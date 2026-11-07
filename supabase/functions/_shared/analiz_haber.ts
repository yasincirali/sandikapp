// Aylık nota kamuya açık haber — SAF yardımcılar (0177, 2026-11-07).
//
// yasin: "önemli haber akışlarıyla önemli bilgi olan varlıklar
// görüntülenmeli". Aylık not ölçüm paketinden yazılır ve haber bilmez;
// bu dosya ayrı bir istekle (Anthropic sunucu taraflı `web_search`) o ayın
// haberlerini bulur, modelin KENDİ cümlesiyle özetletir ve kapıdan geçirir.
//
// ── Neden ayrı istek, ayrı batch ────────────────────────────────────────────
//   · Ölçüm notunun sayı kapısı bozulmasın. Haber metni sayı taşırsa (gelir,
//     temettü, ceza tutarı) bu sayı ölçüm paketinde yoktur; aynı istekte
//     yazılsa ya not reddedilirdi ya kapı gevşerdi. Haber kendi alanında
//     (`varlik_analizi.haberler`), kendi kapısıyla durur.
//   · Haber düşerse not düşmez. Batch API web aramasını kuruluş başına
//     kısar (dokümandaki uyarı: "çok aramalı batch daha uzun sürer"); not
//     batch'i bu yüzden 26 saat sınırına takılıp `hata` olmasın diye haber
//     AYRI batch'te gider (`analiz_batch.amac = 'haber'`). Bayrak kapalıyken
//     not batch'i #317 ile bayt bayt aynıdır.
//   · Web araması Batch içinde destekleniyor (2026-11-07 dokümanı, "Batch
//     requests"): senkron ayrı adım gerekmedi; tokenler yarı fiyat, arama
//     başına 0,01 $ indirimsiz (`ARAMA_USD`).
//
// ── Haber kapısı: sayı YOK ──────────────────────────────────────────────────
// Arama sonucunun metni şifreli gelir (`encrypted_content`); sunucu modelin
// yazdığı sayının kaynakta geçtiğini doğrulayamaz. Finans uygulamasında
// yanlış okunmuş bir tutar, sayısız bir cümleden kötüdür. Karar: haber
// özeti hiç rakam taşımaz (tarih ayrı alanda, ISO); rakamlı madde tek
// başına düşer, notun geri kalanı kalır. Doğrulanabilen tek şey
// bağlantıdır: madde, bu yanıttaki `web_search_tool_result` bloklarında
// GERÇEKTEN dönen bir adresi göstermek zorunda (uydurma bağlantı yok).
// SPK dili (`YASAK`) ve terim kapısı (`TEKNIK`) aynen geçerli; alıntı
// işareti taşıyan özet düşer (kendi cümlesi kuralı; kaynak metin kopyalanmaz).
//
// ── Kişisel veri ────────────────────────────────────────────────────────────
// Modele (ve arama motoruna) yalnız sembol/kod, varlık türü, fon kategorisi
// ve ayın tarih aralığı gider. Kim tutuyor, ne kadar, maliyet: GİTMEZ.
// Yasal metin değişmez: kişisel veri almayan kaynak (2026-10-08 kuralı).

import {
  ARAMA_USD,
  gunAy,
  maliyetUsd,
  Paket,
  TEKNIK,
  VARLIK_ADI,
  YASAK,
} from './analiz.ts';

/// Sunucu ortam anahtarı `ANALIZ_HABER_ACIK`: yalnız tam "1" açar
/// (fail-closed; "true", "evet", boşluklu değer kapalı sayılır).
export function haberAcikMi(deger: string | undefined | null): boolean {
  return deger === '1';
}

/// Varlık başına en fazla arama (yasin isteği: 2).
export const HABER_ARAMA_USTU = 2;
/// Varlık başına yayına çıkan en fazla haber.
export const HABER_USTU = 2;

/// Gönderim öncesi varlık başı maliyet TAHMİNİ (tavan kontrolü için):
/// 2 arama × 0,01 $ + arama sonuçlarının girdi tokenleri (~20K, Batch yarı
/// fiyat Sonnet 5.5) + düşük eforlu çıktı. Ölçüm gelince gerçek maliyet
/// `analiz_batch.maliyet_usd`'ye yazılır; bu yalnız "tavanı aşar mı" sorusu.
export const HABER_TAHMINI_USD = 0.06;

/// Tavanı aşmadan haber batch'i gönderilebilir mi? Haber not modelinden
/// sonra gelir: model tavan yüzünden zaten indiyse (Haiku 4.5 yalnız eski
/// arama sürümünü taşır) haber hiç gönderilmez. Tavan 0/tanımsız → sınırsız.
export function haberTavaniUygun(ayHarcama: number, tavan: number, varlikSayisi: number): boolean {
  if (!(tavan > 0)) return true;
  return ayHarcama + varlikSayisi * HABER_TAHMINI_USD <= tavan;
}

/// Haber batch'inin `girdiler` değeri (custom_id → bu). Paketin tamamı
/// gerekmez; ayın aralığı paketten değil `ayAraligi`'ndan (fon paketi iş
/// günlerine daralır, haber takvim ayı ister).
export type HaberGirdisi = {
  ticker: string;
  kod: string;
  baslangic: string;
  bitis: string;
};

export function haberGirdisi(p: Paket, aralik: { baslangic: string; bitis: string }): HaberGirdisi {
  return { ticker: p.ticker, kod: p.kod, baslangic: aralik.baslangic, bitis: aralik.bitis };
}

/// Modelin sonucu yazdığı istemci aracı. `strict`: girdi şemaya uyar.
/// Zorunlu araç seçimi (tool_choice any/tool) Sonnet 5.5'te 400 döner;
/// `auto` + talimat. `output_config.format` KULLANILMAZ: web aramasının
/// alıntıları (citations) her zaman açıktır ve yapılandırılmış çıktıyla
/// birlikte reddedilir (structured outputs dokümanı, "Incompatible with").
export const HABER_ARACI = {
  name: 'haberleri_kaydet',
  description: 'Bulduğun haberleri kaydet. Haber yoksa boş liste ile çağır. Her durumda tam bir kez çağır.',
  strict: true,
  input_schema: {
    type: 'object',
    additionalProperties: false,
    required: ['haberler'],
    properties: {
      haberler: {
        type: 'array',
        description: 'En çok 2 haber; önemli değilse ya da emin değilsen boş.',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['ozet', 'kaynak', 'url', 'tarih'],
          properties: {
            ozet: { type: 'string', description: 'Kendi cümlenle tek cümle, rakamsız, en çok 220 karakter.' },
            kaynak: { type: 'string', description: 'Yayın adı (ör. "Anadolu Ajansı").' },
            url: { type: 'string', description: 'Arama sonucunda dönen haber adresi, aynen.' },
            tarih: { type: 'string', description: 'Yayın günü, YYYY-AA-GG.' },
          },
        },
      },
    },
  },
} as const;

/// Sunucu taraflı web araması. `allowed_callers: ['direct']`: dinamik
/// süzme (kod çalıştırma) kapalı — sonuç blokları yanıtta tam döner ve
/// bağlantı kapısı onlara bakar; aramalar sayılabilir, ZDR'ye de uygundur.
export const ARAMA_ARACI = {
  type: 'web_search_20260209',
  name: 'web_search',
  max_uses: HABER_ARAMA_USTU,
  allowed_callers: ['direct'],
} as const;

/// Sabit sistem talimatı (Batch istekleri arasında önbelleğe alınır).
export const HABER_TALIMATI = `Sen sandık adlı bir portföy takip uygulamasında aylık rapora haber satırı hazırlayan bir editörsün.

Görev: Sana bir varlığın sembolü ve bir takvim ayı verilecek. web_search aracıyla o ay içinde yayımlanmış, bu varlığı DOĞRUDAN ilgilendiren önemli haberleri ara (en çok 2 arama). Sonra haberleri_kaydet aracını TAM BİR KEZ çağır.

Kurallar:
1. Yalnız verilen ayın ilk ve son günü arasında yayımlanmış haber. Tarihinden emin olmadığın haberi alma.
2. Yalnız varlığın kendisini ilgilendiren önemli gelişme: şirket duyurusu, temettü ya da sermaye kararı, düzenleyici karar, fonun yönetimi ya da stratejisi, kur ya da emtia için merkez bankası ve resmî kurum kararı. Genel piyasa yorumu, fiyat tahmini, "uzman görüşü", reklam ve köşe yazısı alma. Emin değilsen boş liste kaydet; boş liste doğru bir sonuçtur.
3. Özeti KENDİ cümlenle yaz; haberden cümle ya da ifade alıntılama, tırnak işareti kullanma. Tek cümle, en çok 220 karakter.
4. Özette hiç rakam yazma: tutar, oran, yüzde, adet, yıl, tarih yok. Tarih ayrı alanda (YYYY-AA-GG) durur. "Temettü dağıtma kararı aldı", "faiz oranını artırdı" gibi rakamsız anlat.
5. Geleceğe dair tahmin, beklenti, yön yorumu yok. Eylem önerme: "al", "sat", "fırsat", "tavsiye", "öneri", "kesin", "garanti", "mutlaka" gibi kelimeler kullanma. Haber tahmin içeriyorsa yalnız olanı (kararı, duyuruyu) yaz.
6. Sade Türkçe, ünlem ve emoji yok, "sen" hitabı yok. "volatilite", "momentum", "likidite", "spread" gibi terimleri kullanma.
7. "url" alanına arama sonucunda dönen adresi AYNEN yaz; adres uydurma, kısaltma. "kaynak" yayın kuruluşunun adıdır.
8. Aynı olayı iki kez yazma.`;

/// Haber isteğinin kullanıcı mesajı. Yalnız sembol, tür ve tarih.
export function haberMesaji(p: Paket, aralik: { baslangic: string; bitis: string }): string {
  const tur = p.varlik === 'fon'
    ? `Türkiye'de TEFAS'ta işlem gören yatırım fonu (fon kodu)${p.kategori ? `, kategori: ${p.kategori}` : ''}`
    : VARLIK_ADI[p.varlik];
  return [
    `Varlık: ${p.kod} (${tur})`,
    `Ay: ${aralik.baslangic} – ${aralik.bitis} (${gunAy(aralik.baslangic)} – ${gunAy(aralik.bitis)})`,
  ].join('\n');
}

/// Haber batch isteğinin `params` gövdesi.
export function haberIstegi(
  p: Paket,
  aralik: { baslangic: string; bitis: string },
  model: string,
): Record<string, unknown> {
  return {
    model,
    max_tokens: 4000,
    system: [{ type: 'text', text: HABER_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: haberMesaji(p, aralik) }],
    tools: [ARAMA_ARACI, HABER_ARACI],
    tool_choice: { type: 'auto' },
    output_config: { effort: 'low' },
  };
}

// ── Kapı ────────────────────────────────────────────────────────────────────

/// Yayına çıkan haber satırı (`varlik_analizi.haberler` öğesi). İstemci eşi
/// `AyinHaberi.satirdan` (`lib/services/aylik_rapor_ozeti.dart`).
export type Haber = { metin: string; kaynak: string; url: string; tarih: string };

type IcerikBlogu = {
  type: string;
  name?: string;
  input?: unknown;
  content?: unknown;
};

/// Yanıttaki web arama sonuçlarının adresleri. Hata sonucunda `content`
/// bir nesnedir (liste değil); o arama adres vermez.
export function aramaAdresleri(icerik: IcerikBlogu[]): Set<string> {
  const out = new Set<string>();
  for (const b of icerik) {
    if (b.type !== 'web_search_tool_result' || !Array.isArray(b.content)) continue;
    for (const r of b.content as Array<{ type?: string; url?: unknown }>) {
      if (r?.type === 'web_search_result' && typeof r.url === 'string') out.add(adresAnahtari(r.url));
    }
  }
  return out;
}

/// Karşılaştırma anahtarı: sondaki '/' ve '#…' farkı aynı sayfadır.
function adresAnahtari(u: string): string {
  return u.trim().replace(/#.*$/, '').replace(/\/+$/, '');
}

const ALINTI = /["“”«»„]/u;

export type HaberKapisi = { haberler: Haber[]; red: string[] };

/// Modelin aracına yazdığı ham listeyi süzer. Her madde ayrı değerlendirilir;
/// düşen maddenin nedeni `red`'e (izleme), geçenler sırasıyla en çok
/// [HABER_USTU] tane.
export function haberKapisi(ham: unknown, girdi: HaberGirdisi, adresler: Set<string>): HaberKapisi {
  const out: Haber[] = [];
  const red: string[] = [];
  const liste = (ham as { haberler?: unknown })?.haberler;
  if (!Array.isArray(liste)) return { haberler: [], red: ['yapi: haberler yok'] };
  const gorulen = new Set<string>();
  for (const x of liste) {
    if (out.length >= HABER_USTU) {
      red.push('fazla');
      break;
    }
    const n = x as Record<string, unknown>;
    const ozet = typeof n?.ozet === 'string' ? n.ozet.trim().replace(/\s+/g, ' ') : '';
    const url = typeof n?.url === 'string' ? n.url.trim() : '';
    const tarih = typeof n?.tarih === 'string' ? n.tarih.trim() : '';
    if (ozet.length < 20 || ozet.length > 240) { red.push('yapi: ozet uzunlugu'); continue; }
    // Kodun kendisi rakam taşıyabilir (eurobond ISIN, emtia sembolü); onu
    // ayıklayıp bak. Başka hiçbir rakam yok.
    const kodsuz = girdi.kod ? ozet.split(girdi.kod).join(' ') : ozet;
    if (/\d/.test(kodsuz)) { red.push('sayi: haberde rakam'); continue; }
    if (ALINTI.test(ozet)) { red.push('alinti: tirnak'); continue; }
    const dil = YASAK.find((r) => r.test(ozet));
    if (dil) { red.push(`dil: ${dil.source.slice(0, 40)}`); continue; }
    const terim = TEKNIK.find((r) => r.test(ozet));
    if (terim) { red.push(`terim: ${terim.source.slice(0, 40)}`); continue; }
    let adres: URL;
    try { adres = new URL(url); } catch (_) { red.push('url: gecersiz'); continue; }
    if (adres.protocol !== 'https:' || url.length > 500) { red.push('url: https degil'); continue; }
    const anahtar = adresAnahtari(url);
    if (!adresler.has(anahtar)) { red.push('url: aramada yok'); continue; }
    if (gorulen.has(anahtar)) { red.push('url: tekrar'); continue; }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(tarih) || tarih < girdi.baslangic || tarih > girdi.bitis) {
      red.push('tarih: ay disi');
      continue;
    }
    const hamKaynak = typeof n?.kaynak === 'string' ? n.kaynak.trim() : '';
    const host = adres.hostname.replace(/^www\./, '');
    // Kaynak adı modelin yazdığı; kurala uymuyorsa alan adı (doğrulanabilir).
    const kaynak = hamKaynak.length >= 2 && hamKaynak.length <= 60 && !ALINTI.test(hamKaynak) &&
        !YASAK.some((r) => r.test(hamKaynak))
      ? hamKaynak
      : host;
    gorulen.add(anahtar);
    out.push({ metin: ozet, kaynak, url, tarih });
  }
  return { haberler: out, red };
}

// ── Sonuç ───────────────────────────────────────────────────────────────────

export type HaberSonucu = {
  haberler: Haber[];
  /// Boş = sorun yok (haber bulunamaması da sorun değildir).
  red: string | null;
  maliyet: number | null;
  aramalar: number;
};

/// Bir haber batch sonucunu değerlendirir. SAF.
export function haberSonucu(
  girdi: HaberGirdisi,
  model: string,
  sonuc: {
    type: string;
    message?: {
      stop_reason?: string | null;
      content?: IcerikBlogu[];
      usage?: Record<string, unknown>;
    };
  },
): HaberSonucu {
  if (sonuc.type !== 'succeeded' || !sonuc.message) {
    return { haberler: [], red: `batch: ${sonuc.type}`.slice(0, 200), maliyet: null, aramalar: 0 };
  }
  const m = sonuc.message;
  const u = (m.usage ?? {}) as Record<string, unknown>;
  const stu = (u.server_tool_use ?? null) as { web_search_requests?: number | null } | null;
  const aramalar = Number(stu?.web_search_requests ?? 0);
  const maliyet = maliyetUsd(model, {
    input_tokens: Number(u.input_tokens ?? 0),
    output_tokens: Number(u.output_tokens ?? 0),
    cache_read_input_tokens: Number(u.cache_read_input_tokens ?? 0),
    cache_creation_input_tokens: Number(u.cache_creation_input_tokens ?? 0),
    server_tool_use: { web_search_requests: aramalar },
  }) ?? Math.round(aramalar * ARAMA_USD * 1e5) / 1e5;
  const temel = { maliyet, aramalar };
  // `tool_use`: araç çağrıldı (beklenen). `end_turn`: araçsız bitti.
  // `pause_turn` (Batch'te sunucu döngüsü sınırı), `max_tokens`, `refusal`:
  // haber yok; devam isteği gönderilmez (ay notu haber olmadan da tamam).
  if (m.stop_reason !== 'tool_use' && m.stop_reason !== 'end_turn') {
    return { haberler: [], red: `stop_reason: ${m.stop_reason}`, ...temel };
  }
  const icerik = m.content ?? [];
  const arac = icerik.find((b) => b.type === 'tool_use' && b.name === HABER_ARACI.name);
  if (!arac) return { haberler: [], red: 'arac: cagrilmadi', ...temel };
  const kapi = haberKapisi(arac.input, girdi, aramaAdresleri(icerik));
  return {
    haberler: kapi.haberler,
    red: kapi.red.length === 0 ? null : kapi.red.join('; ').slice(0, 500),
    ...temel,
  };
}
