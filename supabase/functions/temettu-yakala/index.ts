// Temettü yakala — gerçekleşmiş temettüyü kullanıcıya ÖNERİ olarak getirir.
//
// ── Neden ───────────────────────────────────────────────────────────────────
// Temettü kaydı tamamen kullanıcının hafızasına kalmıştı: hisse temettü
// dağıttığında uygulama bunu bilmiyordu, kullanıcı unutursa getirisi eksik
// görünüyordu. Yahoo chart API'si (`events=div`) hak kullanımı YAPILMIŞ
// temettüleri TL/pay olarak veriyor; ilan edilmiş ama gerçekleşmemiş
// temettü yok — yani bildirim yalnızca olmuş bir şeyi söyler.
//
// ── Bu fonksiyon KAYIT YAZMAZ ───────────────────────────────────────────────
// Temettü satırı (`assets.kind='dividend'`) yine istemcide, `addDividend`
// yolundan ve kullanıcı ONAYIYLA yazılır: net tutarı (stopaj sonrası) ancak
// kullanıcı bilir ve temettü miktara girmez değişmezi tek yoldan korunur.
// Burada yazılan tek şey gönderim defteri (`temettu_bildirimleri`, 0086):
// olay 30 günlük pencerede her akşam yeniden görünür, defter ikinci
// bildirimi önler.
//
// ── Maliyet ─────────────────────────────────────────────────────────────────
// Sembol başına TEK Yahoo isteği (price_history.ts ilkesi): istek sayısı
// kullanıcı sayısıyla değil, BIST hisse çeşitliliğiyle ölçeklenir.
//
// ── Kim, hangi lot ──────────────────────────────────────────────────────────
// Evren: BUGÜN açık pozisyonu olan BIST hisseleri (`acikPozisyonLotlari`,
// push tarafının silme sezgisiyle). Lot: hak tarihinden ÖNCEKİ günlerde
// yapılmış alım − satım ([hakTarihindekiLot]). BIST'te hak kullanım günü
// açılışında fiyat düzeltilir; o gün alan temettü almaz, o gün satan alır.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';
import {
  appNotificationRow,
  recordAppNotification,
} from '../_shared/app_notifications.ts';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  acikPozisyonLotlari,
  pozisyonAnahtari,
  PozisyonLot,
} from '../_shared/positions.ts';
import { collapseTokens, TokenRow } from '../_shared/push_tokens.ts';
import { sessizKullanicilar } from '../_shared/quiet_hours.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya; Allow-Origin
  // bilinçli olarak yok (calendar-nudge ile aynı).
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

/// Brifingle aynı "bilgilendirici, acil değil" kanalı.
const CHANNEL_ID = 'brief_channel';

/// Olayın geriye bakış penceresi. Kullanıcı bir gün sessiz saatte ya da
/// tavana takıldıysa öneri sonraki akşamlarda yine gelebilsin diye birkaç
/// günden geniş; Yahoo'nun geç yazdığı olayı da yakalar.
export const PENCERE_GUN = 30;

/// Kullanıcı başına GÜNLÜK öneri tavanı. Bayram sonrası pek çok hisse aynı
/// hafta temettü dağıtır; on bildirim üst üste "spam" okunur. Tavanı aşan
/// olay deftere YAZILMAZ — ertesi akşam sıradaki olarak gelir.
export const GUNLUK_TAVAN = 3;

const GUN_MS = 24 * 60 * 60 * 1000;
/// TR sabit UTC+3, yaz saati yok (2016+).
const TR_OFSET_MS = 3 * 60 * 60 * 1000;
/// Kayan nokta toleransı (positions.ts ile aynı).
const EPSILON = 1e-7;

/// Önceden kaydedilmiş temettü bu aralıktaysa olay "kaydedildi" sayılır:
/// BIST'te ödeme genelde hak günü, taksitli ödemede aylar sonra da olabilir;
/// kullanıcı tarihi birkaç gün önce de girebilir.
export const KAYIT_ONCE_GUN = 7;
export const KAYIT_SONRA_GUN = 60;

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

// ── Saf parçalar (supabase/tests/temettu_yakala_test.ts) ───────────────────

export interface TemettuOlayi {
  /// Hak kullanım günü, TR takvimi (`YYYY-MM-DD`).
  hakTarihi: string;
  /// TL/pay, brüt.
  tutarPay: number;
}

/// Temettü satırı da okunur (kayıtlı mı?) — `PozisyonLot` + tutar.
export type VarlikSatiri = PozisyonLot & { dividend_amount?: number | null };

export interface TemettuOnerisi {
  user_id: string;
  ticker: string;
  hak_tarihi: string;
  tutar_pay: number;
  lot: number;
}

/// Epoch ms → TR günü (`YYYY-MM-DD`).
export function trGunu(ms: number): string {
  return new Date(ms + TR_OFSET_MS).toISOString().slice(0, 10);
}

function zamanMs(v: string | null | undefined): number | null {
  if (!v) return null;
  const t = new Date(v).getTime();
  return Number.isFinite(t) ? t : null;
}

/// `YYYY-MM-DD` + gün → `YYYY-MM-DD` (UTC takvim aritmetiği; saat yok).
function gunEkle(gun: string, n: number): string {
  return new Date(Date.parse(`${gun}T00:00:00Z`) + n * GUN_MS)
    .toISOString()
    .slice(0, 10);
}

/// Yahoo chart gövdesinden son [pencereGun] günün temettüleri.
///
/// Geçersiz tutar/tarih ATILIR — uydurma sayı yasağı: tutarı okunamayan
/// olay için "yaklaşık" bir öneri gönderilmez. Aynı güne iki kayıt gelirse
/// (Yahoo nadiren yineler) sonuncusu kalır.
export function temettuOlaylari(
  govde: unknown,
  simdiMs: number,
  pencereGun = PENCERE_GUN,
): TemettuOlayi[] {
  // deno-lint-ignore no-explicit-any
  const div = (govde as any)?.chart?.result?.[0]?.events?.dividends;
  if (!div || typeof div !== 'object') return [];
  const alt = trGunu(simdiMs - pencereGun * GUN_MS);
  const ust = trGunu(simdiMs);
  const tekil = new Map<string, number>();
  for (const v of Object.values(div as Record<string, unknown>)) {
    const o = v as { date?: unknown; amount?: unknown } | null;
    const tarih = Number(o?.date);
    const tutar = Number(o?.amount);
    if (!Number.isFinite(tarih) || tarih <= 0) continue;
    if (!Number.isFinite(tutar) || tutar <= 0) continue;
    const gun = trGunu(tarih * 1000);
    if (gun < alt || gun > ust) continue;
    tekil.set(gun, tutar);
  }
  return [...tekil]
    .map(([hakTarihi, tutarPay]) => ({ hakTarihi, tutarPay }))
    .sort((a, b) => (a.hakTarihi < b.hakTarihi ? -1 : 1));
}

/// Tek pozisyonun (aynı kullanıcı + aynı [pozisyonAnahtari]) satırlarından
/// hak tarihindeki net lot.
///
/// Kurallar `acikPozisyonLotlari` ile aynı aileden:
///   · yalnız `buy`/`sell` miktara girer; temettü ASLA (nakit hareketi),
///   · `ref_asset_id`'li mezar taşının işaret ettiği lot yok sayılır,
///   · pozisyonun tamamını silen mezar taşından ESKİ hareketler o silinmiş
///     "kuşağa" aittir, sayılmaz (sil → yeniden al = yeni pozisyon),
///   · mezar taşları TARİHTEN BAĞIMSIZ uygulanır: silme bugünün kararıdır,
///     hak tarihinden sonra silinmiş lot da öneri doğurmaz,
///   · tarihi okunamayan hareket hak tarihine bağlanamaz, atlanır.
/// Hak günü ve sonrasındaki alım hak kazandırmaz; hak gününde satış hakkı
/// düşürmez (fiyat açılışta düzeltilir).
export function hakTarihindekiLot(
  satirlar: PozisyonLot[],
  hakTarihi: string,
): number {
  const silinenLot = new Set<string>();
  let silmeAni: number | null = null;
  for (const r of satirlar) {
    if ((r.kind ?? 'buy') !== 'delete_log') continue;
    if (r.ref_asset_id != null) {
      silinenLot.add(String(r.ref_asset_id));
      continue;
    }
    const t = zamanMs(r.added_date);
    if (t !== null && (silmeAni === null || t > silmeAni)) silmeAni = t;
  }

  let net = 0;
  for (const r of satirlar) {
    const kind = r.kind ?? 'buy';
    if (kind !== 'buy' && kind !== 'sell') continue;
    if (silinenLot.has(String(r.id))) continue;
    const t = zamanMs(r.added_date);
    if (t === null) continue;
    if (trGunu(t) >= hakTarihi) continue;
    if (silmeAni !== null && t <= silmeAni) continue;
    const q = Number(r.quantity ?? 0);
    if (!Number.isFinite(q)) continue;
    net += kind === 'sell' ? -q : q;
  }
  return net > EPSILON ? net : 0;
}

/// Kullanıcı bu olay için temettüyü ZATEN kaydetmiş mi?
///
/// Eşleme tarih penceresiyle ([KAYIT_ONCE_GUN], [KAYIT_SONRA_GUN]): kayıt
/// satırı hak tarihini taşımaz, kullanıcının girdiği ödeme gününü taşır.
export function temettuKayitliMi(
  satirlar: PozisyonLot[],
  hakTarihi: string,
): boolean {
  const alt = gunEkle(hakTarihi, -KAYIT_ONCE_GUN);
  const ust = gunEkle(hakTarihi, KAYIT_SONRA_GUN);
  return satirlar.some((r) => {
    if (r.kind !== 'dividend') return false;
    const t = zamanMs(r.added_date);
    if (t === null) return false;
    const gun = trGunu(t);
    return gun >= alt && gun <= ust;
  });
}

function sembolu(r: PozisyonLot): string {
  return (r.ticker ?? '').trim().toUpperCase();
}

/// Öneri alabilecek satır: TRY kote BIST hissesi (`.IS`). USD kote ya da
/// sembolsüz hissenin Yahoo temettüsü TL/pay değildir ya da hiç yoktur.
function bistHissesiMi(r: PozisyonLot): boolean {
  return r.type === 'hisse' &&
    sembolu(r).endsWith('.IS') &&
    (r.currency ?? 'TRY').toUpperCase() === 'TRY';
}

/// Bugün açık pozisyonu olan BIST hisselerinin TEKİL sembolleri — Yahoo'ya
/// sembol başına bir istek atılır.
export function yakalanacakSemboller(satirlar: PozisyonLot[]): string[] {
  const s = new Set<string>();
  for (const r of acikPozisyonLotlari(satirlar)) {
    if (bistHissesiMi(r)) s.add(sembolu(r));
  }
  return [...s].sort();
}

/// Defter anahtarı — `temettu_bildirimleri` PK'sıyla aynı.
export function defterAnahtari(
  userId: string,
  ticker: string,
  hakTarihi: string,
): string {
  return `${userId}|${ticker.toUpperCase()}|${hakTarihi}`;
}

/// Olaylar × açık pozisyonlar → gönderilecek öneriler.
///
/// [gonderilmis]: defterdeki anahtarlar ([defterAnahtari]); [bugunGonderilen]:
/// kullanıcı başına BUGÜN (TR) deftere yazılmış öneri sayısı — tavan elle
/// ikinci koşuda da tutsun. Sıra: kullanıcı içinde en ESKİ olay önce (pencereden
/// ilk o düşecek).
export function onerileriKur(p: {
  satirlar: PozisyonLot[];
  olaylar: Map<string, TemettuOlayi[]>;
  gonderilmis: Set<string>;
  bugunGonderilen?: Map<string, number>;
  tavan?: number;
}): TemettuOnerisi[] {
  const tavan = p.tavan ?? GUNLUK_TAVAN;
  const gruplar = new Map<string, PozisyonLot[]>();
  for (const r of p.satirlar) {
    const k = pozisyonAnahtari(r);
    const g = gruplar.get(k);
    if (g) g.push(r);
    else gruplar.set(k, [r]);
  }

  const acikAnahtarlar = new Map<string, PozisyonLot>();
  for (const r of acikPozisyonLotlari(p.satirlar)) {
    if (!bistHissesiMi(r)) continue;
    const k = pozisyonAnahtari(r);
    if (!acikAnahtarlar.has(k)) acikAnahtarlar.set(k, r);
  }

  const adaylar: TemettuOnerisi[] = [];
  for (const [k, ornek] of acikAnahtarlar) {
    const ticker = sembolu(ornek);
    const grup = gruplar.get(k) ?? [];
    for (const olay of p.olaylar.get(ticker) ?? []) {
      if (p.gonderilmis.has(defterAnahtari(ornek.user_id, ticker, olay.hakTarihi))) {
        continue;
      }
      const lot = hakTarihindekiLot(grup, olay.hakTarihi);
      if (lot <= 0) continue;
      if (temettuKayitliMi(grup, olay.hakTarihi)) continue;
      adaylar.push({
        user_id: ornek.user_id,
        ticker,
        hak_tarihi: olay.hakTarihi,
        tutar_pay: olay.tutarPay,
        lot,
      });
    }
  }

  adaylar.sort((a, b) =>
    a.user_id !== b.user_id
      ? (a.user_id < b.user_id ? -1 : 1)
      : a.hak_tarihi !== b.hak_tarihi
      ? (a.hak_tarihi < b.hak_tarihi ? -1 : 1)
      : (a.ticker < b.ticker ? -1 : 1)
  );
  const sayac = new Map(p.bugunGonderilen ?? []);
  const out: TemettuOnerisi[] = [];
  for (const o of adaylar) {
    const n = sayac.get(o.user_id) ?? 0;
    if (n >= tavan) continue;
    sayac.set(o.user_id, n + 1);
    out.push(o);
  }
  return out;
}

/// Türkçe sayı: 1234.5 → "1.234,50" ([basamak] = 2).
export function trSayi(v: number, basamak: number): string {
  const [tam, kesir] = v.toFixed(basamak).split('.');
  const eksi = tam.startsWith('-');
  const rakam = eksi ? tam.slice(1) : tam;
  const binli = rakam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${eksi ? '-' : ''}${binli}${kesir ? `,${kesir}` : ''}`;
}

/// Pay tutarı: en az 2, gerekirse 4 ondalık (0,0512 gibi küçük temettü
/// 0,05'e yuvarlanıp yanlış okunmasın); sondaki sıfırlar 2'ye kadar kırpılır.
export function tutarYazisi(v: number): string {
  let s = trSayi(v, 4);
  while (/,\d{3,}$/.test(s) && s.endsWith('0')) s = s.slice(0, -1);
  return s;
}

/// Lot: tam sayıysa ondalıksız, değilse en fazla 4 ondalık.
export function lotYazisi(v: number): string {
  if (Math.abs(v - Math.round(v)) < EPSILON) return trSayi(Math.round(v), 0);
  let s = trSayi(v, 4);
  while (s.endsWith('0')) s = s.slice(0, -1);
  return s.endsWith(',') ? s.slice(0, -1) : s;
}

/// "THYAO temettü dağıttı" / "100 lot × ₺3,44 (brüt). Kaydetmek ister misin?"
///
/// BRÜT yazılır ve bunu söyler: stopaj oranı sunucuda bilinmiyor; net
/// tutarı uydurmaktansa kullanıcıya onaylatırken istemci hesaplar.
export function temettuMesaji(o: TemettuOnerisi): { title: string; body: string } {
  const kod = o.ticker.replace(/\.IS$/i, '');
  return {
    title: `${kod} temettü dağıttı`,
    body: `${lotYazisi(o.lot)} lot × ₺${tutarYazisi(o.tutar_pay)} (brüt). ` +
      'Kaydetmek ister misin?',
  };
}

/// Push/çan verisi — istemci `TemettuOnerisi.fromPush` ile okur. Sayılar
/// makine biçiminde (nokta ondalık), metin değil.
export function temettuVerisi(o: TemettuOnerisi): Record<string, string> {
  return {
    type: 'temettu',
    ticker: o.ticker,
    hak_tarihi: o.hak_tarihi,
    tutar_pay: String(o.tutar_pay),
    lot: String(o.lot),
  };
}

/// Yahoo'dan bir sembolün son [PENCERE_GUN] temettüleri. Hata → boş liste
/// (o sembol bu akşam atlanır, yarın yeniden denenir).
export async function temettuleriCek(
  sembol: string,
  simdiMs: number,
  f: typeof fetch = fetch,
): Promise<TemettuOlayi[]> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(sembol)}` +
    '?range=3mo&interval=1d&events=div';
  try {
    const res = await f(url, {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return [];
    return temettuOlaylari(await res.json(), simdiMs);
  } catch (_) {
    return [];
  }
}

// ── G/Ç ────────────────────────────────────────────────────────────────────

const VARLIK_SUTUNLARI =
  'id, user_id, name, ticker, type, sub_category, currency, quantity, kind, added_date, ref_asset_id';

/// Aktif hisse defteri, sayfalı (PostgREST `max_rows` = 1000; sayfasız
/// okuma kullanıcıları sessizce düşürür — leaderboard-snapshot notu).
async function hisseDefteri(admin: SupabaseClient): Promise<PozisyonLot[]> {
  const SAYFA = 1000;
  const out: PozisyonLot[] = [];
  for (let bas = 0;; bas += SAYFA) {
    const { data, error } = await admin
      .from('assets')
      .select(VARLIK_SUTUNLARI)
      .eq('type', 'hisse')
      .is('deleted_at', null)
      .order('id')
      .range(bas, bas + SAYFA - 1);
    if (error) throw new Error(`Varliklar alinamadi: ${error.message}`);
    const satirlar = (data ?? []) as PozisyonLot[];
    out.push(...satirlar);
    if (satirlar.length < SAYFA) break;
  }
  return out;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('TEMETTU_YAKALA_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (cron_auth.ts), sonra başlık kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'TEMETTU_YAKALA_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Env denetimi kapıdan SONRA: yetkisiz çağıran eksik yapılandırmayı
    // öğrenemesin (2026-09-23 denetimi L2).
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY yok.');
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error('FCM secret\'lari eksik.');
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);
    const simdi = Date.now();
    const bugun = trGunu(simdi);

    // 1) Defter + semboller.
    const satirlar = await hisseDefteri(admin);
    const semboller = yakalanacakSemboller(satirlar);
    if (semboller.length === 0) {
      return jsonResponse({ ok: true, reason: 'BIST hissesi yok.', sent: 0 });
    }

    // 2) Sembol başına BİR istek; sıralı — Yahoo'yu patlama ile yormamak
    // için (akşam koşusu, süre sorun değil).
    const olaylar = new Map<string, TemettuOlayi[]>();
    for (const s of semboller) {
      const o = await temettuleriCek(s, simdi);
      if (o.length > 0) olaylar.set(s, o);
    }
    if (olaylar.size === 0) {
      return jsonResponse({ ok: true, reason: 'Pencerede temettu yok.', sent: 0 });
    }

    // 3) Gönderim defteri: pencere + bugünün tavan sayacı.
    const { data: defterRows, error: defterHatasi } = await admin
      .from('temettu_bildirimleri')
      .select('user_id, ticker, hak_tarihi, created_at')
      .gte('hak_tarihi', gunEkle(bugun, -(PENCERE_GUN + 1)));
    // Defter okunamıyorsa DUR: okumadan göndermek herkese dünkü
    // bildirimi yeniden atar.
    if (defterHatasi) throw new Error(`Defter okunamadi: ${defterHatasi.message}`);
    const gonderilmis = new Set<string>();
    const bugunGonderilen = new Map<string, number>();
    for (const r of (defterRows ?? []) as Array<Record<string, string>>) {
      gonderilmis.add(defterAnahtari(r.user_id, r.ticker, r.hak_tarihi));
      const t = zamanMs(r.created_at);
      if (t !== null && trGunu(t) === bugun) {
        bugunGonderilen.set(r.user_id, (bugunGonderilen.get(r.user_id) ?? 0) + 1);
      }
    }

    const oneriler = onerileriKur({ satirlar, olaylar, gonderilmis, bugunGonderilen });
    if (oneriler.length === 0) {
      return jsonResponse({ ok: true, reason: 'Yeni oneri yok.', sent: 0 });
    }
    if (dryRun) {
      return jsonResponse({
        ok: true,
        dry_run: true,
        semboller: olaylar.size,
        would_suggest: oneriler.length,
      });
    }

    // 4) Token'lar + sessiz saatler.
    const kullanicilar = [...new Set(oneriler.map((o) => o.user_id))];
    const { data: tokenRows } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at')
      .in('user_id', kullanicilar);
    const tokenlar = new Map<string, string[]>();
    for (const t of collapseTokens((tokenRows ?? []) as TokenRow[])) {
      const l = tokenlar.get(t.user_id) ?? [];
      l.push(t.token);
      tokenlar.set(t.user_id, l);
    }
    const sessiz = await sessizKullanicilar(admin, kullanicilar);

    let accessToken: string | null = null;
    let sent = 0;
    let skippedQuietHours = 0;
    let yazilan = 0;
    const failures: string[] = [];

    for (const o of oneriler) {
      // Defter ÖNCE: satır yazılamazsa push da gitmez — yazılmadan giden
      // bildirim yarın yine giderdi. Çakışma (23505) = eşzamanlı ikinci
      // koşu zaten yazmış; bu öneri onun.
      const { error: yazHatasi } = await admin
        .from('temettu_bildirimleri')
        .insert({
          user_id: o.user_id,
          ticker: o.ticker,
          hak_tarihi: o.hak_tarihi,
          tutar_pay: o.tutar_pay,
          lot: o.lot,
        });
      if (yazHatasi) {
        if (yazHatasi.code !== '23505') {
          console.error('[temettu-yakala] defter yazilamadi:', yazHatasi.message);
          failures.push('defter: yazilamadi');
        }
        continue;
      }
      yazilan += 1;

      const mesaj = temettuMesaji(o);
      const veri = temettuVerisi(o);
      // Çan kaydı push'tan BAĞIMSIZ: sessiz saatte ya da token yokken de
      // öneri kaybolmaz (defter yazıldı, push bir daha denenmeyecek).
      const kayitHatasi = await recordAppNotification(
        admin,
        appNotificationRow({
          userId: o.user_id,
          type: 'temettu',
          title: mesaj.title,
          body: mesaj.body,
          data: veri,
        }),
      );
      if (kayitHatasi) failures.push(kayitHatasi);

      // Sessiz saat (0057): push ATLANIR, ertelenmez — öneri çanda bekler.
      if (sessiz.has(o.user_id)) {
        skippedQuietHours += 1;
        continue;
      }
      const hedefler = tokenlar.get(o.user_id) ?? [];
      if (hedefler.length === 0) continue;
      accessToken ??= await createAccessToken(
        JSON.parse(fcmServiceAccountJson) as ServiceAccount,
      );
      for (const token of hedefler) {
        const r = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token,
          title: mesaj.title,
          body: mesaj.body,
          channelId: CHANNEL_ID,
          data: veri,
        });
        if (r.ok) {
          sent += 1;
        } else {
          // Ham FCM gövdesi yalnız günlüğe; yanıta kısa kod.
          console.error('[temettu-yakala] FCM basarisiz:', r.rawText.slice(0, 500));
          failures.push(`fcm: ${r.hataKodu}`);
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', token);
          }
        }
      }
    }

    return jsonResponse({
      ok: true,
      oneriler: yazilan,
      sent,
      skipped_quiet_hours: skippedQuietHours,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    // Ayrıntı yalnız günlüğe: `error.message` tablo/sütun adlarını sızdırır.
    console.error('[temettu-yakala] hata:', error);
    return jsonResponse({ error: 'Temettu yakalama basarisiz.' }, 500);
  }
});
