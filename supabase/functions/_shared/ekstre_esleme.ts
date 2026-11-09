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

/// Metin yolu (2026-10-13, yasin: "eklenen pdf in içeriğini metin olarak
/// apide ayıklatabilir miyiz", Qwen karşılaştırmasından sonra "bahsettiğimiz
/// şekilde geliştirmeyi yap"). v1 iskelette HARFLER de maskeliydi; model
/// "Pay Adedi" gibi sözlükteki başlıkları görüyor ama "Nominal Miktar",
/// "Kıymet" gibi sözlük dışı başlıkları ve varlık adlarını göremiyordu —
/// yasin'in DenizBank ekstresinde yanıt "0 tablo" (Tokyo kaydı 2026-10-13
/// 09:05). v2'de harfler AÇIK, rakamlar yine 9: tutar, adet, IBAN, TCKN,
/// hesap no cihazda kalır; ad/adres etiketli künye satırlarında cihazda
/// maskelenir (`ekstreMetni`). Aynı maske denetimi v2'ye de uygulanır.
export const METIN_ILK_SATIR = 'sandık ekstre metni v2';

export type Surum = 'iskelet' | 'metin';

/// İskeletin biçimi ve maskesi. Hata nedeni ya da tablo boyutları.
export function iskeletiDogrula(
  iskelet: unknown,
): { gecti: true; tablolar: TabloBoyutu[]; surum: Surum } | { gecti: false; neden: string } {
  if (typeof iskelet !== 'string' || iskelet.length === 0) return { gecti: false, neden: 'bos' };
  if (iskelet.length > AZAMI_UZUNLUK) return { gecti: false, neden: 'uzun' };
  const satirlar = iskelet.split('\n');
  const surum: Surum | null = satirlar[0] === ILK_SATIR
    ? 'iskelet'
    : satirlar[0] === METIN_ILK_SATIR
    ? 'metin'
    : null;
  if (surum === null) return { gecti: false, neden: 'surum' };
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
  return { gecti: true, tablolar, surum };
}

export const SISTEM_TALIMATI = `Bir portföy uygulamasının ekstre okuyucusuna yardım ediyorsun. Kullanıcı bir banka ya da aracı kurumdan aldığı ekstreyi (PDF, Excel, CSV) yükledi; cihazdaki okuyucu tabloları çıkardı ama hangi sütunun ne olduğundan emin olamadı.

Sana tabloların iskeleti veriliyor: her tablo "## tablo N" başlığıyla başlar, her satır "satır_no<TAB>hücre<TAB>hücre…" biçimindedir. Rakamlar maskelidir (9 olur); noktalama ve uzunluk korunur ("9.999,99" bir tutar, "99/99/9999" bir tarih). İlk satır "sandık ekstre iskeleti v1" ise kişisel bilgi taşıyabilecek kelimeler de maskelidir (harfler A/a; "AAA" üç harfli bir kod), yalnız sütun adları ve genel finans kelimeleri ("Pay Adedi", "Birim Fiyat", "PORTFÖY", "FONU") açıktır. "sandık ekstre metni v2" ise kelimeler açıktır; yalnız ad ve adres gibi kişisel alanlar A/a ile maskelidir. Hücre numaraları 0'dan başlar (satır numarasından sonraki ilk hücre 0).

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

/// İlk deneme: ucuz model (Haiku 5.5, yasin 2026-10-13: "Claude Haiku'da
/// kal, gerekirse Sonnet"). Yalnız metin yolunda; v1 iskelet eskisi gibi
/// doğrudan Sonnet. Haiku hiç tablo bulamazsa aynı istek bir kez Sonnet'e
/// gider (`ekstre-esle`).
export const ILK_MODEL = 'claude-haiku-5-5';
export const YEDEK_MODEL = 'claude-sonnet-5-5';

export function istekGovdesi(iskelet: string, model: string): Record<string, unknown> {
  return {
    model,
    // Sonnet 5.5 zorunlu araç seçimini (tool_choice any/tool) 400
    // invalid_request_error ile reddeder (canlı log, 2026-10-10). `auto` +
    // sistem talimatındaki "yalnız sutun_eslemesi aracıyla ver" yeterli;
    // araç bloğu gelmezse yanitiDogrula boş döner, istemci "eşleşme yok" der.
    // Uyarlanabilir düşünme varsayılan açık olduğundan bütçe 1024'ten geniş.
    max_tokens: 4096,
    output_config: { effort: 'low' },
    system: SISTEM_TALIMATI,
    tools: [ARAC],
    tool_choice: { type: 'auto', disable_parallel_tool_use: true },
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

// Log satırı için hata özeti (2026-10-08). İlk sürüm yalnız `e.name`
// yazıyordu; Anthropic SDK hataları `name` ezmediği için log "ekstre-esle
// Error" diyordu ve bakiye bitmesi, geçersiz anahtar, model adı birbirinden
// ayrılamadı (yasin'in iki 500'ü). Durum kodu + API hata türü yeter; ham
// mesaj loga da yazılmaz (istek kimliği/hesap ayrıntısı taşıyabilir), yanıta
// zaten hiç girmez.
export function hataOzeti(e: unknown): string {
  if (e && typeof e === 'object') {
    const o = e as Record<string, unknown>;
    if (typeof o.status === 'number') {
      const govde = o.error as Record<string, unknown> | undefined;
      const ic = govde?.error as Record<string, unknown> | undefined;
      const tur = ic?.type ?? govde?.type ?? o.type;
      return `api ${o.status}${typeof tur === 'string' ? ' ' + tur : ''}`;
    }
    // PostgrestError düz nesne (Error değil): yalnız kodu.
    if (typeof o.code === 'string') return `db ${o.code}`;
    if (e instanceof Error) return e.name;
  }
  return 'hata';
}

// ── Banka şablonu hafızası (2026-10-13, 0147) ──────────────────────────────
// yasin: "direkt okutmak pahalı gözüküyor … banka şablonları da
// değişebilir". Model bir tabloyu eşlediğinde başlık satırının izi
// (`baslikIzi`) ve sütun rolleri saklanır; aynı başlıklı tablo bir daha
// geldiğinde model ÇAĞRILMAZ. Maliyet dosya başına değil düzen başına olur.
//
// Değişen tasarım: iz başlık satırının TAMAMIDIR (sütun sırası ve adları);
// banka bir sütun ekler/yeniden adlandırırsa iz tutmaz, şablon hiç denenmez,
// model bir kez çağrılır ve yeni düzen ayrı satır olarak eklenir — eskisi
// silinmez, iki düzen birlikte çalışır. İz tutup değerler tutmazsa cihaz
// (`aiEslemesiyle` sağlaması) şablonu reddeder ve `sablonsuz` ile yeniden
// sorar; burası şablonun hata sayacını artırır, modelin yeni eşlemesi aynı
// izin üstüne yazılır.
//
// Kişisel veri: tabloda iz METİN olarak değil SHA-256 özeti olarak durur —
// model başlık satırını yanlış seçip künyeyi başlık sanırsa bile ad
// saklanmaz.

/// Tek başlığa bakılacak en çok satır (başlık genelde ilk birkaç satırda).
export const SABLON_TARANAN_SATIR = 15;
/// Şablon bu kadar hata alınca kullanılmaz (yeni eşleme sayacı sıfırlar).
export const SABLON_HATA_SINIRI = 3;

export type Sablon = { roller: Partial<Record<Rol, number>>; sutun_sayisi: number };

/// Metindeki tablolar: tablo → satır → hücre (satır no'su atılmış).
export function tablolariAyikla(metin: string): string[][][] {
  const out: string[][][] = [];
  for (const s of metin.split('\n')) {
    if (/^## tablo \d+ /.test(s)) {
      out.push([]);
      continue;
    }
    const veri = s.match(/^(\d+)\t(.*)$/);
    if (!veri || out.length === 0) continue;
    out[out.length - 1].push(veri[2].split('\t'));
  }
  return out;
}

function katla(h: string): string {
  return h
    .replaceAll('İ', 'i').replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i').replaceAll('ş', 's').replaceAll('ğ', 'g')
    .replaceAll('ü', 'u').replaceAll('ö', 'o').replaceAll('ç', 'c')
    .replaceAll('â', 'a').replaceAll('î', 'i').replaceAll('û', 'u')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/[0-9]/g, '#')
    .replace(/\s+/g, ' ')
    .trim();
}

/// Başlık satırının izi; başlığa benzemeyen satır (iki harfli hücreden
/// azı) için `null`.
export function baslikIzi(hucreler: string[]): string | null {
  const k = hucreler.map(katla);
  if (k.filter((h) => /[a-z]/.test(h)).length < 2) return null;
  const iz = k.join('|');
  return iz.length > 400 ? null : iz;
}

export async function izOzeti(iz: string): Promise<string> {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(iz));
  return Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, '0')).join('');
}

function sutunSayisi(t: string[][]): number {
  return t.reduce((m, s) => Math.max(m, s.length), 0);
}

/// Her tablonun ilk [SABLON_TARANAN_SATIR] satırının izleri.
export function adayIzler(tablolar: string[][][]): { tablo: number; satir: number; iz: string }[] {
  const out: { tablo: number; satir: number; iz: string }[] = [];
  for (const [i, t] of tablolar.entries()) {
    for (const [j, s] of t.slice(0, SABLON_TARANAN_SATIR).entries()) {
      const iz = baslikIzi(s);
      if (iz) out.push({ tablo: i + 1, satir: j, iz });
    }
  }
  return out;
}

/// Saklı şablonlarla eşleme: tablo başına ilk tutan satır. Sütun sayısı
/// şablonunkinden farklıysa (aynı başlık, farklı bölünme) kullanılmaz.
export function sablonlaEsle(
  tablolar: string[][][],
  adaylar: { tablo: number; satir: number; iz: string }[],
  sablonlar: Map<string, Sablon>,
): { eslemeler: Esleme[]; kullanilan: string[] } {
  const eslemeler: Esleme[] = [];
  const kullanilan: string[] = [];
  for (const a of adaylar) {
    if (eslemeler.some((e) => e.tablo === a.tablo)) continue;
    const s = sablonlar.get(a.iz);
    if (!s || s.sutun_sayisi !== sutunSayisi(tablolar[a.tablo - 1])) continue;
    eslemeler.push({ tablo: a.tablo, baslik_satiri: a.satir, roller: s.roller });
    kullanilan.push(a.iz);
  }
  return { eslemeler, kullanilan };
}

/// Modelin eşlemesinden saklanacak şablonlar (başlıksız tablo şablon olmaz).
export function yeniSablonlar(
  tablolar: string[][][],
  eslemeler: Esleme[],
): { iz: string; sablon: Sablon }[] {
  const out: { iz: string; sablon: Sablon }[] = [];
  for (const e of eslemeler) {
    const t = tablolar[e.tablo - 1];
    if (!t || e.baslik_satiri < 0 || e.baslik_satiri >= t.length) continue;
    const iz = baslikIzi(t[e.baslik_satiri]);
    if (!iz || out.some((x) => x.iz === iz)) continue;
    out.push({ iz, sablon: { roller: e.roller, sutun_sayisi: sutunSayisi(t) } });
  }
  return out;
}

/// DB'den gelen `roller` jsonb'si güvenilmez sayılır: yalnız bilinen rol ve
/// sütun sınırı içindeki numaralar kalır.
export function sablonRolleri(ham: unknown, sutun: number): Partial<Record<Rol, number>> | null {
  if (typeof ham !== 'object' || ham === null) return null;
  const r: Partial<Record<Rol, number>> = {};
  for (const k of ROLLER) {
    const c = (ham as Record<string, unknown>)[k];
    if (Number.isInteger(c) && (c as number) >= 0 && (c as number) < sutun) r[k] = c as number;
  }
  return r.sembol === undefined || r.adet === undefined ? null : r;
}
