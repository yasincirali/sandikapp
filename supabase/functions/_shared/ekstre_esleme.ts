// Ekstre AI sütun eşleme — SAF yardımcılar (2026-10-05, 0121).
//
// `ekstre-esle` ağ ve veritabanı işini yapar; buradaki her şey girdi alıp
// çıktı döner ki `supabase/tests/ekstre_esleme_test.ts` Anthropic'e ve
// Postgres'e dokunmadan sınayabilsin.
//
// ── Neden ──────────────────────────────────────────────────────────────────
// yasin (2026-10-05): "hangi banka olduğu önemli değil, tüm banka ve aracı
// kurumları kapsamalıyız"; karar kartında "AI sütun eşleme" seçildi.
// Cihazdaki motor kurum başına kod içermez ama görmediği bir düzende sembol
// sütununu tanıyamayabilir. O zaman uygulama tablonun ANONİM iskeletini
// (`lib/services/ekstre/ekstre_iskeleti.dart`) buraya yollar; model yalnız
// "hangi sütun ne" sorusunu yanıtlar.
//
// ── Kişisel veri gitmez ────────────────────────────────────────────────────
// İskelette ad, numara ve tutar maskelidir (harf A/a, rakam 9). Sunucu buna
// GÜVENMEZ: tablo hücrelerinde 9'dan başka rakam varsa istek reddedilir
// (`iskeletiDogrula`) — istemcideki bir hata ham ekstreyi modele
// taşıyamaz. İskelet ve yanıt saklanmaz; yalnız sayaç ve maliyet yazılır.
//
// ── Model sayı üretmez ─────────────────────────────────────────────────────
// Yanıt yalnız sütun numaralarıdır; değerler cihazda belgeden okunur.
// Numaralar iskeletteki tablo boyutlarına karşı denetlenir
// (`yanitiDogrula`): olmayan tablo/sütun, aynı sütuna iki rol, sembol ya da
// adet olmayan tablo düşer.

export const ROLLER = [
  'sembol', 'isim', 'adet', 'fiyat', 'tutar', 'tarih', 'yon', 'tur', 'para_birimi',
] as const;
export type Rol = typeof ROLLER[number];

export type TabloBoyutu = { satir: number; sutun: number };

export type Esleme = {
  /// İskeletteki tablo numarası (1'den).
  tablo: number;
  /// Başlık satırının iskeletteki satır numarası; başlıksızsa -1.
  baslik_satiri: number;
  roller: Partial<Record<Rol, number>>;
};

export const AZAMI_UZUNLUK = 40_000;
export const ILK_SATIR = 'sandık ekstre iskeleti v1';

/// İskeletin biçimi ve maskesi. Hata nedeni ya da tablo boyutları.
export function iskeletiDogrula(
  iskelet: unknown,
): { gecti: true; tablolar: TabloBoyutu[] } | { gecti: false; neden: string } {
  if (typeof iskelet !== 'string' || iskelet.length === 0) return { gecti: false, neden: 'bos' };
  if (iskelet.length > AZAMI_UZUNLUK) return { gecti: false, neden: 'uzun' };
  const satirlar = iskelet.split('\n');
  if (satirlar[0] !== ILK_SATIR) return { gecti: false, neden: 'surum' };
  const tablolar: TabloBoyutu[] = [];
  for (const s of satirlar) {
    const baslik = s.match(/^## tablo (\d+) \(.*\) · (\d+) satır × (\d+) sütun$/);
    if (baslik) {
      if (Number(baslik[1]) !== tablolar.length + 1) return { gecti: false, neden: 'sira' };
      tablolar.push({ satir: Number(baslik[2]), sutun: Number(baslik[3]) });
      continue;
    }
    const veri = s.match(/^(\d+)\t(.*)$/);
    if (!veri) continue;
    if (tablolar.length === 0) return { gecti: false, neden: 'tablosuz_satir' };
    // Maske denetimi: hücrelerde yalnız 9 rakamı olabilir.
    if (/[0-8]/.test(veri[2])) return { gecti: false, neden: 'maskesiz' };
  }
  if (tablolar.length === 0) return { gecti: false, neden: 'tablo_yok' };
  return { gecti: true, tablolar };
}

export const SISTEM_TALIMATI = `Bir portföy uygulamasının ekstre okuyucusuna yardım ediyorsun. Kullanıcı bir banka ya da aracı kurumdan aldığı ekstreyi (PDF, Excel, CSV) yükledi; cihazdaki okuyucu tabloları çıkardı ama hangi sütunun ne olduğundan emin olamadı.

Sana tabloların ANONİM iskeleti veriliyor: her tablo "## tablo N" başlığıyla başlar, her satır "satır_no<TAB>hücre<TAB>hücre…" biçimindedir. Hücrelerde kişisel bilgi maskelidir: harfler A/a, rakamlar 9 olur; noktalama ve uzunluk korunur ("9.999,99" bir tutar, "99/99/9999" bir tarih, "AAA" üç harfli bir kod). Sütun adları ve genel finans kelimeleri ("Pay Adedi", "Birim Fiyat", "PORTFÖY", "FONU") maskesizdir. Hücre numaraları 0'dan başlar (satır numarasından sonraki ilk hücre 0).

Görevin: YATIRIM VARLIKLARINI (hisse, fon, döviz, altın, kripto, tahvil) ya da bu varlıkların ALIM-SATIM İŞLEMLERİNİ listeleyen tabloları bulmak ve sütunlarını eşlemek. Vadesiz/vadeli hesap bakiyeleri, kart harcamaları, havale/EFT hareketleri, özet ve döviz kuru tabloları varlık tablosu DEĞİLDİR, onları atla.

Roller:
- sembol: varlığın kodu (THYAO, TTE, USD) ya da kod yoksa varlığın adı (fon unvanı)
- isim: kodun yanında ayrıca ad sütunu varsa ad
- adet: miktar, pay adedi, lot, nominal
- fiyat: alış/maliyet fiyatı ya da işlem fiyatı (güncel fiyat DEĞİL; yalnız güncel fiyat varsa ve maliyet yoksa onu ver)
- tutar: alış/maliyet tutarı ya da işlem tutarı (güncel piyasa değeri DEĞİL; yalnız piyasa değeri varsa onu ver)
- tarih: işlem tarihi
- yon: alış/satış yönü
- tur: varlık türü (hisse, fon…)
- para_birimi: para birimi

Kurallar: Yalnız gerçekten var olan sütunları ver; emin olmadığın rolü HİÇ verme. Her sütun en çok bir role gider. sembol ve adet bulunamayan tabloyu hiç listeleme. Başlık satırı yoksa baslik_satiri = -1. Yanıtı yalnız sutun_eslemesi aracıyla ver.`;

export const ARAC = {
  name: 'sutun_eslemesi',
  description: 'Varlık ya da işlem tablolarının sütun eşlemesi.',
  input_schema: {
    type: 'object',
    properties: {
      tablolar: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            tablo: { type: 'integer', description: '"## tablo N" numarası' },
            baslik_satiri: { type: 'integer', description: 'Başlık satırının satır numarası, yoksa -1' },
            roller: {
              type: 'object',
              properties: Object.fromEntries(ROLLER.map((r) => [r, { type: 'integer' }])),
              additionalProperties: false,
            },
          },
          required: ['tablo', 'baslik_satiri', 'roller'],
        },
      },
    },
    required: ['tablolar'],
  },
} as const;

export function istekGovdesi(iskelet: string, model: string): Record<string, unknown> {
  return {
    model,
    max_tokens: 1024,
    system: SISTEM_TALIMATI,
    tools: [ARAC],
    tool_choice: { type: 'tool', name: ARAC.name },
    messages: [{ role: 'user', content: iskelet }],
  };
}

/// Model yanıtından ARAÇ girdisini alır ve iskeletin boyutlarına karşı
/// denetler. Geçersiz tablo/rol sessizce düşer; hiç geçerli tablo yoksa [].
export function yanitiDogrula(arac: unknown, tablolar: TabloBoyutu[]): Esleme[] {
  const liste = (arac as { tablolar?: unknown })?.tablolar;
  if (!Array.isArray(liste)) return [];
  const out: Esleme[] = [];
  const gorulen = new Set<number>();
  for (const x of liste) {
    const tablo = (x as { tablo?: unknown })?.tablo;
    if (!Number.isInteger(tablo) || (tablo as number) < 1 || (tablo as number) > tablolar.length) continue;
    if (gorulen.has(tablo as number)) continue;
    const boyut = tablolar[(tablo as number) - 1];
    const bs = (x as { baslik_satiri?: unknown }).baslik_satiri;
    const baslik = Number.isInteger(bs) && (bs as number) >= -1 && (bs as number) < boyut.satir
      ? bs as number
      : -1;
    const ham = (x as { roller?: unknown }).roller;
    if (typeof ham !== 'object' || ham === null) continue;
    const roller: Partial<Record<Rol, number>> = {};
    const kullanilan = new Set<number>();
    for (const r of ROLLER) {
      const c = (ham as Record<string, unknown>)[r];
      if (!Number.isInteger(c) || (c as number) < 0 || (c as number) >= boyut.sutun) continue;
      if (kullanilan.has(c as number)) continue;
      roller[r] = c as number;
      kullanilan.add(c as number);
    }
    if (roller.sembol === undefined || roller.adet === undefined) continue;
    gorulen.add(tablo as number);
    out.push({ tablo: tablo as number, baslik_satiri: baslik, roller });
  }
  return out;
}
