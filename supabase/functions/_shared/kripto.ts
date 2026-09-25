// Kripto piyasa verisi — saf yardımcılar + sağlayıcı çağrıları.
//
// ── Neden sunucuda (kullanıcı kararı, 2026-09-25) ───────────────────────────
// "Public bir performans sorunu yaratmayacak bir API üzerinden güvenli ve
// hızlı şekilde datayı çekmeliyiz." Diğer varlıklarda her telefon Yahoo/
// truncgil'e kendisi gidiyor; kriptoda bunu tekrarlamıyoruz:
//   · CoinGecko ücretsiz planı ayda 10.000 çağrı. 1.000 kullanıcının 30 sn
//     ritmi ayda ~86 milyon istek eder; anahtarı uygulamaya gömmek de onu
//     herkese açmak demek.
//   · Binance IP başına dakikada 6.000 ağırlık tanır ve ABD IP'lerine 451
//     döner. Telefondan çağrı ülkeye göre kırılır; sunucudan çağrı bölgeye
//     sabitlenebilir (bkz. 0074, `x-region`).
// Sonuç: sağlayıcıya giden istek sayısı kullanıcı sayısından BAĞIMSIZ.
// Telefon yalnızca kendi Supabase'ini okur.
//
// ── Fiyat kaynağı sözleşmesi (lib/services/fiyat_kaynagi.dart) ─────────────
// Buradaki TL fiyatı üç kurala uyar:
//   1. Coin'in hangi pariteden fiyatlanacağına KATALOG karar verir
//      (`kripto_varlik.parite`), çağıran değil. TRY paritesi varsa o;
//      yoksa USDT paritesi × USDTTRY.
//   2. Çevrim AYNI borsanın USDTTRY'si ile yapılır, uygulamanın USDTRY=X'i
//      ile DEĞİL: fiyat ile grafik aynı ölçekte kalsın. (USDT/TRY, USD/TRY'nin
//      küçük bir primle üstündedir; iki kuru karıştırmak grafikte sahte
//      basamak üretir.)
//   3. Kur bilinmiyorsa nokta ÜRETİLMEZ. Sabit kur, "son bilinen" tahmin
//      yok — `null` döner, satır yazılmaz.

/// `assets.ticker` / `watchlist.ticker` / `price_alerts.symbol` biçimi.
/// `TEFAS:` öneki gibi: kaynağı sembolden okunur, Yahoo'ya DÜŞMEZ.
export const KRIPTO_ONEKI = 'KRIPTO:';

/// Coin kodu biçimi — Binance baseAsset'i (BTC, ETH, 1INCH, SHIB…).
const KOD_DESENI = /^[A-Z0-9]{2,15}$/;

export function kriptoMu(sembol: string): boolean {
  return sembol.trim().toUpperCase().startsWith(KRIPTO_ONEKI);
}

/// `KRIPTO:btc` → `BTC`. Biçim dışıysa `null` (sorguya girmez).
export function kriptoKodu(sembol: string): string | null {
  const s = sembol.trim().toUpperCase();
  if (!s.startsWith(KRIPTO_ONEKI)) return null;
  const kod = s.slice(KRIPTO_ONEKI.length);
  return KOD_DESENI.test(kod) ? kod : null;
}

export function kodGecerliMi(kod: string): boolean {
  return KOD_DESENI.test(kod);
}

/// Türkiye 2016'dan beri sabit UTC+3 (yaz saati yok). "Bugün" kripto için
/// 00:00 İstanbul'da başlar (kullanıcıya önerilen varsayılan, 2026-09-25):
/// uygulamanın diğer "bugün"leriyle aynı takvim günü.
export const TR_OFFSET_MS = 3 * 60 * 60 * 1000;

/// İstanbul takvim günü, `YYYY-MM-DD`.
export function istanbulGunu(t: Date): string {
  return new Date(t.getTime() + TR_OFFSET_MS).toISOString().slice(0, 10);
}

// ── Katalog ─────────────────────────────────────────────────────────────────

export type Parite = 'TRY' | 'USDT';

export interface KatalogSatiri {
  kod: string;
  ad: string;
  logo_url: string | null;
  coingecko_id: string | null;
  piyasa_sirasi: number | null;
  parite: Parite;
  binance_sembol: string;
}

export interface BinanceSembol {
  symbol: string;
  status?: string;
  baseAsset: string;
  quoteAsset: string;
}

export interface GeckoCoin {
  id: string;
  symbol: string;
  name: string;
  image?: string | null;
  market_cap_rank?: number | null;
}

/// Katalog evreni: Binance'te TRY paritesi olan HER coin + piyasa değerinde
/// ilk N içinde olup USDT paritesi olanlar (kullanıcıya önerilen varsayılan,
/// 2026-09-25: "TL paritesi olanlar + ilk 250").
///
/// Ad/logo CoinGecko'dan gelir; CoinGecko'da aynı sembolü taşıyan birden
/// çok coin var (ör. onlarca "ETH" klonu). Listeyi sıraya göre gezip İLK
/// eşleşmeyi almak en yüksek piyasa değerlisini seçer. CoinGecko hiç yanıt
/// vermediyse katalog yine kurulur: ad = kod, logo yok. Fiyat Binance'ten
/// geldiği için eksik ad fiyatı bozmaz.
export function katalogKur(
  binance: BinanceSembol[],
  gecko: GeckoCoin[],
): KatalogSatiri[] {
  const tryBaz = new Map<string, string>();
  const usdtBaz = new Map<string, string>();
  for (const s of binance) {
    if (s.status !== undefined && s.status !== 'TRADING') continue;
    const baz = String(s.baseAsset ?? '').toUpperCase();
    if (!kodGecerliMi(baz)) continue;
    if (s.quoteAsset === 'TRY') tryBaz.set(baz, s.symbol);
    else if (s.quoteAsset === 'USDT') usdtBaz.set(baz, s.symbol);
  }

  const geckoKod = new Map<string, GeckoCoin>();
  const sirali = [...gecko].sort(
    (a, b) => (a.market_cap_rank ?? 1e9) - (b.market_cap_rank ?? 1e9),
  );
  for (const c of sirali) {
    const k = String(c.symbol ?? '').toUpperCase();
    if (!geckoKod.has(k)) geckoKod.set(k, c);
  }

  const satirlar: KatalogSatiri[] = [];
  const ekle = (kod: string, parite: Parite, binanceSembol: string) => {
    const g = geckoKod.get(kod);
    satirlar.push({
      kod,
      ad: g?.name?.trim() || kod,
      logo_url: g?.image && g.image.startsWith('https://') ? g.image : null,
      coingecko_id: g?.id ?? null,
      piyasa_sirasi: g?.market_cap_rank ?? null,
      parite,
      binance_sembol: binanceSembol,
    });
  };

  for (const [kod, sembol] of tryBaz) ekle(kod, 'TRY', sembol);
  for (const kod of geckoKod.keys()) {
    if (tryBaz.has(kod)) continue;
    const sembol = usdtBaz.get(kod);
    if (sembol) ekle(kod, 'USDT', sembol);
  }
  // USDT'nin kendisi: TRY paritesi (USDTTRY) yukarıda zaten eklenir.
  return satirlar.sort(
    (a, b) => (a.piyasa_sirasi ?? 1e9) - (b.piyasa_sirasi ?? 1e9) || a.kod.localeCompare(b.kod),
  );
}

// ── Anlık fiyat ─────────────────────────────────────────────────────────────

/// Binance `/api/v3/ticker/tradingDay` satırı (yalnız kullandığımız alanlar).
/// `timeZone=3` ile `openPrice` İSTANBUL gününün açılışıdır — "bugün"
/// yüzdesi borsaların 24 saatlik kayan penceresine değil takvim gününe
/// bağlanır.
export interface GunSatiri {
  symbol: string;
  openPrice: string;
  lastPrice: string;
}

export interface FiyatSatiri {
  kod: string;
  fiyat_try: number;
  fiyat_usd: number | null;
  gun_acilis_try: number | null;
  gun: string;
  kaynak: 'binance_try' | 'binance_usdt' | 'btcturk_try';
  guncellendi: string;
}

function pozitif(v: unknown): number | null {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/// Katalog + tradingDay yanıtı → TL fiyat satırları.
///
/// USDT paritesinde açılış da AYNI anın kuruyla çevrilir (açılış × USDTTRY
/// açılışı). Açılışı bugünkü kurla çevirmek, kur hareketini coin hareketi
/// gibi gösterirdi.
export function fiyatlariHesapla(
  katalog: Pick<KatalogSatiri, 'kod' | 'parite' | 'binance_sembol'>[],
  gunSatirlari: GunSatiri[],
  simdi: Date,
): FiyatSatiri[] {
  const bySym = new Map(gunSatirlari.map((r) => [r.symbol, r]));
  const kur = bySym.get('USDTTRY');
  const kurSon = pozitif(kur?.lastPrice);
  const kurAcilis = pozitif(kur?.openPrice);
  const gun = istanbulGunu(simdi);
  const guncellendi = simdi.toISOString();

  const out: FiyatSatiri[] = [];
  for (const c of katalog) {
    const r = bySym.get(c.binance_sembol);
    const son = pozitif(r?.lastPrice);
    if (son === null) continue;
    const acilis = pozitif(r?.openPrice);
    if (c.parite === 'TRY') {
      out.push({
        kod: c.kod,
        fiyat_try: son,
        fiyat_usd: kurSon !== null ? son / kurSon : null,
        gun_acilis_try: acilis,
        gun,
        kaynak: 'binance_try',
        guncellendi,
      });
    } else {
      // Kur yoksa TL fiyatı YOK (sözleşme madde 3) — satır yazılmaz, eski
      // satır `guncellendi` ile bayat görünür.
      if (kurSon === null) continue;
      out.push({
        kod: c.kod,
        fiyat_try: son * kurSon,
        fiyat_usd: son,
        gun_acilis_try: acilis !== null && kurAcilis !== null ? acilis * kurAcilis : null,
        gun,
        kaynak: 'binance_usdt',
        guncellendi,
      });
    }
  }
  return out;
}

/// tradingDay'e sorulacak Binance sembolleri: katalogdakiler + USDTTRY.
/// Tekrarsız, 100'lük parçalar (uç noktanın üst sınırı).
export function gunSembolParcalari(
  katalog: Pick<KatalogSatiri, 'binance_sembol'>[],
  parca = 100,
): string[][] {
  const set = new Set<string>(['USDTTRY']);
  for (const c of katalog) set.add(c.binance_sembol);
  const hepsi = [...set];
  const out: string[][] = [];
  for (let i = 0; i < hepsi.length; i += parca) out.push(hepsi.slice(i, i + parca));
  return out;
}

/// BtcTurk yedeği: yalnızca TRY paritesi. Binance tümüyle yanıtsızken
/// devreye girer.
///
/// BtcTurk `open` alanının hangi pencereye ait olduğu belgelerde net değil;
/// bu yüzden açılış OKUNMAZ. Aynı İstanbul gününe ait önceki açılış varsa o
/// korunur, yoksa `null` (günlük yüzde gösterilmez) — uydurma açılış yok.
export interface BtcTurkTicker {
  pair?: string;
  numeratorSymbol?: string;
  denominatorSymbol?: string;
  last?: number | string;
}

export function btcturkFiyatlari(
  katalog: Pick<KatalogSatiri, 'kod'>[],
  ticker: BtcTurkTicker[],
  oncekiAcilis: Map<string, { gun: string; acilis: number | null }>,
  simdi: Date,
): FiyatSatiri[] {
  const gun = istanbulGunu(simdi);
  const tryFiyat = new Map<string, number>();
  for (const t of ticker) {
    if (String(t.denominatorSymbol ?? '').toUpperCase() !== 'TRY') continue;
    const p = pozitif(t.last);
    if (p !== null) tryFiyat.set(String(t.numeratorSymbol ?? '').toUpperCase(), p);
  }
  const kur = tryFiyat.get('USDT') ?? null;
  const out: FiyatSatiri[] = [];
  for (const c of katalog) {
    const p = tryFiyat.get(c.kod);
    if (p === undefined) continue;
    const onceki = oncekiAcilis.get(c.kod);
    out.push({
      kod: c.kod,
      fiyat_try: p,
      fiyat_usd: kur !== null ? p / kur : null,
      gun_acilis_try: onceki && onceki.gun === gun ? onceki.acilis : null,
      gun,
      kaynak: 'btcturk_try',
      guncellendi: simdi.toISOString(),
    });
  }
  return out;
}

// ── Seri (grafik) ───────────────────────────────────────────────────────────

/// İstemcinin gönderdiği aralık — `ResolutionTier.yahooInterval` ile aynı
/// adlar, böylece `HistoryService` çözünürlük katmanı kriptoda da aynı
/// kalır. Binance karşılığı sağda.
export const ARALIK: Record<string, { binance: string; ms: number }> = {
  '1m': { binance: '1m', ms: 60_000 },
  '5m': { binance: '5m', ms: 5 * 60_000 },
  '15m': { binance: '15m', ms: 15 * 60_000 },
  '1h': { binance: '1h', ms: 60 * 60_000 },
  '1d': { binance: '1d', ms: 24 * 60 * 60_000 },
  '1wk': { binance: '1w', ms: 7 * 24 * 60 * 60_000 },
};

const GUN = 24 * 60 * 60_000;

/// İstemcinin gönderdiği dönem — Yahoo `range` adları.
export const DONEM_MS: Record<string, number> = {
  '1d': GUN,
  '5d': 5 * GUN,
  '1mo': 31 * GUN,
  '3mo': 92 * GUN,
  '6mo': 183 * GUN,
  '1y': 366 * GUN,
  '2y': 731 * GUN,
  '5y': 1827 * GUN,
  // Binance spot 2017'de açıldı; "max" oradan başlar.
  'max': Number.POSITIVE_INFINITY,
};

export const BINANCE_ACILIS_MS = Date.UTC(2017, 6, 1);

/// Tek istekte en çok 1.000 mum; en çok 8 sayfa → bir seri en çok 8.000
/// nokta. Yahoo'nun "1m + 5d" penceresi 7.200 nokta — sığar.
export const SAYFA_MUM = 1000;
export const AZAMI_SAYFA = 8;

export interface SeriIstegi {
  kod: string;
  aralik: string;
  donem: string;
}

/// İstek doğrulaması — biçim dışı istek sağlayıcıya hiç gitmez.
export function seriIstegiCoz(body: unknown): SeriIstegi | null {
  if (typeof body !== 'object' || body === null) return null;
  const b = body as Record<string, unknown>;
  const kod = String(b.kod ?? '').trim().toUpperCase();
  const aralik = String(b.aralik ?? '');
  const donem = String(b.donem ?? '');
  if (!kodGecerliMi(kod)) return null;
  if (!(aralik in ARALIK)) return null;
  if (!(donem in DONEM_MS)) return null;
  return { kod, aralik, donem };
}

/// Önbellek anahtarı: kullanıcıya DEĞİL isteğe bağlı. BTC'nin 1G grafiğini
/// açan her kullanıcı aynı satırı paylaşır.
export function seriAnahtari(i: SeriIstegi): string {
  return `${i.kod}|${i.aralik}|${i.donem}`;
}

/// Önbellek ömrü = bir bar (en az 60 sn, en çok 1 saat). Bardan sık
/// tazelemek aynı barı yeniden çekmektir (`ResolutionTier.barSuresi` ile
/// aynı ilke).
export function seriTtlMs(aralik: string): number {
  const ms = ARALIK[aralik]?.ms ?? 60_000;
  return Math.min(Math.max(ms, 60_000), 60 * 60_000);
}

export function seriBaslangici(donem: string, simdiMs: number): number {
  const d = DONEM_MS[donem] ?? GUN;
  return Number.isFinite(d) ? Math.max(simdiMs - d, BINANCE_ACILIS_MS) : BINANCE_ACILIS_MS;
}

/// Binance kline satırı → `[açılış ms, kapanış]`. Bozuk satır atlanır.
export function mumlariCoz(rows: unknown): [number, number][] {
  if (!Array.isArray(rows)) return [];
  const out: [number, number][] = [];
  for (const r of rows) {
    if (!Array.isArray(r)) continue;
    const t = Number(r[0]);
    const c = pozitif(r[4]);
    if (Number.isFinite(t) && c !== null) out.push([t, c]);
  }
  return out;
}

/// USDT serisini TL'ye çevirir: aynı açılış anına sahip USDTTRY mumu ile
/// çarpar. Kuru olmayan nokta DÜŞER (sözleşme madde 3); en yakın kurla
/// doldurmak yok.
export function tlSerisi(
  coin: [number, number][],
  kur: [number, number][],
): [number, number][] {
  const k = new Map(kur);
  const out: [number, number][] = [];
  for (const [t, c] of coin) {
    const r = k.get(t);
    if (r !== undefined) out.push([t, c * r]);
  }
  return out;
}

// ── Sağlayıcı çağrıları ─────────────────────────────────────────────────────

/// `data-api.binance.vision` yalnızca piyasa verisi sunan uç; işlem uç
/// noktaları yok. Yanıt vermezse ana alan adı denenir.
export const BINANCE_TABANLARI = [
  'https://data-api.binance.vision',
  'https://api.binance.com',
];

const ZAMAN_ASIMI = 10_000;

/// Binance GET — iki taban sırayla. 429/418'de (ağırlık aşımı) ikinci
/// tabana GEÇMEZ: aynı IP'nin sınırı ortak, zorlamak ban süresini uzatır.
export async function binanceGet(
  yol: string,
  params: Record<string, string>,
  f: typeof fetch = fetch,
): Promise<unknown | null> {
  const qs = new URLSearchParams(params).toString();
  for (const taban of BINANCE_TABANLARI) {
    try {
      const res = await f(`${taban}${yol}${qs ? `?${qs}` : ''}`, {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(ZAMAN_ASIMI),
      });
      if (res.status === 429 || res.status === 418) {
        console.error(`binance ${yol}: ${res.status} (agirlik siniri)`);
        await res.body?.cancel();
        return null;
      }
      if (!res.ok) {
        console.error(`binance ${yol}: ${res.status} (${taban})`);
        await res.body?.cancel();
        continue;
      }
      return await res.json();
    } catch (e) {
      console.error(`binance ${yol}: ag hatasi (${taban})`, e instanceof Error ? e.name : '');
    }
  }
  return null;
}

/// Parçaları paralel sorar; başarısız parça diğerlerini düşürmez.
///
/// Bilinen sınır: Binance, parçadaki TEK bir geçersiz sembol için (tamamen
/// delist edilmiş coin) bütün parçayı 400 ile reddeder. Katalog saatte bir
/// yalnızca işlemdeki sembollerle yenilendiği için bu pencere en çok bir
/// saattir; o sürede aynı parçadaki coin'ler bayat görünür, yanlış görünmez.
export async function gunSatirlariniCek(
  parcalar: string[][],
  f: typeof fetch = fetch,
): Promise<{ satirlar: GunSatiri[]; basarili: number }> {
  const sonuc = await Promise.all(
    parcalar.map((p) =>
      binanceGet('/api/v3/ticker/tradingDay', {
        symbols: JSON.stringify(p),
        timeZone: '3',
        type: 'MINI',
      }, f)
    ),
  );
  const satirlar: GunSatiri[] = [];
  let basarili = 0;
  for (const s of sonuc) {
    if (!Array.isArray(s)) continue;
    basarili++;
    for (const r of s) {
      if (r && typeof r.symbol === 'string') satirlar.push(r as GunSatiri);
    }
  }
  return { satirlar, basarili };
}

/// Mumları sayfa sayfa çeker (başlangıçtan bugüne). `null` = sağlayıcı
/// yanıt vermedi (boş seri ile karıştırılmasın: önbellekteki bayat seri
/// o durumda korunur).
export async function mumlariCek(
  sembol: string,
  aralik: string,
  baslangicMs: number,
  simdiMs: number,
  f: typeof fetch = fetch,
): Promise<[number, number][] | null> {
  const a = ARALIK[aralik];
  if (!a) return null;
  const out: [number, number][] = [];
  let imlec = baslangicMs;
  for (let sayfa = 0; sayfa < AZAMI_SAYFA && imlec <= simdiMs; sayfa++) {
    const rows = await binanceGet('/api/v3/klines', {
      symbol: sembol,
      interval: a.binance,
      startTime: String(imlec),
      limit: String(SAYFA_MUM),
      // Günlük/haftalık mumlar İstanbul gece yarısında açılsın — "gün"
      // tanımı fiyat tablosuyla aynı. startTime her zaman UTC ms.
      timeZone: '3',
    }, f);
    if (rows === null) return sayfa === 0 ? null : out;
    const mumlar = mumlariCoz(rows);
    out.push(...mumlar);
    if (mumlar.length < SAYFA_MUM) break;
    imlec = mumlar[mumlar.length - 1][0] + a.ms;
  }
  return out;
}
