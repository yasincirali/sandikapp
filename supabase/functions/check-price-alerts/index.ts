// Check Price Alerts — kullanıcının kendi kurduğu fiyat alarmları.
//
// pg_cron ile TR 08:00–21:30 arası tetiklenir (0168'den beri iki iş):
//   · `check-price-alerts`       :00 ve :30 — gövde `{}`, HER tür (eski davranış)
//   · `check-price-alerts-hizli` aradaki 5 dakikalar — gövde
//     `{"turler":["altin","doviz","kripto"]}`, yalnız fiyatı 5 dakikadan sık
//     tazelenen türler. BIST/fon kaynakları zaten gecikmeli ya da günlük;
//     onları 5 dakikada sormak Yahoo/TEFAS'a boşa istek olurdu.
//
// Bu, kullanıcının KENDİSİNİN istediği tek bildirim: alaka garantili,
// opt-out riski taşımıyor. Sunucuda değerlendirilir ki uygulama kapalıyken
// de çalışsın — yalnızca açıkken çalışan bir alarm geri getirme kanalı
// değildir, sadece bir ekran öğesidir.
//
// 0169: aynı turda yüzde alarmları da (`_shared/yuzde_alarmi.ts`, "gram
// altın bugün %2 düşerse"). Ayrı tablo, ayrı damga; fiyat alarmının
// sorgusu, tetikleme kuralı ve sırası değişmedi.
//
// 0170 (2026-10-29): gösterge ve çizgi alarmları da (`_shared/
// seviye_alarmi.ts`, "EMA50'yi keserse", "çizdiğim trend çizgisine
// değerse"). Yine ayrı tablolar, ayrı damga, try içinde; yanıta yalnız
// `seviye` alanı eklenir.
//
// 0171 (2026-10-29): "Her geçişte haber ver" (`price_alerts.tekrar`).
// Tekrarlı alarm çalınca SÖNDÜRÜLMEZ; hedefin öbür tarafına %0,5 tamponla
// geçince nöbete döner, günde en çok 3 kez çalar (`_shared/
// fiyat_alarmi_tekrar.ts`). `tekrar=false` alarmın dalı (isTriggered +
// alarmiSondur + metin) birebir eskisi; yanıta yalnız `nobete_donen` eklenir.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';
import { fiyatMetni, fiyatSayisi, kotasyonSimgesi } from '../_shared/fiyat_metni.ts';
import {
  fetchLivePrices,
  isFxSymbol,
  isGoldSymbol,
} from '../_shared/live_prices.ts';
import { kriptoMu } from '../_shared/kripto.ts';
import {
  fiyatKaynagiKanaryasi,
  kanaryaKismiMi,
  type KanaryaSonucu,
} from '../_shared/kanarya.ts';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  TokenRow,
  tokenSatirlariniOku,
} from '../_shared/push_tokens.ts';
import {
  kartGorseli,
  KartAyari,
  KartVerisi,
  kartVerisiniHazirla,
} from '../_shared/bildirim_karti.ts';
import { takipListesiHareketleri } from '../_shared/watchlist_moves.ts';
import { yuzdeAlarmTuruKos } from '../_shared/yuzde_alarmi.ts';
import { seviyeAlarmTuruKos } from '../_shared/seviye_alarmi.ts';
import {
  GUNLUK_TAVAN,
  tekrarKarari,
  type TekrarKarari,
} from '../_shared/fiyat_alarmi_tekrar.ts';

// Testler bu modülden okuyor; kaynağı `_shared/push_tokens.ts`.
export { collapseTokens };
import { sessizKullanicilar } from '../_shared/quiet_hours.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

/// Ayrı kanal: kullanıcı alarmları açık tutup brifingi kapatabilmeli.
const CHANNEL_ID = 'alert_channel';

type AlertRow = {
  id: string;
  user_id: string;
  symbol: string;
  label: string;
  target_price: number;
  direction: string;
  // 0171 — migration'dan önceki şemada yok; yoksa tek atış sayılır.
  tekrar?: boolean | null;
  triggered_at?: string | null;
  gunluk_tetik_sayisi?: number | null;
  gunluk_tetik_gunu?: string | null;
};

/// Eski sorgunun kolonları (0046) ve 0171'in ekledikleri.
const ALARM_KOLONLARI = 'id, user_id, symbol, label, target_price, direction';
const TEKRAR_KOLONLARI =
  `${ALARM_KOLONLARI}, tekrar, triggered_at, gunluk_tetik_sayisi, gunluk_tetik_gunu`;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Hızlı turun anladığı türler (0168). Liste dışı ad yok sayılır.
export type AlarmTuru = 'altin' | 'doviz' | 'kripto' | 'diger';
const HIZLI_TURLER: ReadonlySet<AlarmTuru> = new Set(['altin', 'doviz', 'kripto']);

/// Sembolün alarm türü — `live_prices.ts`'in kaynak seçimiyle AYNI ayrım:
/// altın ve döviz truncgil'den, kripto `kripto_fiyat` tablosundan (2 dk)
/// gelir; geri kalanı (BIST, fon, emtia, eurobond) 30 dakikalık turda kalır.
export function alarmTuru(symbol: string): AlarmTuru {
  if (isGoldSymbol(symbol)) return 'altin';
  if (isFxSymbol(symbol)) return 'doviz';
  if (kriptoMu(symbol)) return 'kripto';
  return 'diger';
}

/// Gövdedeki `turler` → filtre; `null` = HER tür.
///
/// Eski çağrılar (parametresiz cron, panel/SQL'den elle `{}`/`dry_run`)
/// bugünkü gibi her türü değerlendirir: alan yoksa, dizi değilse ya da
/// içinde tanınan tek ad yoksa `null`. Bilinmeyen değerde HİÇBİR alarmı
/// değerlendirmemek "alarm sessizce öldü" demek olurdu; fazla değerlendirmek
/// zararsız (tek atış damgası tekrarı önler).
export function turFiltresi(raw: unknown): ReadonlySet<AlarmTuru> | null {
  if (!Array.isArray(raw)) return null;
  const out = new Set<AlarmTuru>();
  for (const t of raw) {
    if (typeof t === 'string' && HIZLI_TURLER.has(t as AlarmTuru)) {
      out.add(t as AlarmTuru);
    }
  }
  return out.size === 0 ? null : out;
}

/// Bu turda değerlendirilecek alarmlar. Filtre fiyat çekiminden ÖNCE
/// uygulanır ki hızlı tur Yahoo/TEFAS'a hiç gitmesin.
export function turaGirenAlarmlar<T extends { symbol: string }>(
  alerts: T[],
  filtre: ReadonlySet<AlarmTuru> | null,
): T[] {
  if (filtre === null) return alerts;
  return alerts.filter((a) => filtre.has(alarmTuru(a.symbol)));
}

/// Alarmı söndürür; YALNIZ bu çağrı söndürdüyse `'sondu'`.
///
/// 0168 öncesi `.is('triggered_at', null)` yarış korumasıydı ama sonuç
/// okunmuyordu: eşleşmeyen UPDATE hata DEĞİL, boş sonuçtur — çakışan iki
/// tur ikisi de push gönderirdi. 5 dakikalık ritimde (fonksiyon 60 sn'yi
/// aşarsa) çakışma artık kuramsal değil; satır dönmezse push gitmez.
export async function alarmiSondur(
  // deno-lint-ignore no-explicit-any
  admin: { from: (t: string) => any },
  id: string,
  simdi: Date = new Date(),
): Promise<'sondu' | 'zaten' | 'hata'> {
  const { data, error } = await admin
    .from('price_alerts')
    .update({ triggered_at: simdi.toISOString(), enabled: false })
    .eq('id', id)
    .is('triggered_at', null)
    .select('id');
  if (error) {
    // DB mesajı yalnızca günlüğe; yanıta sabit kod (2026-09-23 denetimi L2).
    console.error('[check-price-alerts] damga yazilamadi:', error.message);
    return 'hata';
  }
  return Array.isArray(data) && data.length > 0 ? 'sondu' : 'zaten';
}

/// Tekrarlı alarmın çalışını yazar (0171); YALNIZ bu çağrı yazdıysa `'caldi'`.
///
/// `alarmiSondur`'un eşi, tek farkla: `enabled` true kalır. Aynı yarış
/// koruması (`triggered_at is null` koşullu UPDATE; satır dönmezse push
/// gitmez). `son_tetik_at` nöbete dönüşte silinmez, listedeki "son çaldı"
/// satırını besler.
export async function tekrarliCalisiYaz(
  // deno-lint-ignore no-explicit-any
  admin: { from: (t: string) => any },
  id: string,
  karar: Extract<TekrarKarari, { tur: 'cal' }>,
  simdi: Date = new Date(),
): Promise<'caldi' | 'zaten' | 'hata'> {
  const an = simdi.toISOString();
  const { data, error } = await admin
    .from('price_alerts')
    .update({
      triggered_at: an,
      son_tetik_at: an,
      gunluk_tetik_sayisi: karar.sayi,
      gunluk_tetik_gunu: karar.gun,
    })
    .eq('id', id)
    .is('triggered_at', null)
    .select('id');
  if (error) {
    console.error('[check-price-alerts] tekrar damgasi yazilamadi:', error.message);
    return 'hata';
  }
  return Array.isArray(data) && data.length > 0 ? 'caldi' : 'zaten';
}

/// Çalmış tekrarlı alarmı nöbete döndürür (0171): `triggered_at` null.
///
/// Koşul okunan damga: arada başka tur çaldırdıysa ya da kişi alarmı
/// kapattıysa eski okumaya göre verilmiş karar yazılmaz. Eski build bu
/// satırı yeniden "bekleyen" görür (`enabled && triggered_at == null`).
export async function nobeteDondur(
  // deno-lint-ignore no-explicit-any
  admin: { from: (t: string) => any },
  id: string,
  okunanDamga: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from('price_alerts')
    .update({ triggered_at: null })
    .eq('id', id)
    .eq('enabled', true)
    .eq('triggered_at', okunanDamga)
    .select('id');
  if (error) {
    console.error('[check-price-alerts] nobete donus yazilamadi:', error.message);
    return false;
  }
  return Array.isArray(data) && data.length > 0;
}

/// Alarm tetiklendi mi?
///
/// Sınır DAHİLDİR: kullanıcı "5.400 olunca" der, "5.400'ü geçince" demez.
/// Tam eşitlikte tetiklememek, hedefine ulaşmış bir alarmın sessiz kalması
/// demek olurdu.
export function isTriggered(
  price: number,
  target: number,
  direction: string,
): boolean {
  if (!Number.isFinite(price) || price <= 0) return false;
  return direction === 'above' ? price >= target : price <= target;
}

/// Türkçe para biçimi: 5412.37 → "5.412,37"
///
/// `Intl` Deno'da mevcut ama `tr-TR` verisi çalışma zamanına göre eksik
/// olabiliyor; bildirim metni sessizce "5,412.37" olarak çıkarsa kullanıcı
/// rakamı yanlış okur. Elle biçimlendirmek bu belirsizliği kaldırır.
///
/// 2026-10-29: kural `_shared/fiyat_metni.ts › fiyatSayisi`'ye taşındı —
/// 1'in altındaki fiyat (SHIB ₺0,0004) 2 haneye yuvarlanıp "0,00"
/// okunuyordu. Ad, eski içe aktaranlar için kalır.
export function formatTRY(value: number): string {
  return fiyatSayisi(value);
}

/// [simge]: kotasyonun para simgesi (`kotasyonSimgesi`); `null` → simgesiz.
/// Varsayılan ₺ eski çağıranlar için (alarmların çoğu TL kote).
///
/// 2026-10-29 (bildirim denetimi): başlık ve gövde simgeli ("$" ABD
/// hissesinde) ve alarmın tek seferlik olduğunu, artık KAPALI olduğunu
/// söyler — kullanıcı "yine çalacak mı?" diye sormasın; çan satırı da aynı
/// metni okur.
///
/// [tekrar] (0171): aynı soruya öbür cevap — alarm açık kalır, fiyat geri
/// dönüp yeniden geçerse yine haber verir. Varsayılan `false`: metin birebir.
///
/// [sonCalis] (Ar-Ge 30 Eki #0): günün son çalışı (`GUNLUK_TAVAN`). "Yine
/// haber vereceğiz" demek yalan olurdu — o gün alarm susar; susan alarm
/// bozuk sanılmasın diye bu bildirim bunu söyler.
export function buildAlertMessage(
  label: string,
  price: number,
  target: number,
  direction: string,
  simge: string | null = '₺',
  tekrar = false,
  sonCalis = false,
): { title: string; body: string } {
  const yukari = direction === 'above';
  return {
    title: `${yukari ? '▲' : '▼'} ${label} ${fiyatMetni(target, simge)} ` +
      `${yukari ? 'seviyesine ulaştı' : 'seviyesinin altına indi'}`,
    body: `Şu an ${fiyatMetni(price, simge)}. ` +
      (tekrar && sonCalis
        ? `Bugün ${GUNLUK_TAVAN}. kez çaldı; yarın yeniden nöbette. `
        : tekrar
        ? 'Alarm açık: fiyat geri dönüp yeniden geçerse yine haber vereceğiz. '
        : 'Tek seferlik alarmdı, kapatıldı. ') +
      'Yatırım tavsiyesi değildir.',
  };
}

/// Fiyat alarmının kartı (yalnız `bildirim_surumu >= 2` cihazlar).
///
/// Değişim yüzdesi değil EŞİK bildirimi: halka büyüklük göstermez, yön
/// renginde tam çizilir; büyük satır şu anki fiyat, alt satır hedef.
export function buildAlertCard(
  label: string,
  price: number,
  target: number,
  direction: string,
  simge: string | null = '₺',
): KartVerisi | null {
  if (!Number.isFinite(price) || !Number.isFinite(target)) return null;
  return kartVerisiniHazirla({
    e: label,
    b: fiyatMetni(price, simge),
    y: direction === 'above' ? 'u' : 'd',
    a: `Fiyat alarmı · hedef ${fiyatMetni(target, simge)}`,
  });
}

/// Cihaz başına tek token (bkz. daily-brief/index.ts — aynı gerekçe).

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Env denetimi kapıdan SONRA (2026-09-23 denetimi L2): yetkisiz çağıran
    // eksik yapılandırmayı ya da secret adlarını öğrenemesin.
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY yok.');
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error('FCM secret\'ları eksik.');
    }

    let dryRun = false;
    // `watchlist: true` → alarm turu DEĞİL, takip listesi hareketi turu
    // (0068 cron'u, TR 18:25). Aynı secret, aynı fonksiyon: alarm kanalının
    // doğal uzantısı; ayrı fonksiyon ayrı secret ve ayrı dağıtım demekti.
    let watchlist = false;
    let filtre: ReadonlySet<AlarmTuru> | null = null;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (body?.watchlist === true) watchlist = true;
      filtre = turFiltresi(body?.turler);
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);
    // Bildirim kartı (0092, yalnız yeni sürüm cihazlar) — bkz. bildirim_karti.ts.
    const kart: KartAyari = { supabaseUrl, anahtar: serviceRoleKey };

    if (watchlist) {
      return jsonResponse(await takipListesiHareketleri(admin, {
        dryRun,
        fcm: dryRun
          ? null
          : { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson },
        kart,
      }));
    }

    // ── 0) Yüzde alarmları (0169) ───────────────────────────────────────────
    // Fiyat alarmından ÖNCE ve ondan BAĞIMSIZ: kendi tablosu, kendi damgası.
    // Hata yutulur (günlüğe yazılır) ki aşağıdaki fiyat alarmı turu birebir
    // eskisi gibi koşsun; yanıta yalnız `yuzde` alanı eklenir.
    let yuzde: Record<string, unknown>;
    try {
      yuzde = await yuzdeAlarmTuruKos(admin, {
        dryRun,
        filtre,
        fcm: dryRun
          ? null
          : { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson },
        kart,
      });
    } catch (e) {
      console.error('[check-price-alerts] yuzde alarm turu basarisiz:', e);
      yuzde = { error: 'yuzde alarm turu basarisiz' };
    }

    // ── 0b) Gösterge ve çizgi alarmları (0170) ──────────────────────────────
    // Yüzde turuyla aynı sözleşme: bağımsız, hata yutulur, fiyat alarmı
    // turu birebir eskisi gibi koşar. Hızlı turda yalnız o turun türleri
    // (0168 süzgeci, fiyat alarmıyla aynı `alarmTuru`).
    let seviye: Record<string, unknown>;
    try {
      seviye = await seviyeAlarmTuruKos(admin, {
        dryRun,
        turaGirer: (s) => filtre === null || filtre.has(alarmTuru(s)),
        fcm: dryRun
          ? null
          : { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson },
        kart,
      });
    } catch (e) {
      console.error('[check-price-alerts] seviye alarm turu basarisiz:', e);
      seviye = { error: 'seviye alarm turu basarisiz' };
    }

    // ── 1) Aktif alarmlar ───────────────────────────────────────────────────
    // 0171 kolonlarıyla okunur; şema henüz 0171'i almadıysa (fonksiyon
    // migration'dan önce dağıtıldı) eski kolonlarla yeniden sorulur ve
    // hepsi tek atış sayılır — alarm turu kolon yüzünden ölmesin.
    const aktifSorgu = (kolonlar: string) => admin
      .from('price_alerts')
      .select(kolonlar)
      .eq('enabled', true)
      .is('triggered_at', null);
    let tekrarSemasi = true;
    let { data: alertRows, error: alertError } = await aktifSorgu(TEKRAR_KOLONLARI);
    if (alertError) {
      console.error('[check-price-alerts] 0171 kolonlari okunamadi:', alertError.message);
      tekrarSemasi = false;
      ({ data: alertRows, error: alertError } = await aktifSorgu(ALARM_KOLONLARI));
    }
    if (alertError) throw new Error(`Alarmlar alinamadi: ${alertError.message}`);

    const alerts = turaGirenAlarmlar((alertRows ?? []) as unknown as AlertRow[], filtre);

    // ── 1b) Nöbete dönmeyi bekleyen tekrarlı alarmlar (0171) ────────────────
    // Çalmış (`triggered_at` dolu) ama açık tekrarlı alarmlar. Hata yutulur:
    // bu tur kaçarsa alarm bir sonraki turda döner; fiyat alarmı turu
    // etkilenmez.
    let donecekler: AlertRow[] = [];
    if (tekrarSemasi) {
      const { data: donusRows, error: donusError } = await admin
        .from('price_alerts')
        .select(TEKRAR_KOLONLARI)
        .eq('enabled', true)
        .eq('tekrar', true)
        .not('triggered_at', 'is', null);
      if (donusError) {
        console.error('[check-price-alerts] nobet donusu okunamadi:', donusError.message);
      } else {
        donecekler = turaGirenAlarmlar((donusRows ?? []) as unknown as AlertRow[], filtre);
      }
    }

    if (alerts.length === 0 && donecekler.length === 0) {
      return jsonResponse({ ok: true, reason: 'Aktif alarm yok.', sent: 0, yuzde, seviye });
    }

    // ── 2) Fiyatlar ─────────────────────────────────────────────────────────
    // Sembol başına TEK çekim: 500 kullanıcı aynı gram altın alarmını
    // kurmuşsa da tek istek gider.
    const semboller = new Set([...alerts, ...donecekler].map((a) => a.symbol));
    const fiyatlar = await fetchLivePrices(semboller, admin);
    if (fiyatlar.size === 0) {
      // KANARYA: alarm var ama TEK sembol bile fiyatlanamadı. 2026-09-15'te
      // truncgil'in anahtar değişimi böyle görünmüştü ve HTTP 200 ile iki gün
      // sessiz kaldı. `sent: 0` meşru bir sonuç olduğundan ("piyasa kapalı")
      // izleme tarafında ayırt edilemiyordu; şimdi db_logs'a is_error satırı
      // düşer ve admin'e (12 saatte en çok bir kez) push gider.
      const kanarya = await fiyatKaynagiKanaryasi(admin, {
        kaynak: 'check-price-alerts',
        alarmSayisi: alerts.length + donecekler.length,
        semboller: [...semboller],
        fcm: dryRun
          ? null
          : { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson, channelId: CHANNEL_ID },
      });
      return jsonResponse({
        ok: true,
        reason: 'Fiyat alinamadi.',
        sent: 0,
        kanarya,
        yuzde,
        seviye,
      });
    }

    // KISMİ KANARYA (2026-09-20): sembollerin yarısından azı fiyatlandıysa
    // da öter. 2026-09-19'da fon alarmları (TEFAS) 9 sembolün 6'sında
    // sessizce fiyatlanmıyordu; altın/döviz fiyatlandığı için "boş döndü"
    // kanaryası susuyordu. Yalnızca EKSİK semboller listelenir; sessizlik
    // penceresi tam arızayla ortak (aynı kaynak, aynı alarm).
    let kanaryaKismi: KanaryaSonucu | undefined;
    if (kanaryaKismiMi(fiyatlar.size, semboller.size)) {
      kanaryaKismi = await fiyatKaynagiKanaryasi(admin, {
        kaynak: 'check-price-alerts',
        alarmSayisi: alerts.length + donecekler.length,
        semboller: [...semboller].filter((s) => !fiyatlar.has(s)),
        fiyatlanan: fiyatlar.size,
        fcm: dryRun
          ? null
          : { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson, channelId: CHANNEL_ID },
      });
    }

    // ── 2b) Nöbete dönüş (0171) ─────────────────────────────────────────────
    // Push yok, yalnız damga temizlenir. Kuru koşuda yazılmaz, sayılır.
    let nobeteDonen = 0;
    for (const a of donecekler) {
      const p = fiyatlar.get(a.symbol);
      if (p === undefined || !a.triggered_at) continue;
      if (tekrarKarari(a, p).tur !== 'nobete_don') continue;
      if (dryRun || await nobeteDondur(admin, a.id, a.triggered_at)) nobeteDonen += 1;
    }

    // Tekrarlı alarmın kararı (0171); tek atış alarm bu haritaya girmez.
    const tekrarKararlari = new Map<string, Extract<TekrarKarari, { tur: 'cal' }>>();
    const tetiklenen = alerts.filter((a) => {
      const p = fiyatlar.get(a.symbol);
      // Fiyatı alınamayan sembol DEĞERLENDİRİLMEZ: yanlış tetiklemektense
      // bir tur beklemek doğru.
      if (p === undefined) return false;
      if (a.tekrar === true) {
        const karar = tekrarKarari(a, p);
        if (karar.tur !== 'cal') return false;
        tekrarKararlari.set(a.id, karar);
        return true;
      }
      return isTriggered(p, Number(a.target_price), a.direction);
    });
    if (tetiklenen.length === 0) {
      return jsonResponse({
        ok: true,
        checked: alerts.length,
        priced: fiyatlar.size,
      kanarya: kanaryaKismi,
        sent: 0,
        nobete_donen: nobeteDonen,
        yuzde,
        seviye,
      });
    }

    // ── 3) Token'lar ────────────────────────────────────────────────────────
    const userIds = [...new Set(tetiklenen.map((a) => a.user_id))];
    const { data: tokenRows } = await tokenSatirlariniOku((s) =>
      admin.from('user_push_tokens').select(s).in('user_id', userIds)
    );
    // 0137: cihazın pasif hesaplarının satırları da (başlıkta hesap adı).
    const tokens = collapseTokens([
      ...(tokenRows ?? []),
      ...await ekHesapSatirlari(admin, userIds),
    ]);

    const tokensByUser = new Map<string, TokenRow[]>();
    for (const t of tokens) {
      const liste = tokensByUser.get(t.user_id);
      if (liste) {
        liste.push(t);
      } else {
        tokensByUser.set(t.user_id, [t]);
      }
    }

    const accessToken = dryRun
      ? ''
      : await createAccessToken(
        JSON.parse(fcmServiceAccountJson) as ServiceAccount,
      );

    let sent = 0;
    let skippedQuietHours = 0;
    const failures: string[] = [];

    // Sessiz saatler (0057): alarm ATLANIR ama damgalanmaz — pencere bitince
    // koşul sürüyorsa bir sonraki turda gider. Kuru koşuda da uygulanır ki
    // rapor gerçek davranışı göstersin.
    const sessiz = await sessizKullanicilar(admin, userIds);

    for (const alarm of tetiklenen) {
      if (sessiz.has(alarm.user_id)) { skippedQuietHours += 1; continue; }
      const fiyat = fiyatlar.get(alarm.symbol)!;
      const simge = kotasyonSimgesi(alarm.symbol);
      const tekrarKarar = tekrarKararlari.get(alarm.id);
      const mesaj = buildAlertMessage(
        alarm.label,
        fiyat,
        Number(alarm.target_price),
        alarm.direction,
        simge,
        tekrarKarar !== undefined,
        tekrarKarar !== undefined && tekrarKarar.sayi >= GUNLUK_TAVAN,
      );

      if (dryRun) {
        sent += 1;
        continue;
      }

      // Alarm ÖNCE söndürülür, sonra bildirim gider.
      //
      // Sıra kasıtlı: push başarısız olup damga atılmazsa alarm bir sonraki
      // turda yeniden denenir (istenen davranış). Ters sırada, push gidip
      // damga yazılamazsa kullanıcı her turda (5 dakikada bir) aynı bildirimi alırdı —
      // geri alınamaz olan bu.
      // Yarış koruması: iki tur çakışırsa yalnız damgayı ATAN gönderir.
      // Tekrarlı alarm (0171) aynı sırayla damgalanır ama söndürülmez.
      const damga = tekrarKarar
        ? await tekrarliCalisiYaz(admin, alarm.id, tekrarKarar)
        : await alarmiSondur(admin, alarm.id);
      if (damga === 'hata') {
        failures.push('damga: yazilamadi');
        continue;
      }
      if (damga === 'zaten') continue;

      // Uygulama içi bildirim listesi kaydı (0065).
      //
      // Token döngüsünden ÖNCE ve push'un sonucundan BAĞIMSIZ yazılır:
      // kullanıcı push'u kaçırsa da (bildirim izni kapalı, token bayat,
      // cihaz kapalı) alarmın çalıştığını uygulamada görebilmeli. Push'a
      // bağlasaydık "alarm kurmuştum, çalıştı mı?" sorusu yine cevapsız
      // kalırdı — bu tablonun var olma sebebi tam olarak o.
      //
      // Hata YUTULUR: liste kaydı yazılamadı diye bildirimi göndermemek
      // daha kötü olurdu. Alarm zaten damgalandı, geri dönüşü yok.
      const { error: kayitHatasi } = await admin
        .from('price_alert_notifications')
        .insert({
          user_id: alarm.user_id,
          alert_id: alarm.id,
          symbol: alarm.symbol,
          label: alarm.label,
          target_price: alarm.target_price,
          triggered_price: fiyat,
          direction: alarm.direction,
        });
      if (kayitHatasi) {
        // DB mesajı yalnızca günlüğe; yanıta sabit kod (2026-09-23 denetimi L2).
        console.error('[check-price-alerts] liste kaydi yazilamadi:', kayitHatasi.message);
        failures.push('liste: yazilamadi');
      }

      const kartVerisi = buildAlertCard(
        alarm.label,
        fiyat,
        Number(alarm.target_price),
        alarm.direction,
        simge,
      );
      for (const t of tokensByUser.get(alarm.user_id) ?? []) {
        const r = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token: t.token,
          hesap: ekHesap(t),
          title: mesaj.title,
          body: mesaj.body,
          channelId: CHANNEL_ID,
          // Acil uyarı (`_shared/fcm.ts` priority belgesi): `normal`ken iOS
          // APNs 5 ile güç tasarrufu için erteleyebiliyor, Android Doze'da
          // geciktiriyordu; 5 dakikalık alarm hızı (#245) bildirim geç
          // gelince boşa gidiyordu. Müşteri raporu 2026-10-26 21:15 #1.
          priority: 'high',
          data: { type: 'price_alert', alert_id: alarm.id, symbol: alarm.symbol },
          gorselUrl: await kartGorseli(kart, t, kartVerisi),
        });
        if (r.ok) {
          sent += 1;
        } else {
          // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
          console.error('[check-price-alerts] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
          failures.push(`fcm: ${r.hataKodu}`);
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', t.token);
          }
        }
      }
    }

    return jsonResponse({
      ok: true,
      checked: alerts.length,
      priced: fiyatlar.size,
      kanarya: kanaryaKismi,
      triggered: tetiklenen.length,
      turler: filtre ? [...filtre] : 'hepsi',
      sent,
      skipped_quiet_hours: skippedQuietHours,
      nobete_donen: nobeteDonen,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
      yuzde,
      seviye,
    });
  } catch (error) {
    // Ayrıntı yalnızca günlüğe: yanıtta `error.message` dönmek tablo/sütun
    // ve secret adlarını sızdırır (CLAUDE.md sunucu kuralı, 2026-09-23 denetimi L2).
    console.error('[check-price-alerts] hata:', error);
    return jsonResponse({ error: 'Alarm denetimi basarisiz.' }, 500);
  }
});
