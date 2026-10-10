// Fon X-Ray, Katman A — KAP Portföy Dağılım Raporu kalemleri, SAF
// yardımcılar ve BEŞ KONTROL (0132).
//
// `fon-kalem-raporu/index.ts` ağ (KAP, TEFAS, model) ve veritabanı işini
// yapar; buradakiler girdi alıp çıktı döner ki `supabase/tests/
// fon_kalem_test.ts` hepsini ağsız sınasın. PDF'ten metin çıkarma ayrı
// (`pdf_metin.ts`): npm bağımlılığı test koşusuna girmesin.
//
// ── Kanıt zinciri ───────────────────────────────────────────────────────────
// Kalemleri model ayıklar; doğruluğu model değil KONTROLLER belirler
// (araştırma raporu "Sonuç"). Biri düşerse belgenin TAMAMI reddedilir —
// yarım doğru bir listeyi göstermek, hiç göstermemekten kötü (fonlu kararı):
//   1. metin  — her ağırlık PDF metninde AYNEN geçer; kodu olan kalemde o
//               kodun bir geçişinden sonraki pencerede.
//   2. toplam — ağırlıklar toplamı %100 ± 1,5.
//   3. tefas  — hisse toplamı aynı ay sonu TEFAS `hs` (yabancı hisse `yhs`)
//               sütunuyla ± 3 puan. TEFAS satırı yoksa doğrulanamaz → red.
//   4. bant   — fon unvanından okunan türün yasal alt sınırı (hisse
//               yoğun ≥ %80 vb.); bilgi vermeyen türlerde (değişken,
//               serbest, fon sepeti) geçer.
//   5. şema   — model yanıtı beklenen biçimde (ilk uygulanan).

export const KALEM_TURLERI = [
  'hisse',
  'yabanci_hisse',
  'borclanma',
  'para_piyasasi',
  'mevduat',
  'kiymetli_maden',
  'fon',
  'diger',
] as const;
export type KalemTuru = typeof KALEM_TURLERI[number];

/// Modelin döndürdüğü tek satır. `agirlik_metni` PDF'te yazan dizgi
/// ("2,32"); kontrol 1 onu metinde arar.
export type HamKalem = {
  ad: string;
  kod: string;
  tur: KalemTuru;
  agirlik: number;
  agirlik_metni: string;
};

/// Tabloya yazılan satır (0132 `kalemler`).
export type Kalem = { ad: string; kod: string; tur: KalemTuru; agirlik: number };

export const TOPLAM_TOLERANS = 1.5;
export const TEFAS_TOLERANS = 3;
/// Yasal alt sınır %80; rapor iki ondalık ve FPD/FTD farkı için yarım puan.
export const BANT_ALT = 79.5;
/// Pencere: kod satırından sonra ağırlığın aranacağı karakter sayısı. KAP
/// düzeninde kod, alt alta kırılmış unvan satırları ve sayılar ~150-400
/// karakter içinde (BTE Eylül 2026 raporu).
export const KOD_PENCERESI = 800;

// ── Model isteği ────────────────────────────────────────────────────────────

export const KALEM_SEMASI = {
  type: 'object',
  properties: {
    kalemler: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          ad: { type: 'string', description: 'İhraççı / kalem adı, raporda yazdığı gibi' },
          kod: { type: 'string', description: 'BIST kodu ya da yabancı borsa kodu (ör. ASELS, AAPL US); yoksa boş' },
          tur: { type: 'string', enum: [...KALEM_TURLERI] },
          agirlik: { type: 'number', description: 'Fon portföy değerine (FPD) göre yüzde' },
          agirlik_metni: { type: 'string', description: 'Ağırlığın PDF metninde yazdığı dizgi, aynen (ör. "2,32")' },
        },
        required: ['ad', 'kod', 'tur', 'agirlik', 'agirlik_metni'],
        additionalProperties: false,
      },
    },
  },
  required: ['kalemler'],
  additionalProperties: false,
} as const;

export const SISTEM_TALIMATI = [
  'Bir Türk yatırım/emeklilik fonunun KAP "Portföy Dağılım Raporu" PDF metnini alıyorsun.',
  'Görev: "FON PORTFÖY DEĞERİ TABLOSU"ndaki her kalemi (hisse, tahvil, bono, kira sertifikası,',
  'repo/ters repo, para piyasası, mevduat, katılma hesabı, kıymetli maden, fon payı, türev teminatı)',
  'ayrı satır olarak çıkar.',
  'Kurallar:',
  '- Ağırlık, "TOPLAM (FPD\'ye GÖRE)" yüzdesidir (fon portföy değerine göre). Grup yüzdesi ya da FTD',
  '  yüzdesi DEĞİL. Yalnız FTD varsa onu kullan.',
  '- agirlik_metni: o yüzdenin metinde yazdığı dizgi, AYNEN (virgül/nokta dahil). Hesaplama yapma,',
  '  yuvarlama yapma, birleştirme yapma: aynı kalem birden çok satırdaysa her satırı ayrı ver.',
  '- Grup toplamı, genel toplam, temettü tablosu, alım-satım işlemleri tablosu kalem DEĞİLDİR.',
  '- tur: BIST hissesi "hisse"; yabancı borsada hisse/ADR "yabanci_hisse"; tahvil/bono/kira sertifikası/',
  '  eurobond "borclanma"; repo/ters repo/Takasbank veya BİST para piyasası "para_piyasasi"; mevduat/',
  '  katılma hesabı "mevduat"; altın/gümüş ve kıymetli maden cinsinden borçlanma/kira sertifikası',
  '  "kiymetli_maden"; yatırım fonu/BYF payı "fon"; geri kalan (VİOP teminatı, opsiyon, diğer) "diger".',
  '- kod: hissede borsa kodu (ASELS, AAPL US); tahvil/bonoda ISIN; yoksa boş dizgi.',
  '- Metinde olmayan hiçbir sayı ya da kalem yazma. Tablo okunamıyorsa boş liste döndür.',
].join('\n');

export function istekGovdesi(metin: string, fonKodu: string, model: string): Record<string, unknown> {
  return {
    model,
    max_tokens: 16000,
    system: [{ type: 'text', text: SISTEM_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: `Fon kodu: ${fonKodu}\n\n<rapor>\n${metin}\n</rapor>` }],
    output_config: { effort: 'low', format: { type: 'json_schema', schema: KALEM_SEMASI } },
  };
}

// ── Sayı ve metin ───────────────────────────────────────────────────────────

/// TR (`1.234,56`) ya da US (`1,234.56`) biçimli sayı. Tanınmazsa null.
export function sayiOku(ham: string): number | null {
  let s = String(ham ?? '').trim().replace(/^%\s*/, '').replace(/\s*%$/, '');
  if (!/^-?[\d.,]+$/.test(s)) return null;
  const virgul = s.lastIndexOf(',');
  const nokta = s.lastIndexOf('.');
  if (virgul >= 0 && nokta >= 0) {
    // Son ayraç ondalıktır.
    s = virgul > nokta ? s.replaceAll('.', '').replace(',', '.') : s.replaceAll(',', '');
  } else if (virgul >= 0) {
    // Tek tür ayraç: birden çoksa binlik, tekse ondalık (rapor yüzdeleri).
    s = (s.match(/,/g)!.length > 1) ? s.replaceAll(',', '') : s.replace(',', '.');
  } else if (nokta >= 0 && (s.match(/\./g)!.length > 1)) {
    s = s.replaceAll('.', '');
  }
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

/// Boşlukları teke indirir (PDF metninde satır/kolon araları değişken).
export function metniNormalle(s: string): string {
  return String(s ?? '').replace(/\s+/g, ' ').trim();
}

/// Metin katmanı var mı: vektör çizilmiş (İş Portföy) ya da taranmış
/// PDF'te ya hiç metin yoktur ya da birkaç başlık kalır. En az 300
/// karakter ve 10 ondalıklı sayı.
export function metinYeterliMi(metin: string): boolean {
  const m = metniNormalle(metin);
  if (m.length < 300) return false;
  return (m.match(/\d+[.,]\d{2}\b/g) ?? []).length >= 10;
}

/// KAP dosya ucu PDF'i Java serileştirme sarmalında döndürür; gerçek
/// içerik `%PDF-` ofsetinden başlar. Yoksa null (PDF değil).
export function pdfBaytlari(b: Uint8Array): Uint8Array | null {
  const imza = [0x25, 0x50, 0x44, 0x46, 0x2d]; // %PDF-
  const ust = Math.min(b.length - imza.length, 4096);
  for (let i = 0; i <= ust; i++) {
    let tamam = true;
    for (let j = 0; j < imza.length; j++) {
      if (b[i + j] !== imza[j]) { tamam = false; break; }
    }
    if (tamam) return b.subarray(i);
  }
  return null;
}

// ── Kontroller ──────────────────────────────────────────────────────────────

export type KontrolAdi = 'sema' | 'metin' | 'toplam' | 'tefas' | 'bant';
export type Sonuc =
  | { gecti: true; kalemler: Kalem[]; ozet: Record<string, unknown> }
  | { gecti: false; kontrol: KontrolAdi; neden: string; ozet: Record<string, unknown> };

/// 5. Şema: model yanıtı → HamKalem[]. Tek bozuk satır bütün yanıtı düşürür.
export function semaKontrolu(ham: unknown): { ok: true; kalemler: HamKalem[] } | { ok: false; neden: string } {
  const liste = (ham as { kalemler?: unknown } | null)?.kalemler;
  if (!Array.isArray(liste)) return { ok: false, neden: 'kalemler_dizi_degil' };
  if (liste.length === 0) return { ok: false, neden: 'bos_liste' };
  if (liste.length > 400) return { ok: false, neden: 'cok_kalem' };
  const out: HamKalem[] = [];
  for (const x of liste) {
    if (typeof x !== 'object' || x === null) return { ok: false, neden: 'satir_nesne_degil' };
    const o = x as Record<string, unknown>;
    const ad = typeof o.ad === 'string' ? o.ad.trim() : '';
    const kod = typeof o.kod === 'string' ? o.kod.trim() : null;
    const tur = o.tur as KalemTuru;
    const agirlik = o.agirlik;
    const metin = typeof o.agirlik_metni === 'string' ? o.agirlik_metni.trim() : '';
    if (ad.length === 0 || ad.length > 160) return { ok: false, neden: 'ad' };
    if (kod === null || kod.length > 24) return { ok: false, neden: 'kod' };
    if (!KALEM_TURLERI.includes(tur)) return { ok: false, neden: 'tur' };
    if (typeof agirlik !== 'number' || !Number.isFinite(agirlik) || agirlik <= 0 || agirlik > 100) {
      return { ok: false, neden: 'agirlik' };
    }
    if (metin.length === 0 || metin.length > 16) return { ok: false, neden: 'agirlik_metni' };
    out.push({ ad, kod, tur, agirlik, agirlik_metni: metin });
  }
  return { ok: true, kalemler: out };
}

/// 1. Metin: ağırlık dizgisi PDF metninde aynen geçer, sayısal değeri
/// `agirlik`'a eşittir; kod verilmişse kodun bir geçişinden sonraki
/// [KOD_PENCERESI] içinde geçer (başka satırın sayısıyla eşleşmesin).
export function metinKontrolu(kalemler: HamKalem[], pdfMetni: string): string | null {
  const metin = metniNormalle(pdfMetni);
  for (const k of kalemler) {
    const deger = sayiOku(k.agirlik_metni);
    if (deger === null || Math.abs(deger - k.agirlik) > 0.005) return `deger_uyusmuyor:${k.ad}`;
    if (!sayiGeciyor(metin, k.agirlik_metni, 0, metin.length)) return `metinde_yok:${k.ad}`;
    if (k.kod.length > 0) {
      const kod = metniNormalle(k.kod);
      let bulundu = false;
      let i = metin.indexOf(kod);
      if (i < 0) return `kod_metinde_yok:${k.kod}`;
      while (i >= 0 && !bulundu) {
        bulundu = sayiGeciyor(metin, k.agirlik_metni, i + kod.length, i + kod.length + KOD_PENCERESI);
        i = metin.indexOf(kod, i + 1);
      }
      if (!bulundu) return `kodun_yaninda_yok:${k.kod}`;
    }
  }
  return null;
}

/// [aranan] sayı dizgisi [bas, son) aralığında bir sayının TAMAMI olarak
/// geçiyor mu ("2,32" "12,32" ya da "2,325" içinde sayılmaz).
function sayiGeciyor(metin: string, aranan: string, bas: number, son: number): boolean {
  const parca = metin.slice(Math.max(0, bas), Math.min(metin.length, son));
  let i = parca.indexOf(aranan);
  while (i >= 0) {
    const once = i > 0 ? parca[i - 1] : ' ';
    const sonra = i + aranan.length < parca.length ? parca[i + aranan.length] : ' ';
    const sinir = (c: string) => !/[\d.,]/.test(c);
    // Sondaki nokta/virgül cümle noktalaması olabilir: ardından rakam yoksa sınır.
    const sonraTamam = sinir(sonra) ||
      (/[.,]/.test(sonra) && !/\d/.test(parca[i + aranan.length + 1] ?? ' '));
    if (sinir(once) && sonraTamam) return true;
    i = parca.indexOf(aranan, i + 1);
  }
  return false;
}

const toplamOf = (kalemler: { agirlik: number }[]) => kalemler.reduce((t, k) => t + k.agirlik, 0);
const turToplami = (kalemler: { tur: KalemTuru; agirlik: number }[], tur: KalemTuru) =>
  toplamOf(kalemler.filter((k) => k.tur === tur));

/// 2. Toplam %100 ± [TOPLAM_TOLERANS].
export function toplamKontrolu(kalemler: { agirlik: number }[]): string | null {
  const t = toplamOf(kalemler);
  return Math.abs(t - 100) <= TOPLAM_TOLERANS ? null : `toplam:${t.toFixed(2)}`;
}

/// 3. TEFAS ay sonu: hisse ve yabancı hisse toplamları ± [TEFAS_TOLERANS].
/// TEFAS satırı yoksa doğrulanamaz → red.
export function tefasKontrolu(
  kalemler: { tur: KalemTuru; agirlik: number }[],
  tefas: Record<string, number> | null,
): string | null {
  if (!tefas) return 'tefas_satiri_yok';
  const hs = tefas.hs ?? 0;
  const yhs = tefas.yhs ?? 0;
  const h = turToplami(kalemler, 'hisse');
  const y = turToplami(kalemler, 'yabanci_hisse');
  if (Math.abs(h - hs) > TEFAS_TOLERANS) return `hisse:${h.toFixed(2)}~${hs}`;
  if (Math.abs(y - yhs) > TEFAS_TOLERANS) return `yabanci_hisse:${y.toFixed(2)}~${yhs}`;
  return null;
}

export type FonTuru =
  | 'hisse_yogun'
  | 'yabanci_hisse'
  | 'kiymetli_maden'
  | 'borclanma'
  | 'para_piyasasi'
  | 'bilgisiz';

/// Unvandan yasal tür. Sıra önemli: "YABANCI HİSSE" "HİSSE"den önce;
/// değişken/serbest/fon sepeti türü ne yazarsa yazsın bant bilgisi taşımaz.
export function fonTuru(unvan: string | null | undefined): FonTuru {
  const u = String(unvan ?? '').toLocaleUpperCase('tr');
  if (/DEĞİŞKEN|SERBEST|FON SEPETİ|KARMA|ÇOKLU VARLIK/.test(u)) return 'bilgisiz';
  if (/PARA PİYASASI/.test(u)) return 'para_piyasasi';
  if (/YABANCI HİSSE/.test(u)) return 'yabanci_hisse';
  if (/HİSSE SENEDİ/.test(u)) return 'hisse_yogun';
  if (/ALTIN|KIYMETLİ MADEN|GÜMÜŞ/.test(u)) return 'kiymetli_maden';
  if (/BORÇLANMA ARAÇLARI/.test(u)) return 'borclanma';
  return 'bilgisiz';
}

/// 4. Yasal bant (taban, nokta değil).
export function bantKontrolu(
  kalemler: { tur: KalemTuru; agirlik: number }[],
  unvan: string | null | undefined,
): string | null {
  const tur = fonTuru(unvan);
  const t = (x: KalemTuru) => turToplami(kalemler, x);
  switch (tur) {
    case 'hisse_yogun':
      return t('hisse') >= BANT_ALT ? null : `hisse_yogun:${t('hisse').toFixed(2)}`;
    case 'yabanci_hisse':
      return t('yabanci_hisse') >= BANT_ALT ? null : `yabanci_hisse:${t('yabanci_hisse').toFixed(2)}`;
    case 'kiymetli_maden':
      return t('kiymetli_maden') >= BANT_ALT ? null : `kiymetli_maden:${t('kiymetli_maden').toFixed(2)}`;
    case 'borclanma':
      return t('borclanma') >= BANT_ALT ? null : `borclanma:${t('borclanma').toFixed(2)}`;
    case 'para_piyasasi': {
      // Para piyasası fonu hisse tutamaz.
      const h = t('hisse') + t('yabanci_hisse');
      return h <= 0.5 ? null : `para_piyasasi_hisse:${h.toFixed(2)}`;
    }
    default:
      return null;
  }
}

/// Aynı kalemin lot satırları (kod, yoksa ad + tür) tek satıra; ağırlığa
/// göre büyükten küçüğe. Toplama dışında sayıya dokunulmaz.
export function birlestir(kalemler: HamKalem[]): Kalem[] {
  const m = new Map<string, Kalem>();
  for (const k of kalemler) {
    const anahtar = `${k.tur}|${k.kod.length > 0 ? k.kod.toUpperCase() : k.ad.toLocaleUpperCase('tr')}`;
    const o = m.get(anahtar);
    if (o) o.agirlik = Math.round((o.agirlik + k.agirlik) * 1e4) / 1e4;
    else m.set(anahtar, { ad: k.ad, kod: k.kod, tur: k.tur, agirlik: k.agirlik });
  }
  return [...m.values()].sort((a, b) => b.agirlik - a.agirlik || a.ad.localeCompare(b.ad));
}

/// Beş kontrol, sırayla; ilk düşen belgenin tamamını reddeder.
export function dogrula(girdi: {
  ham: unknown;
  pdfMetni: string;
  tefas: Record<string, number> | null;
  unvan: string | null | undefined;
}): Sonuc {
  const sema = semaKontrolu(girdi.ham);
  if (!sema.ok) return { gecti: false, kontrol: 'sema', neden: sema.neden, ozet: {} };
  const ks = sema.kalemler;
  const ozet: Record<string, unknown> = {
    kalem: ks.length,
    toplam: Math.round(toplamOf(ks) * 100) / 100,
    hisse_toplam: Math.round(turToplami(ks, 'hisse') * 100) / 100,
    yabanci_hisse_toplam: Math.round(turToplami(ks, 'yabanci_hisse') * 100) / 100,
    tefas_hs: girdi.tefas?.hs ?? null,
    tefas_yhs: girdi.tefas?.yhs ?? null,
    fon_turu: fonTuru(girdi.unvan),
  };
  const sirali: [KontrolAdi, () => string | null][] = [
    ['metin', () => metinKontrolu(ks, girdi.pdfMetni)],
    ['toplam', () => toplamKontrolu(ks)],
    ['tefas', () => tefasKontrolu(ks, girdi.tefas)],
    ['bant', () => bantKontrolu(ks, girdi.unvan)],
  ];
  for (const [ad, f] of sirali) {
    const neden = f();
    if (neden !== null) return { gecti: false, kontrol: ad, neden, ozet };
  }
  return { gecti: true, kalemler: birlestir(ks), ozet };
}

// ── KAP liste ve dönem ──────────────────────────────────────────────────────

export const KAP_TABAN = 'https://www.kap.org.tr';
/// Yanıt bu sayıda satırda kesiliyor (doğrulandı 2026-10-10).
export const KAP_LISTE_USTU = 2000;

export type PdrSatiri = { fon_kodu: string; index: number; yil: number; ay: number };

const PDR_KONU = /portf[öo]y\s+da[ğg][ıi]l[ıi]m\s+raporu/i;

/// Liste yanıtından Portföy Dağılım Raporu satırları.
export function pdrSatirlari(liste: unknown): PdrSatiri[] {
  if (!Array.isArray(liste)) return [];
  const out: PdrSatiri[] = [];
  for (const x of liste) {
    if (typeof x !== 'object' || x === null) continue;
    const o = x as Record<string, unknown>;
    if (!PDR_KONU.test(String(o.subject ?? '').normalize('NFC'))) continue;
    const kod = String(o.fundCode ?? '').trim().toUpperCase();
    const index = Number(o.disclosureIndex);
    const yil = Number(o.year);
    const ay = Number(o.period);
    if (!/^[A-Z0-9]{2,8}$/.test(kod) || !Number.isInteger(index) || index <= 0) continue;
    if (!Number.isInteger(yil) || !Number.isInteger(ay) || ay < 1 || ay > 12) continue;
    out.push({ fon_kodu: kod, index, yil, ay });
  }
  return out;
}

/// Fon başına dönemin EN YENİ bildirimi (düzeltme bildirimi eskisini ezer).
export function donemBildirimleri(satirlar: PdrSatiri[], yil: number, ay: number): Map<string, number> {
  const m = new Map<string, number>();
  for (const s of satirlar) {
    if (s.yil !== yil || s.ay !== ay) continue;
    if ((m.get(s.fon_kodu) ?? 0) < s.index) m.set(s.fon_kodu, s.index);
  }
  return m;
}

/// [bugun] (`YYYY-MM-DD`, TR) için raporlanan dönem: önceki ayın son günü.
export function oncekiAySonu(bugun: string): { donem: string; yil: number; ay: number } {
  const [y, m] = bugun.split('-').map(Number);
  const yil = m === 1 ? y - 1 : y;
  const ay = m === 1 ? 12 : m - 1;
  const son = new Date(Date.UTC(yil, ay, 0)).getUTCDate();
  return { donem: `${yil}-${String(ay).padStart(2, '0')}-${String(son).padStart(2, '0')}`, yil, ay };
}

/// [donem]'den sonraki günden [bugun]'e kadar (dahil) günler.
export function taranacakGunler(donem: string, bugun: string): string[] {
  const out: string[] = [];
  const d = new Date(`${donem}T00:00:00Z`);
  for (let i = 0; i < 40; i++) {
    d.setUTCDate(d.getUTCDate() + 1);
    const g = d.toISOString().slice(0, 10);
    if (g > bugun) break;
    out.push(g);
  }
  return out;
}

/// Önbellekteki gün kesin mi: gün BİTTİKTEN sonra (TR gece yarısı = önceki
/// günün 21:00 UTC'si) taranmışsa bir daha istenmez.
export function taramaKesinMi(gun: string, tarandi: string): boolean {
  const gunSonu = new Date(`${gun}T21:00:00Z`).getTime(); // TR 24:00
  return new Date(tarandi).getTime() >= gunSonu;
}

export function ekPdfNesnesi(ekDetayi: unknown): string | null {
  const ilk = Array.isArray(ekDetayi) ? ekDetayi[0] : null;
  const ekler = (ilk as { attachments?: unknown } | null)?.attachments;
  if (!Array.isArray(ekler)) return null;
  for (const e of ekler) {
    const o = e as Record<string, unknown>;
    const ad = `${o.fileExtension ?? ''} ${o.fileName ?? ''}`.toLowerCase();
    if (/pdf/.test(ad) && typeof o.objId === 'string' && /^[a-f0-9]{16,64}$/i.test(o.objId)) return o.objId;
  }
  return null;
}

export function bildirimAdresi(index: number): string {
  return `${KAP_TABAN}/tr/Bildirim/${index}`;
}
