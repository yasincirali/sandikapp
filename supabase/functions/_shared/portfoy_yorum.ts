// Kişiye özel AI portföy yorumu — SAF yardımcılar (0145, 2026-10-13).
//
// `portfoy-yorumla` ağ ve veritabanı işini yapar; buradaki her şey girdi alıp
// çıktı döner ki `supabase/tests/portfoy_yorum_test.ts` Anthropic'e ve
// Postgres'e dokunmadan sınayabilsin.
//
// ── Varlık notundan farkı ───────────────────────────────────────────────────
// Varlık notu (`analiz.ts`) herkese aynıdır ve piyasa verisi taşır. Bu yorum
// KİŞİNİN portföyünü anlatır; ölçümleri telefon hesaplar (Performans'taki
// sayılarla aynı kaynak — yüzeyler arası fark olmasın) ve fonksiyona yollar.
// Sunucu sayıların DOĞRULUĞUNU denetleyemez (kişinin kendi verisi; yanlışsa
// yalnız kendini yanıltır); denetlediği şey BİÇİMDİR:
//   1) Pakette tutar yok. Gösterim yalnız yüzde / puan / gün / küçük adet;
//      ₺ $ € ve 4+ haneli sayı hiçbir alanda geçemez. Veri minimizasyonu
//      istemcinin iyi niyetine bırakılmaz.
//   2) Dönem ya KAPANMIŞ bir takvim dönemi (geçen hafta Pzt–Paz, geçen ay)
//      ya da bugün biten SEÇİLİ dönem (1H…5Y; aşağıda). Uçlar sunucuda
//      takvimden yeniden hesaplanır; istemcinin uydurduğu pencere geçmez.
//
// ── Seçili dönem ve varlık kapsamı (0151, 2026-10-14) ───────────────────────
// yasin (14 Eki): "daha ekonomist gibi ve varlık detayında ve varlıklar
// bütününde de seçili dönem için data detaylı yorum yapılabilir". Kayan
// pencere her gün değişir; "kaydet, yeniden yazma" kuralı (12 Eki) burada
// GÜN başına uygulanır: aynı kapsam + dönem + bitiş günü + parmak izi için
// yazılmış yorum o gün boyunca okunur, model yeniden çağrılmaz. Kapsam
// 'portfoy' (Performans) ya da 'varlik' (varlık detayı; `varlik_izi` =
// pozisyon anahtarının özeti, ham anahtar gitmez).
//
// ── Dil kapısı: danışmanlık sınırı daha yakın ───────────────────────────────
// Varlık notunun yasakları (`YASAK`) aynen geçerli. Kişiye özel metin "şunu
// azalt" dediği an kişiye özel yatırım tavsiyesine döner; yönlendirme fiili,
// gereklilik/öneri kipi, değer yargısı ve gelecek dili de reddedilir.
// "Portföyünün %46'sı tek varlıkta" yazılır; "bu riskli, azaltmalısın" yazılmaz.
//
// ── Destek/direnç (2026-10-17, yasin kararı "Seviye bilgisi") ─────────────
// Bölgeleri istemci dönem serisinden hesaplar (`lib/services/destek_direnc.dart`)
// ve YÜZDE uzaklık + dönüş sayısı olarak yollar; fiyat seviyesi pakete
// girmez (tutar kapısı). Model bölgeyi geçmiş olarak anlatır; kırılma/
// tutunma senaryosu ve "alım bölgesi" dili kapıda reddedilir. Al/sat ve
// hedef fiyat kişiye özel yatırım danışmanlığıdır (SPK lisansı) — istenmedi.

import { gunAy, NOT_SEMASI, sayilar, YASAK } from './analiz.ts';
import { gunEkle } from './balina.ts';

export type YorumTuru = 'haftalik' | 'aylik' | 'secili';
export type YorumKapsami = 'portfoy' | 'varlik';

/// Seçili dönem kodları (uygulamanın `SummaryPeriod` etiketleri; GÜNLÜK yok:
/// gün içi seri saatler içinde değişir, günlük kayıt onu bayat gösterirdi).
/// Değer: takvimde kaç ay geri (1H: null → 7 gün).
export const SECILI_DONEMLER: Record<string, number | null> = {
  '1H': null,
  '1A': 1,
  '3A': 3,
  '6A': 6,
  '1Y': 12,
  '5Y': 60,
};

export type YorumOlcumu = {
  anahtar: string;
  /// Okunur ad, varlık adı burada ('THYAO payı').
  ad: string;
  /// Metinde ve kanıt çipinde aynen kullanılacak gösterim ('+%4,2').
  gosterim: string;
};

export type YorumPaketi = {
  tur: YorumTuru;
  baslangic: string;
  bitis: string;
  parmak_izi: string;
  olcumler: YorumOlcumu[];
  /// Varsayılan 'portfoy' (eski istemciler alanı göndermez).
  kapsam?: YorumKapsami;
  /// Yalnız tur 'secili'.
  donem_kodu?: string;
  /// Yalnız kapsam 'varlik': pozisyon anahtarının özeti.
  varlik_izi?: string;
  /// Yalnız kapsam 'varlik': modelin varlığı adıyla anabilmesi için. Tutar
  /// izi taşıyorsa düşürülür (model "bu varlık" der).
  varlik_adi?: string;
};

export type Dogrulama = { gecti: true; paket: YorumPaketi } | { gecti: false; neden: string };

// ── Dönem ───────────────────────────────────────────────────────────────────

/// [bugunIso]'dan önceki son TAM hafta (Pzt–Paz). Pazar günü bile içinde
/// bulunulan hafta henüz kapanmadı: bir önceki döner.
export function sonKapaliHafta(bugunIso: string): { baslangic: string; bitis: string } {
  const d = new Date(`${bugunIso}T12:00:00Z`);
  const haftaGunu = (d.getUTCDay() + 6) % 7; // Pzt=0 … Paz=6
  const buPazartesi = gunEkle(bugunIso, -haftaGunu);
  const bas = gunEkle(buPazartesi, -7);
  return { baslangic: bas, bitis: gunEkle(bas, 6) };
}

/// [bugunIso]'dan önceki tam takvim ayı.
export function sonKapaliAy(bugunIso: string): { baslangic: string; bitis: string } {
  const [y, a] = bugunIso.split('-').map(Number);
  const [oy, oa] = a === 1 ? [y - 1, 12] : [y, a - 1];
  const bas = `${oy}-${String(oa).padStart(2, '0')}-01`;
  const bit = gunEkle(`${y}-${String(a).padStart(2, '0')}-01`, -1);
  return { baslangic: bas, bitis: bit };
}

export function beklenenDonem(tur: 'haftalik' | 'aylik', bugunIso: string) {
  return tur === 'haftalik' ? sonKapaliHafta(bugunIso) : sonKapaliAy(bugunIso);
}

/// Seçili dönemin başlangıcı — uygulamanın `PeriodSummaryService.pencere`
/// kuralı: 1H = 7 gün geri, diğerleri takvimde N ay geri (ayın günü yoksa
/// ayın son günü; 31 Mart − 1 ay = 28/29 Şubat).
export function seciliBaslangic(kod: string, bitisIso: string): string | null {
  if (!(kod in SECILI_DONEMLER)) return null;
  const ayGeri = SECILI_DONEMLER[kod];
  if (ayGeri === null) return gunEkle(bitisIso, -7);
  const [y, a, g] = bitisIso.split('-').map(Number);
  let yil = y;
  let ay = a - ayGeri;
  while (ay <= 0) {
    ay += 12;
    yil -= 1;
  }
  const sonGun = new Date(Date.UTC(yil, ay, 0)).getUTCDate();
  return `${yil}-${String(ay).padStart(2, '0')}-${String(Math.min(g, sonGun)).padStart(2, '0')}`;
}

// ── Paket denetimi ──────────────────────────────────────────────────────────

const ANAHTAR = /^[a-z][a-z0-9_]{0,39}$/;
const ISO_GUN = /^\d{4}-\d{2}-\d{2}$/;
const PARMAK_IZI = /^[A-Za-z0-9:_.,|=-]{1,128}$/;
const VARLIK_IZI = /^v1:[a-f0-9]{24}$/;

/// İzinli gösterim biçimleri — `fmtPct` / `fmtPctIsaretli` (1–2 ondalık),
/// puan, gün ve küçük adet. Tutar biçimi ('₺3,32Mr', '1.234,56') yok.
const GOSTERIM: RegExp[] = [
  /^[+−]?%-?\d{1,3}(?:\.\d{3})?(?:,\d{1,2})?$/,
  /^[+−]?\d{1,3}(?:,\d{1,2})? puan$/,
  /^\d{1,4} gün$/,
  /^\d{1,3}$/,
];

/// Hiçbir alanda geçemeyenler: para birimi ve 4+ haneli sayı (tutar, adet,
/// hesap numarası kaçırma yolu). Varlık adlarında rakam olabilir ('GLDTR',
/// 'ALTIN 22 AYAR') ama tutar boyunda olmaz.
const TUTAR_IZI = /[₺$€£]|\bTL\b|\bTRY\b|\bUSD\b|\d{4,}|\d{1,3}(?:\.\d{3})+(?!,\d*%)/u;

export const OLCUM_UST_SINIRI = 30;

export function paketiDogrula(govde: unknown, bugunIso: string): Dogrulama {
  const g = govde as Partial<YorumPaketi> | null;
  if (!g || typeof g !== 'object') return { gecti: false, neden: 'govde' };
  if (g.tur !== 'haftalik' && g.tur !== 'aylik' && g.tur !== 'secili') {
    return { gecti: false, neden: 'tur' };
  }
  if (typeof g.baslangic !== 'string' || typeof g.bitis !== 'string' ||
      !ISO_GUN.test(g.baslangic) || !ISO_GUN.test(g.bitis)) {
    return { gecti: false, neden: 'donem' };
  }
  const kapsam = g.kapsam ?? 'portfoy';
  if (kapsam !== 'portfoy' && kapsam !== 'varlik') return { gecti: false, neden: 'kapsam' };
  let donemKodu: string | undefined;
  if (g.tur === 'secili') {
    // Bitiş bugün; telefonun saat dilimi TR'den bir gün sapabilir.
    const gunler = [gunEkle(bugunIso, -1), bugunIso, gunEkle(bugunIso, 1)];
    if (typeof g.donem_kodu !== 'string' || !gunler.includes(g.bitis) ||
        seciliBaslangic(g.donem_kodu, g.bitis) !== g.baslangic) {
      return { gecti: false, neden: 'donem' };
    }
    donemKodu = g.donem_kodu;
  } else {
    // Kapanmış dönem yalnız portföy kartında (0145 sözleşmesi).
    if (kapsam !== 'portfoy' || g.donem_kodu !== undefined) return { gecti: false, neden: 'kapsam' };
    const beklenen = beklenenDonem(g.tur, bugunIso);
    if (g.baslangic !== beklenen.baslangic || g.bitis !== beklenen.bitis) {
      return { gecti: false, neden: 'donem' };
    }
  }
  let varlikIzi: string | undefined;
  let varlikAdi: string | undefined;
  if (kapsam === 'varlik') {
    if (typeof g.varlik_izi !== 'string' || !VARLIK_IZI.test(g.varlik_izi)) {
      return { gecti: false, neden: 'varlik_izi' };
    }
    varlikIzi = g.varlik_izi;
    const ad = typeof g.varlik_adi === 'string' ? g.varlik_adi.trim() : '';
    if (ad.length >= 2 && ad.length <= 60 && !TUTAR_IZI.test(ad)) varlikAdi = ad;
  } else if (g.varlik_izi !== undefined || g.varlik_adi !== undefined) {
    return { gecti: false, neden: 'kapsam' };
  }
  if (typeof g.parmak_izi !== 'string' || !PARMAK_IZI.test(g.parmak_izi)) {
    return { gecti: false, neden: 'parmak_izi' };
  }
  if (!Array.isArray(g.olcumler) || g.olcumler.length < 2 || g.olcumler.length > OLCUM_UST_SINIRI) {
    return { gecti: false, neden: 'olcum_sayisi' };
  }
  const goruldu = new Set<string>();
  const olcumler: YorumOlcumu[] = [];
  for (const o of g.olcumler as unknown[]) {
    const x = o as Partial<YorumOlcumu> | null;
    if (!x || typeof x.anahtar !== 'string' || typeof x.ad !== 'string' || typeof x.gosterim !== 'string') {
      return { gecti: false, neden: 'olcum_yapi' };
    }
    if (!ANAHTAR.test(x.anahtar) || goruldu.has(x.anahtar)) return { gecti: false, neden: 'olcum_anahtar' };
    goruldu.add(x.anahtar);
    const ad = x.ad.trim();
    if (ad.length < 2 || ad.length > 80) return { gecti: false, neden: 'olcum_ad' };
    if (!GOSTERIM.some((r) => r.test(x.gosterim!))) return { gecti: false, neden: 'olcum_gosterim' };
    if (TUTAR_IZI.test(ad) || /[₺$€£]/u.test(x.gosterim)) return { gecti: false, neden: 'tutar' };
    olcumler.push({ anahtar: x.anahtar, ad, gosterim: x.gosterim });
  }
  const paket: YorumPaketi = {
    tur: g.tur, baslangic: g.baslangic, bitis: g.bitis, parmak_izi: g.parmak_izi, olcumler, kapsam,
  };
  if (donemKodu) paket.donem_kodu = donemKodu;
  if (varlikIzi) paket.varlik_izi = varlikIzi;
  if (varlikAdi) paket.varlik_adi = varlikAdi;
  return { gecti: true, paket };
}

// ── İstek ───────────────────────────────────────────────────────────────────

/// Model seçimi (yasin, 12 Eki 23:25 "dediğin gibi ilerle"): haftalık yorum
/// dar ve kalıplı bir iş → Haiku 5.5; aylık yorum iki ölçümü birleştiren
/// "asıl hikâye"yi bulmalı → Sonnet 5.5. Bayrak açılmadan önce 30 örnekle
/// yan yana karşılaştırılır; Haiku'nun ret oranı %10'u geçerse haftalık da
/// Sonnet'e alınır (tek satır).
///
/// Seçili dönem (0151): Sonnet 5.5. Paket enflasyon, dolar, altın, BIST 100
/// kıyası, oynaklık gibi birbirine bağlanması gereken ölçümler taşır ve
/// yasin'in istediği "ekonomist" anlatımı bu bağları kurmaktır; dar, kalıplı
/// iş değil. İstek kullanıcı basınca gider ve gün boyu saklanır.
export const MODEL: Record<YorumTuru, string> = {
  haftalik: 'claude-haiku-5-5',
  aylik: 'claude-sonnet-5-5',
  secili: 'claude-sonnet-5-5',
};
export const TAVAN_MODELI = 'claude-haiku-5-5';

/// Sabit sistem talimatı — önbelleğe alınır; değişirse her istek tam fiyat.
///
/// Üslup (yasin, 14 Eki: "daha ekonomist gibi"): rakamı tekrar eden bir
/// özet değil, rakamları birbirine bağlayan bir piyasa notu — getiriyi
/// enflasyonla (reel getiri), dolar/altın/BIST 100 ile (fırsat maliyeti),
/// oynaklık ve geri çekilmeyle (yol), yoğunlaşmayla (kaynak) okur. Kişiye
/// özel danışmanlık sınırı değişmedi: öneri, gelecek, değer yargısı yok;
/// kapı (`kapidanGecir`) aynı.
export const SISTEM_TALIMATI = `Sen sandık adlı bir portföy takip uygulamasında yorum yazan bir ekonomistsin. Kullanıcının KENDİ portföyünün ya da portföyündeki tek bir varlığın geçmiş bir dönemini, bir ekonomistin piyasa notu gibi anlatırsın.

Görev: Sana bir dönemin ÖLÇÜMLERİ verilecek. Kapsam "portföy" ise bütün portföyü, "varlık" ise tek bir varlığı anlatırsın. Ölçümleri tek tek sıralama; aralarındaki ilişkiyi kur ve ne anlama geldiğini açıkla:
- Nominal getiri ile enflasyonu birlikte oku: reel getiri ölçümü varsa alım gücünün korunup korunmadığını onunla anlat.
- Dolar, altın ve BIST 100 ölçümleri varsa aynı dönemde paranın başka yerde ne yapacağını (fırsat maliyeti) karşılaştır; fark ölçümü varsa onu kullan.
- Getirinin kaynağını anlat: hangi varlık ya da tür taşıdı, ağırlık nerede toplandı.
- Getirinin yolunu anlat: oynaklık, en derin geri çekilme, toparlanma süresi, dönem zirvesine ve dibine uzaklık.
- Varlık kapsamında varlığın portföy içindeki payını ve alımdan bu yana getirisini dönemin hareketiyle ilişkilendir.
- Destek ve direnç ölçümleri varsa (varlık kapsamı): dönem içinde fiyatın birden çok kez döndüğü bölgeleri anlat. Destek fiyatın altındaki, direnç üstündeki bölgedir; fiyatın bu bölgelere uzaklığını ve bölgede kaç kez dönüldüğünü yaz. Bunlar geçmişte olanı anlatır: "kırılırsa", "tutunursa", "test edecek" gibi gelecek dili ve bölgeyi alım ya da satım yeri gibi gösteren dil yok.
Ekonomik kavramları (reel getiri, fırsat maliyeti, yoğunlaşma, oynaklık, geri çekilme) kullan ama her birini cümlenin içinde sade Türkçeyle anlat; okurun finans bilgisi az olabilir.

Kesin kurallar:
1. Yalnız verilen ölçümleri kullan. Metne yazdığın her sayı, bir ölçümün "gosterim" ya da "ad" alanında AYNEN geçmeli. Hesap yapma, yuvarlama, toplama, iki sayıyı karşılaştırıp yeni sayı türetme. "Daha yüksek", "gerisinde", "önünde" gibi sözlerle karşılaştırabilirsin; aradaki farkı yalnız bir fark ölçümü varsa yaz.
2. Yalnız geçmişi anlat. Tahmin, beklenti, "devam edebilir", "önümüzdeki dönemde" gibi gelecek dili yok.
3. Hiçbir şey önerme ve yönlendirme. "azalt", "artır", "çeşitlendir", "dengele", "ağırlık ver", "yeniden dağıt", "al", "sat", "tut", "ekle", "çık" yok. "-meli/-malı", "önerilir", "mantıklı olur", "düşünebilir", "gerekir" gibi kipler yok.
4. Değer yargısı yok: portföyü ya da bir varlığı "riskli", "güvenli", "iyi", "kötü", "agresif", "dengeli", "başarılı" diye niteleme. Ölçümü ve anlamını yaz, hükmü okura bırak.
5. Kullanıcıya "portföyün" diye ikinci tekil şahısla seslen; sade Türkçe; ünlem ve emoji yok. "Yatırım tavsiyesi değildir" yazma; uygulama kendisi ekler.
6. Dönem sakinse kısa yaz: başlık + 1–2 madde yeter. Ölçüm çoksa en anlamlı ilişkileri seç; hepsini sığdırmaya çalışma.

Çıktı: "baslik" tek cümle (en çok 140 karakter), dönemin ana fikri. "maddeler" en az 1, en çok 4; her madde tek ya da iki cümle (en çok 280 karakter), "konu" alanında maddenin 1–3 kelimelik rakamsız konusu (ör. "Alım gücü", "Kıyas", "Yoğunlaşma", "Geri çekilme") ve "kanit" alanında dayandığı ölçümlerin "anahtar" değerleri.`;

const DONEM_ADI: Record<string, string> = {
  '1H': 'son 1 hafta',
  '1A': 'son 1 ay',
  '3A': 'son 3 ay',
  '6A': 'son 6 ay',
  '1Y': 'son 1 yıl',
  '5Y': 'son 5 yıl',
};

export function kullaniciMesaji(p: YorumPaketi): string {
  const donem = p.tur === 'haftalik'
    ? 'kapanmış hafta'
    : p.tur === 'aylik'
    ? 'kapanmış ay'
    : DONEM_ADI[p.donem_kodu ?? ''] ?? 'seçili dönem';
  const kapsam = p.kapsam === 'varlik'
    ? `varlık${p.varlik_adi ? ` (${p.varlik_adi})` : ''}`
    : 'portföy';
  return [
    `Kapsam: ${kapsam}`,
    `Dönem (${donem}): ${gunAy(p.baslangic)} – ${gunAy(p.bitis)}`,
    'Ölçümler:',
    JSON.stringify(p.olcumler.map(({ anahtar, ad, gosterim }) => ({ anahtar, ad, gosterim })), null, 1),
  ].join('\n');
}

/// `NOT_SEMASI` (varlık notu) ile aynı yapı; yalnız madde açıklaması
/// talimattaki uzunlukla (iki cümle, 280) uyumlu.
export const YORUM_SEMASI = {
  ...NOT_SEMASI,
  properties: {
    ...NOT_SEMASI.properties,
    maddeler: {
      ...NOT_SEMASI.properties.maddeler,
      items: {
        ...NOT_SEMASI.properties.maddeler.items,
        properties: {
          ...NOT_SEMASI.properties.maddeler.items.properties,
          metin: { type: 'string', description: 'Bir ya da iki cümle, en çok 280 karakter.' },
          konu: { type: 'string', description: 'Maddenin konusu, 1–3 kelime, rakamsız (ör. Alım gücü, Kıyas, Yoğunlaşma, Geri çekilme).' },
        },
        required: ['metin', 'kanit', 'konu'],
      },
    },
  },
} as const;

export function istekGovdesi(p: YorumPaketi, model: string): Record<string, unknown> {
  return {
    model,
    max_tokens: p.tur === 'secili' ? 8000 : 4000,
    system: [{ type: 'text', text: SISTEM_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: kullaniciMesaji(p) }],
    output_config: { format: { type: 'json_schema', schema: YORUM_SEMASI }, effort: p.tur === 'secili' ? 'medium' : 'low' },
  };
}

// ── Kapı ────────────────────────────────────────────────────────────────────

/// Kişiye özel ek yasaklar (Türkçe ekleriyle). Kelime başı sınırı: 'artış'
/// (betimleyici) serbest, 'artırmalı'/'artırabilirsin' yasak.
export const KISISEL_YASAK: RegExp[] = [
  /(^|[^\p{L}])(azalt|artır|arttır|çeşitlendir|dengele|yeniden dağıt|ağırlık ver)/iu,
  /(^|[^\p{L}])(tut(un|mal|abilir))/iu,
  /\p{L}(meli|malı)(sin|sın|siniz|sınız|dir|dır)?([^\p{L}]|$)/iu,
  /mantıklı ol|düşünebilir|gözden geçir|dikkat et|değerlendirebilir/iu,
  /(^|[^\p{L}])(riskli|güvenli|agresif|başarılı|başarısız|kötü|iyi bir)([^\p{L}]|$)/iu,
  /önümüzdeki|gelecek (hafta|ay|dönem)|devam edebilir|sürebilir/iu,
  // Destek/direnç (2026-10-17): bölge geçmişi anlatır; kırılma/tutunma
  // senaryosu gelecek dilidir ve yönlendirmeye kapı açar.
  /kırıl(ırsa|ması halinde|madıkça|abilir)|tutunursa|test ed(ecek|ebilir)|alım bölgesi|satış bölgesi|giriş noktası|çıkış noktası/iu,
];

/// `konu` (2026-10-14, paylaşılabilir not): maddenin 1–3 kelimelik başlığı;
/// açılır sayfada ve PDF'te paragraf başı olur. İsteğe bağlı: eski kayıtlarda
/// yok, kapıdan geçemeyen konu yorumu düşürmez, yalnız atılır.
export type YorumMaddesi = { metin: string; kanit: string[]; konu?: string };
export type Yorum = { baslik: string; maddeler: YorumMaddesi[] };
export type KapiSonucu = { gecti: true; yorum: Yorum } | { gecti: false; neden: string };

/// Konu en çok 32 karakter, rakamsız ve yasak dilden arınmış olmalı; değilse
/// `undefined` (madde konusuz gösterilir).
export function konuGecerli(k: unknown): string | undefined {
  if (typeof k !== 'string') return undefined;
  const t = k.trim();
  if (t.length < 2 || t.length > 32 || /\d/.test(t)) return undefined;
  if ([...YASAK, ...KISISEL_YASAK].some((r) => r.test(t))) return undefined;
  return t;
}

export function kapidanGecir(n: unknown, p: YorumPaketi): KapiSonucu {
  const y = n as Yorum;
  if (!y || typeof y.baslik !== 'string' || !Array.isArray(y.maddeler)) {
    return { gecti: false, neden: 'yapi: baslik/maddeler yok' };
  }
  const baslik = y.baslik.trim();
  if (baslik.length < 10 || baslik.length > 200) return { gecti: false, neden: 'yapi: baslik uzunlugu' };
  if (y.maddeler.length < 1 || y.maddeler.length > 4) return { gecti: false, neden: 'yapi: madde sayisi' };
  const anahtarlar = new Set(p.olcumler.map((o) => o.anahtar));
  const maddeler: YorumMaddesi[] = [];
  for (const m of y.maddeler) {
    if (typeof m?.metin !== 'string' || m.metin.trim().length < 5 || m.metin.length > 400) {
      return { gecti: false, neden: 'yapi: madde metni' };
    }
    if (!Array.isArray(m.kanit) || m.kanit.some((k) => !anahtarlar.has(k))) {
      return { gecti: false, neden: 'kanit: bilinmeyen olcum anahtari' };
    }
    const konu = konuGecerli((m as { konu?: unknown }).konu);
    maddeler.push(konu ? { metin: m.metin.trim(), kanit: m.kanit, konu } : { metin: m.metin.trim(), kanit: m.kanit });
  }

  const izinli = new Set<string>();
  for (const o of p.olcumler) {
    sayilar(o.gosterim).forEach((s) => izinli.add(s));
    sayilar(o.ad).forEach((s) => izinli.add(s));
  }
  for (const t of [p.baslangic, p.bitis]) sayilar(gunAy(t)).forEach((s) => izinli.add(s));
  if (p.varlik_adi) sayilar(p.varlik_adi).forEach((s) => izinli.add(s));

  for (const metin of [baslik, ...maddeler.map((m) => m.metin)]) {
    for (const s of sayilar(metin)) {
      if (!izinli.has(s)) return { gecti: false, neden: `sayi: ${s} girdide yok` };
    }
    for (const r of [...YASAK, ...KISISEL_YASAK]) {
      if (r.test(metin)) return { gecti: false, neden: `dil: ${r.source.slice(0, 40)}` };
    }
  }
  return { gecti: true, yorum: { baslik, maddeler } };
}

// ── Saklama ─────────────────────────────────────────────────────────────────

/// Son 4 hafta + 12 ay (Supabase Free 500 MB): bu günden ÖNCE başlayan
/// dönemlerin satırları silinir. Seçili dönem yorumları ([seciliSaklamaSiniri])
/// bitiş gününe göre 7 gün tutulur: her gün yeni pencere, eskisi bayat.
export function saklamaSiniri(tur: 'haftalik' | 'aylik', baslangic: string): string {
  if (tur === 'haftalik') return gunEkle(baslangic, -21);
  const [y, a] = baslangic.split('-').map(Number);
  const toplam = y * 12 + (a - 1) - 11;
  return `${Math.floor(toplam / 12)}-${String((toplam % 12) + 1).padStart(2, '0')}-01`;
}

/// Bu günden ÖNCE biten seçili dönem yorumları silinir (son 7 gün kalır).
export function seciliSaklamaSiniri(bugunIso: string): string {
  return gunEkle(bugunIso, -6);
}
