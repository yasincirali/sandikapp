// Daily Brief Edge Function — SABAH BRİFİNGİ
//
// pg_cron ile hafta içi TR 09:45'te tetiklenir. Her kullanıcıya, KENDİ
// portföyüne dair tek cümlelik bir bildirim gönderir.
//
// ── Neden bu özellik var ────────────────────────────────────────────────────
// sandık bir TAKİP uygulaması: kullanıcının içeride yapacak bir işi yok,
// yalnızca bakmak var. Bu yüzden "uygulamayı açmayı unutma" tipi hatırlatma
// burada çalışmaz — geri getiren şey uygulamanın kullanıcıya SÖYLEYECEK bir
// sözünün olmasıdır. Brifing o sözü taşır.
//
// ── v1 KAPSAMI: yalnızca hisse ──────────────────────────────────────────────
// İlk sürüm "portföyün %X arttı" DEMİYOR, "portföyündeki en çok hareket eden
// hisse şu" diyor. Sebebi doğruluk:
//
//   · Portföy yüzdesi için her varlığı TRY'ye çevirmek gerekir; canlı kur
//     sunucuda yok (`assets.purchase_fx_rate` alış anının kuru).
//   · Altın serisi `GC=F` (ons/USD) olarak çözülüyor (bkz. resolveSymbol).
//     Onun günlük yüzdesi, TRY gram altının yüzdesi DEĞİLDİR — arada USD/TRY
//     hareketi var. Aynı sorun döviz ve emtiada da geçerli.
//   · Yanlış bir "portföyün %1,8 arttı" bildirimi, hiç bildirim
//     göndermemekten kötüdür: kullanıcı sayıyı uygulamadakiyle karşılaştırır
//     ve güvenini kaybeder.
//
// BIST hissesi bu tuzakların dışında: Yahoo serisi de holding de TRY.
// Kapsamı genişletmek, önce sunucu tarafına kur modeli koymayı gerektirir.
//
// ── v2 (2026-10-30, Ar-Ge 30 Eki 08:45 #1, yasin "yap"): altın, döviz, fon ──
// Yukarıdaki engel kalktı: sunucu artık TL fiyatı KENDİ tutuyor ve
// uygulamanın gösterdiği sayıyla aynı ölçekte:
//   · altın ayarları + TL döviz → `yurt_ici_kotasyon` (0101; 5 dk, TL,
//     truncgil `Change` = uygulamadaki günlük yüzde)
//   · TEFAS fonu → `tefas_nav_gozlem` (0063; portföydeki fonların NAV'ı)
// Yüzde alarmı (0169) ve widget (`widget-fiyat`) aynı iki tablodan aynı
// yardımcılarla (`_shared/widget_fiyat.ts`) okuyor; brifing yeni bir sembol
// merdiveni KURMAZ (fiyat_kaynagi sözleşmesi madde 1). Kapsam dışı kalan:
//   · GC=F/Yahoo üzerinden altın SERİSİ kullanılmaz — o seri gösterge içindir,
//     brifingin söylediği "bugün %X" uygulamadaki sayı olmalı (madde 2).
//   · kripto: 7/24 ve oynak; brifingin "en çok hareket eden"i neredeyse her
//     gün kripto olurdu ve hisse/altın/fon sahibinin günlük sözü kaybolurdu.
//     Kriptonun kendi yüzde alarmı var.
//   · emtia, eurobond, BES, mevduat: sunucuda TL günlük yüzdeleri yok
//     (BES fonu gözleniyor ama "BES'in bugün %X" bireysel katkı payıyla
//     karışır; kapsam fikirde bilerek dışarıda).
// Yüzde bilinmiyorsa, kotasyon bayatsa ya da fonun NAV'ı son işlem gününe
// ait değilse o varlık aday OLMAZ (uydurma yok, madde 3); dünkü NAV
// değişimini bugün ikinci kez anlatmamak için fonda tarih kapısı var
// ([fonNavGuncelMi]).
//
// ── ORTAK HAREKETİ: neden ayrı bir push değil ───────────────────────────────
// Ortağın portföyüne ekleme yapması, "en çok hareket eden hissen"den daha
// güçlü bir kanca: sosyal bağ bireysel mekaniklerin hepsinden güçlü.
// Ama AYRI bir bildirim olarak gönderilmiyor, çünkü bildirim bütçesi günde
// tek proaktif push'a izin veriyor (bkz. RETENTION_STRATEJISI.md §7) ve
// ortak günde beş lot eklerse beş push demek olurdu. Brifing zaten günde
// bir kez konuşuyor; ortak hareketi varsa SÖZÜ O ALIR.
//
// Mahremiyet: yeni bilgi açılmıyor — ortağın lot'ları zaten karşı tarafta
// görünüyor. Yine de alıcının kapatma hakkı var: `profiles.partner_activity_push`.
//
// ── Neden "son kapanış" ─────────────────────────────────────────────────────
// 09:45'te BIST açılmamıştır ve `price_history_cache` günlük kapanış tutar;
// serinin son noktası bir önceki işlem günüdür. "Dün" demek pazartesi günü
// yanlış olurdu (son kapanış cuma). "Son kapanışta" her gün doğrudur.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
  shortLabel,
} from '../_shared/fcm.ts';
import {
  appNotificationRow,
  recordAppNotification,
} from '../_shared/app_notifications.ts';
import { loadPriceHistories, resolveSymbol } from '../_shared/price_history.ts';
import { acikPozisyonLotlari } from '../_shared/positions.ts';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  tokenSatirlariniOku,
} from '../_shared/push_tokens.ts';
import { degisimKarti, kartGorseli, KartAyari } from '../_shared/bildirim_karti.ts';

// Testler bu modülden okuyor; kaynağı `_shared/push_tokens.ts`.
export { collapseTokens };
import { sessizKullanicilar } from '../_shared/quiet_hours.ts';
import { bistTatilMi } from '../_shared/piyasa_takvimi.ts';
import {
  fonKodu,
  fonWidgetFiyati,
  widgetSembolTuru,
  yurtIciWidgetFiyati,
} from '../_shared/widget_fiyat.ts';
import { trGun } from '../_shared/tefas_nav.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

/// Android bildirim kanalı — istemcide aynı kimlikle kayıtlı olmalı
/// (`NotificationService._ensureChannels`). Sinyalden AYRI kanal olması
/// kasıtlı: kullanıcı brifingi kapatıp sinyalleri açık tutabilmeli. Tek
/// kanal, tek "kapat" demek olurdu.
const CHANNEL_ID = 'brief_channel';

/// Bu eşiğin altındaki hareket bildirime değmez.
///
/// Günlük bir push'un bütçesi var (haftalık tavan 5 bildirim, sinyaller
/// dahil). "%0,3 yükseldi" o bütçeyi hiçbir şey söylemeden harcar ve
/// kullanıcıyı bildirimleri kapatmaya iter.
const DEFAULT_MIN_MOVE_PCT = 1.5;

/// Altın/döviz kotasyonu bu yaştan eskiyse brifing onu "bugün" diye
/// anlatmaz. `yurt-ici-kotasyon` 5 dakikada bir yazar; yüzde alarmının
/// eşiğiyle aynı (`YUZDE_YURT_ICI_BAYATLIK_MS`, 15 dk).
export const BRIEF_YURT_ICI_BAYATLIK_MS = 15 * 60_000;

/// Brifingin anlatabildiği varlık türü (v2, dosya başı).
export type BriefTuru = 'hisse' | 'yurt_ici' | 'fon';

/// Lotun fiyat kaynağındaki sembolü — istemcideki `alarmSembolu` ile aynı
/// kural: altın lotunun ayarı `sub_category`'de (`ALTIN_GRAM`), `ticker`'da
/// değil. Push'taki `ticker` de bu değeri taşır ki istemci varlığı aynı
/// kuralla bulsun (`openPriceAlertAsset`).
export function briefSembolu(ticker: string | null, subCategory: string | null): string {
  const sub = (subCategory ?? '').trim();
  if (sub.startsWith('ALTIN_')) return sub;
  return (ticker ?? '').trim();
}

/// Lot satırı brifinge girer mi; girerse hangi kaynaktan. [sembol]
/// [briefSembolu]'nden gelir.
///
/// Kapsam `widgetSembolTuru`'ndan TÜRER (yüzde alarmı ve widget'la aynı
/// beyaz liste): altın ayarları ve üç TL döviz `yurt_ici`, `TEFAS:XXX` fon.
/// Tür sütunu da bakılır: BES lotu da `TEFAS:` taşır ama fon değildir.
export function briefTuru(type: string, sembol: string): BriefTuru | null {
  const t = (sembol ?? '').trim();
  if (type === 'hisse') return 'hisse';
  if ((type === 'altin' || type === 'doviz') && widgetSembolTuru(t) === 'yurt_ici') {
    return 'yurt_ici';
  }
  if (type === 'fon' && widgetSembolTuru(t) === 'fon') return 'fon';
  return null;
}

/// [simdi]'den önceki son BIST işlem günü (TR takvimi, `YYYY-MM-DD`).
/// Hafta sonu ve resmî tatiller atlanır (`bistTatilMi`).
export function oncekiIsGunu(simdi: Date): string {
  const gun = 24 * 60 * 60 * 1000;
  let d = new Date(simdi.getTime() - gun);
  for (let i = 0; i < 14; i++) {
    const hafta = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Europe/Istanbul',
      weekday: 'short',
    }).format(d);
    if (hafta !== 'Sat' && hafta !== 'Sun' && !bistTatilMi(d)) break;
    d = new Date(d.getTime() - gun);
  }
  return trGun(d);
}

/// Fonun son NAV'ı brifinge girecek kadar yeni mi: bugünün ya da bir önceki
/// işlem gününün fiyatı. Sabah 09:45'te bugünün NAV'ı henüz yok, dünkü
/// (pazartesi cumanın) anlatılır; NAV bir gün gelmediyse eski değişim
/// ertesi sabah YİNELENMEZ.
export function fonNavGuncelMi(navTarihi: string, simdi: Date): boolean {
  const t = String(navTarihi ?? '').slice(0, 10);
  return t === trGun(simdi) || t === oncekiIsGunu(simdi);
}

type AssetRow = {
  id: string;
  user_id: string;
  name: string;
  ticker: string;
  type: string;
  is_manual_price: boolean | null;
  kind: string | null;
  // Netleme alanları — bkz. `_shared/positions.ts`.
  quantity: number | null;
  sub_category: string | null;
  currency: string | null;
  // Mezar taşı (`delete_log`) okuması için — silinen pozisyon susturulur.
  added_date: string | null;
  ref_asset_id: string | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Serinin son iki kapanışından yüzde değişim. Veri yetersizse null.
export function lastChangePct(closes: number[]): number | null {
  if (closes.length < 2) return null;
  const son = closes[closes.length - 1];
  const onceki = closes[closes.length - 2];
  if (!isFinite(son) || !isFinite(onceki) || onceki === 0) return null;
  return ((son - onceki) / onceki) * 100;
}

/// Bildirim metni.
///
/// Yasal çerçeve `analyze-signals` ile aynı: DURUM bildirilir, EYLEM
/// önerilmez ("yükseldi" ✓ / "al" ✗) ve SPK'nın beklediği ibare eklenir.
/// Yön oku başlıkta en solda — kilit ekranında kullanıcı önce sol kenarı
/// tarar; ▲▼ her yazı tipinde aynı görünür ve VoiceOver düzgün okur.
///
/// [otherCount] = eşiği (`minMovePct`) AYRICA geçen DİĞER hisse sayısı
/// (tekil sembol). Eskiden "portföydeki diğer lot sayısı"ydı ve metin
/// "Portföyündeki diğer 2 hisse daha var." diyordu: ne söylediği belli
/// değildi (emülatör testi #16, 2026-09-29) ve aynı hissenin iki lot'u
/// "diğer hisse" sayılıyordu. Şimdi söylenen şey doğrulanabilir: o hisseler
/// de bugün eşik üstü hareket etti.
///
/// v2 (2026-10-30): [tur] zaman ifadesini seçer, çünkü üç kaynağın
/// yüzdesi üç ayrı ana aittir — hisse "son kapanışta" (Yahoo günlük
/// kapanış), altın/döviz "bugün" (truncgil günlük değişimi), fon "son
/// fiyatında" (günde bir açıklanan NAV). [isim] gövdedeki adı seçer:
/// yalnız hisse tutan kişiye metin birebir eskisi ("hisse"), karışık
/// portföyde "varlık" — altını "hisse" diye anlatmamak için.
export function buildBriefMessage(
  label: string,
  changePct: number,
  otherCount: number,
  tur: BriefTuru = 'hisse',
  isim: 'hisse' | 'varlık' = 'hisse',
): { title: string; body: string } {
  const yukari = changePct >= 0;
  const mutlak = Math.abs(changePct).toFixed(1).replace('.', ',');
  const kalan = otherCount > 0
    ? `Portföyündeki ${otherCount} ${isim} daha hareketli. `
    : '';
  const zaman = tur === 'yurt_ici'
    ? 'bugün'
    : tur === 'fon'
    ? 'son fiyatında'
    : 'son kapanışta';
  return {
    title: `${yukari ? '▲' : '▼'} ${label} ${zaman} %${mutlak} ` +
      `${yukari ? 'yükseldi' : 'düştü'}`,
    body: `Portföyünde en çok hareket eden ${isim}. ${kalan}` +
      'Yatırım tavsiyesi değildir.',
  };
}

/// Bildirim kartının alt yazısı; başlıktaki zaman ifadesiyle aynı an.
export function briefKartAltYazisi(tur: BriefTuru): string {
  return tur === 'yurt_ici'
    ? 'Bugün · en hareketli'
    : tur === 'fon'
    ? 'Son fon fiyatı · en hareketli'
    : 'Son kapanış · en hareketli';
}

/// [tur] yoksa hisse (v1 satırları ve testler).
export type BriefAdayi = {
  label: string;
  sembol: string;
  changePct: number;
  tur?: BriefTuru;
};

/// Kullanıcının hisse satırlarından brifingin konusu: en çok hareket eden
/// hisse ve eşiği ayrıca geçen DİĞER hisse sayısı.
///
/// Satırlar LOT düzeyindedir (aynı hissenin birden çok alımı ayrı satır);
/// sayım sembol başına TEKİLLEŞTİRİLİR — iki lot iki "hisse" değildir.
/// Boş girdi → null (uydurma konu yok).
export function briefAdayiSec(
  satirlar: BriefAdayi[],
  minMovePct: number,
): { en: BriefAdayi; digerHareketli: number; yalnizHisse: boolean } | null {
  const tekil = new Map<string, BriefAdayi>();
  for (const s of satirlar) {
    if (!tekil.has(s.sembol)) tekil.set(s.sembol, s);
  }
  let en: BriefAdayi | null = null;
  for (const a of tekil.values()) {
    if (!en || Math.abs(a.changePct) > Math.abs(en.changePct)) en = a;
  }
  if (!en) return null;
  let digerHareketli = 0;
  for (const a of tekil.values()) {
    if (a.sembol !== en.sembol && Math.abs(a.changePct) >= minMovePct) {
      digerHareketli += 1;
    }
  }
  const yalnizHisse = [...tekil.values()].every((a) => (a.tur ?? 'hisse') === 'hisse');
  return { en, digerHareketli, yalnizHisse };
}

/// Bildirim `data`'sı — push ve çan kaydı AYNI veriyi taşır ki iki dokunuş
/// yolu (push → `NotificationService.handleRemoteMessageData`, çan →
/// `home_screen._genelBildirimeGit`) aynı hedefe gidebilsin.
///
/// Hisse mesajı ('mover') `ticker` taşır: istemci o varlığın ekranını
/// GÜNLÜK'te açar (#16: push ana ekranda, çan Özet'te kalıyordu — anlatılan
/// hisse ikisinde de yoktu). Ortak mesajı ticker taşımaz (NE eklendiği
/// söylenmez, bkz. [buildPartnerMessage]); istemci Özet'i açar.
export function briefVerisi(
  bugun: string,
  variant: 'mover' | 'partner',
  ticker?: string,
): Record<string, string> {
  const d: Record<string, string> = {
    type: 'daily_brief',
    sent_on: bugun,
    variant,
  };
  if (variant === 'mover' && ticker && ticker.trim().length > 0) {
    d.ticker = ticker.trim();
  }
  return d;
}

/// Ortak hareketi mesajı.
///
/// Ne EKLENDİĞİ söylenmez, yalnızca ekleme YAPILDIĞI. Varlık adı bildirimde
/// geçseydi kilit ekranında omzunun üstünden bakan biri ortağın ne aldığını
/// görürdü; uygulama içinde zaten görünen bir bilgi, kilit ekranında
/// görünmek zorunda değil.
/// Sahibin ortağa paylaşım seçimi (0135 `ortak_paylasimlari`). Satır yoksa
/// `undefined`: ortak her şeyi görür.
export interface OrtakPaylasimi {
  tumu: boolean;
  ana: boolean;
  portfoyIdler: string[];
}

/// `public.ortak_portfoyu_gorur` ile AYNI kural (RLS eşi): service-role
/// sorgusu RLS'i atladığı için süzgeç burada tekrar uygulanır.
export function ortakLotuGorur(
  p: OrtakPaylasimi | undefined,
  portfoyId: string | null,
): boolean {
  if (!p || p.tumu) return true;
  return portfoyId == null ? p.ana : p.portfoyIdler.includes(portfoyId);
}

export function buildPartnerMessage(
  partnerName: string,
  eklemeSayisi: number,
): { title: string; body: string } {
  const ad = partnerName.trim().length > 0 ? partnerName.trim() : 'Ortağın';
  return {
    title: eklemeSayisi === 1
      ? `${ad} portföyüne ekleme yaptı`
      : `${ad} portföyüne ${eklemeSayisi} ekleme yaptı`,
    body: 'Ortak portföyünüzdeki değişimi sandık\'ta görebilirsin.',
  };
}

/// Cihaz başına TEK token — aynı telefona kopya push gitmesin.
///
/// `analyze-signals` ile aynı gerekçe: FCM token'ı rotasyona girer (yeniden
/// kurulum, veri temizleme, güncelleme) ve eski satırlar tabloda kalır.
/// `device_id` yazmayan eski istemciler için `platform` ile gruplanır.

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('DAILY_BRIEF_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'DAILY_BRIEF_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Env denetimi kapıdan SONRA (2026-09-23 denetimi L2): yetkisiz çağıran
    // eksik yapılandırmayı ya da secret adlarını öğrenemesin.
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından '
        + 'sağlanmadı. Bunlar otomatik enjekte edilir.',
      );
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error(
        'FCM secret\'ları eksik: FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT_JSON.',
      );
    }

    let dryRun = false;
    let minMovePct = DEFAULT_MIN_MOVE_PCT;
    // Slot (0068): sabah koşusu 'morning' kullanıcılarına, akşam koşusu
    // (TR 18:30, `{"slot":"evening"}`) 'evening' kullanıcılarına. Her
    // kullanıcı tek slotta → günde tek brifing.
    let slot: 'morning' | 'evening' = 'morning';
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.min_move_pct === 'number') minMovePct = body.min_move_pct;
      if (body?.slot === 'evening') slot = 'evening';
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // ── 1) Push token'ı olan kullanıcılar ───────────────────────────────────
    const { data: tokenRows, error: tokenError } = await tokenSatirlariniOku((s) =>
      admin.from('user_push_tokens').select(s)
    );
    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }
    // 0137: cihazın pasif hesaplarının satırları da (başlıkta hesap adı).
    const tokens = collapseTokens([...(tokenRows ?? []), ...await ekHesapSatirlari(admin)]);
    // Bildirim kartı (0092, yalnız yeni sürüm cihazlar) — bkz. bildirim_karti.ts.
    const kart: KartAyari = { supabaseUrl, anahtar: serviceRoleKey };
    if (tokens.length === 0) {
      return jsonResponse({ ok: true, reason: 'Kayitli push token yok.', sent: 0 });
    }

    const userIds = [...new Set(tokens.map((t) => t.user_id))];

    // ── 2) Bugün brifing almış kullanıcıları ele ────────────────────────────
    // Cron günde bir kez koşar ama yeniden deneme / elle tetikleme olabilir.
    // Aynı güne ikinci bildirim, bütçeyi harcamanın ötesinde güven kaybettirir.
    const bugun = new Date().toISOString().slice(0, 10);
    const { data: gonderilmis } = await admin
      .from('daily_brief_log')
      .select('user_id')
      .eq('sent_on', bugun)
      .in('user_id', userIds);
    const zatenGonderildi = new Set(
      (gonderilmis ?? []).map((r: { user_id: string }) => r.user_id),
    );

    // Slot filtresi (0068): kullanıcının seçmediği slotta gönderim yok.
    // Sütun eski kayıtlarda null olabilir → 'morning'. Tercih okunamazsa
    // herkes 'morning' sayılır: akşam koşusu o durumda hiç göndermez
    // (çift brifing riskinden sessiz kalmak iyidir).
    try {
      const { data: slotRows } = await admin
        .from('profiles')
        .select('id, brief_slot')
        .in('id', userIds);
      const slotu = new Map<string, string>();
      for (const r of (slotRows ?? []) as Array<Record<string, unknown>>) {
        slotu.set(String(r.id), String(r.brief_slot ?? 'morning'));
      }
      for (const uid of userIds) {
        if ((slotu.get(uid) ?? 'morning') !== slot) zatenGonderildi.add(uid);
      }
    } catch (_) {
      if (slot === 'evening') {
        return jsonResponse({ ok: true, reason: 'Slot tercihi okunamadi.', sent: 0 });
      }
    }
    // Akşam slotu Pazartesi: haftalık özet sabah gitti → ikinci push yok.
    if (slot === 'evening') {
      const { data: haftalik } = await admin
        .from('weekly_summary_log')
        .select('user_id')
        .eq('sent_on', bugun)
        .in('user_id', userIds);
      for (const r of (haftalik ?? []) as Array<{ user_id: string }>) {
        zatenGonderildi.add(r.user_id);
      }
    }

    // ── 3) Varlıklar ────────────────────────────────────────────────────────
    // BIST hissesi, altın, TL döviz ve TEFAS fonu (bkz. dosya başındaki
    // kapsam notu, v2); aktif alım lot'ları ve fiyatı otomatik çekilenler.
    //
    // `deleted_at is null` ŞART: silme fiziksel değil, damgalı
    // (bkz. 0027_soft_delete_lots). Filtre olmadan kullanıcı sildiği hisse
    // için brifing alırdı.
    //
    // SATIŞ satırları da çekilir: `kind='buy'` tek başına "hâlâ sahibim"
    // demek DEĞİLDİR. Tamamen satılmış hisse için brifing gönderilmesi
    // sinyal push'undaki hatanın aynısıydı (bkz. `_shared/positions.ts`).
    const { data: assetRows, error: assetError } = await admin
      .from('assets')
      .select(
        'id, user_id, name, ticker, type, is_manual_price, kind, quantity, sub_category, currency, added_date, ref_asset_id',
      )
      .in('user_id', userIds)
      .in('type', ['hisse', 'altin', 'doviz', 'fon'])
      .is('deleted_at', null);
    if (assetError) {
      throw new Error(`Varliklar alinamadi: ${assetError.message}`);
    }

    const assets = acikPozisyonLotlari((assetRows ?? []) as AssetRow[])
      .filter((a) => a.is_manual_price !== true)
      .filter((a) => briefTuru(a.type, briefSembolu(a.ticker, a.sub_category)) !== null);
    if (assets.length === 0) {
      return jsonResponse({ ok: true, reason: 'Brifing icin varlik yok.', sent: 0 });
    }

    // ── 4) Fiyatlar ─────────────────────────────────────────────────────────
    // Hisse: günlük kapanış serisi (semboller arası paylaşımlı cache).
    const semboller = new Set<string>();
    const yurtIciSemboller = new Set<string>();
    const fonKodlariSet = new Set<string>();
    for (const a of assets) {
      const t = briefSembolu(a.ticker, a.sub_category);
      const tur = briefTuru(a.type, t);
      if (tur === 'hisse') {
        const s = resolveSymbol(t, a.type);
        if (s) semboller.add(s);
      } else if (tur === 'yurt_ici') {
        yurtIciSemboller.add(t);
      } else if (tur === 'fon') {
        const kod = fonKodu(t);
        if (kod) fonKodlariSet.add(kod);
      }
    }
    const histories = semboller.size > 0
      ? await loadPriceHistories(admin, semboller)
      : new Map<string, number[]>();

    // Altın/döviz ve fon: sunucunun zaten tuttuğu iki tablo (v2). Okuma
    // hatası brifingi DÜŞÜRMEZ: o türler bu tur aday olmaz, hisse gider.
    const simdi = new Date();
    const yurtIciYuzde = new Map<string, number>();
    if (yurtIciSemboller.size > 0) {
      const { data, error } = await admin
        .from('yurt_ici_kotasyon')
        .select('sembol, ts, fiyat, degisim_pct')
        .in('sembol', [...yurtIciSemboller])
        .gte('ts', new Date(simdi.getTime() - BRIEF_YURT_ICI_BAYATLIK_MS).toISOString())
        .order('ts', { ascending: false });
      if (error) {
        console.error('[daily-brief] yurt ici kotasyon okunamadi:', error.code);
      }
      for (const r of (data ?? []) as Array<Record<string, unknown>>) {
        const s = String(r.sembol);
        if (yurtIciYuzde.has(s)) continue; // en yeni kova önce geldi
        const f = yurtIciWidgetFiyati(
          { ts: r.ts, fiyat: r.fiyat, degisim_pct: r.degisim_pct },
          simdi.getTime(),
        );
        if (f?.degisim !== undefined && simdi.getTime() - f.zaman <= BRIEF_YURT_ICI_BAYATLIK_MS) {
          yurtIciYuzde.set(s, f.degisim);
        }
      }
    }
    const fonYuzde = new Map<string, number>();
    if (fonKodlariSet.size > 0) {
      const { data, error } = await admin
        .from('tefas_nav_gozlem')
        .select('fon_kodu, nav_tarihi, ilk_gorulme, nav')
        .in('fon_kodu', [...fonKodlariSet])
        .gte('nav_tarihi', trGun(new Date(simdi.getTime() - 10 * 24 * 60 * 60 * 1000)))
        .order('nav_tarihi', { ascending: false });
      if (error) {
        console.error('[daily-brief] fon gozlemi okunamadi:', error.code);
      }
      const kodSatirlari = new Map<string, Array<Record<string, unknown>>>();
      for (const r of (data ?? []) as Array<Record<string, unknown>>) {
        const kod = String(r.fon_kodu);
        const liste = kodSatirlari.get(kod);
        if (liste) liste.push(r); else kodSatirlari.set(kod, [r]);
      }
      for (const [kod, satirlar] of kodSatirlari) {
        const son = satirlar[0];
        if (!son || !fonNavGuncelMi(String(son.nav_tarihi), simdi)) continue;
        const f = fonWidgetFiyati(
          satirlar.slice(0, 2).map((r) => ({
            nav_tarihi: r.nav_tarihi,
            ilk_gorulme: r.ilk_gorulme,
            nav: r.nav,
          })),
          simdi.getTime(),
        );
        if (f?.degisim !== undefined) fonYuzde.set(kod, f.degisim);
      }
    }

    // ── 5) Kullanıcı başına en çok hareket eden varlık ──────────────────────
    const kullaniciSatirlari = new Map<string, BriefAdayi[]>();

    for (const a of assets) {
      if (zatenGonderildi.has(a.user_id)) continue;
      const t = briefSembolu(a.ticker, a.sub_category);
      const tur = briefTuru(a.type, t)!;
      let sembol: string | null = null;
      let degisim: number | null = null;
      // Etiket: hisse/fon kodu ("ASELS", "AFT"); altın/dövizde ad — kod
      // (`ALTIN_GRAM`) kimseye bir şey söylemez.
      let label = shortLabel(a.name, t);
      if (tur === 'hisse') {
        sembol = resolveSymbol(t, a.type);
        const closes = sembol ? histories.get(sembol) : undefined;
        degisim = closes ? lastChangePct(closes) : null;
      } else if (tur === 'yurt_ici') {
        sembol = t;
        degisim = yurtIciYuzde.get(t) ?? null;
        label = (a.name ?? '').trim() || t;
      } else {
        const kod = fonKodu(t);
        sembol = t;
        degisim = kod ? fonYuzde.get(kod) ?? null : null;
      }
      if (!sembol || degisim === null || !isFinite(degisim)) continue;

      const satir: BriefAdayi = { label, sembol, changePct: degisim, tur };
      const liste = kullaniciSatirlari.get(a.user_id);
      if (liste) liste.push(satir); else kullaniciSatirlari.set(a.user_id, [satir]);
    }
    const kullaniciAdaylari = new Map<
      string,
      { en: BriefAdayi; digerHareketli: number; yalnizHisse: boolean }
    >();
    for (const [uid, satirlar] of kullaniciSatirlari) {
      const secim = briefAdayiSec(satirlar, minMovePct);
      if (secim) kullaniciAdaylari.set(uid, secim);
    }

    // ── 5b) Ortak hareketi ──────────────────────────────────────────────────
    //
    // Ortak dün portföyüne ekleme yaptıysa brifingin SÖZÜNÜ o alır: sosyal
    // kanca, "en çok hareket eden hissen"den güçlü. Ayrı bir push değil —
    // bildirim bütçesi günde tek proaktif mesaja izin veriyor.
    const ortakHareketi = new Map<string, { ad: string; adet: number }>();
    try {
      const { data: profilRows } = await admin
        .from('profiles')
        .select('id, display_name, partner_activity_push')
        .in('id', userIds);
      const profiller = new Map<string, { ad: string; ister: boolean }>();
      for (const p of (profilRows ?? []) as Array<Record<string, unknown>>) {
        profiller.set(String(p.id), {
          ad: String(p.display_name ?? ''),
          // Sütun eski kayıtlarda null olabilir; varsayılan AÇIK.
          ister: p.partner_activity_push !== false,
        });
      }

      const { data: esRows } = await admin
        .from('partnerships')
        .select('user_id_1, user_id_2')
        .eq('active', true)
        .or(`user_id_1.in.(${userIds.join(',')}),user_id_2.in.(${userIds.join(',')})`);

      // alıcı → ortak listesi
      const ortaklar = new Map<string, string[]>();
      for (const r of (esRows ?? []) as Array<Record<string, unknown>>) {
        const a1 = String(r.user_id_1);
        const a2 = String(r.user_id_2);
        for (const [alici, ortak] of [[a1, a2], [a2, a1]]) {
          if (!userIds.includes(alici)) continue;
          const liste = ortaklar.get(alici);
          if (liste) liste.push(ortak); else ortaklar.set(alici, [ortak]);
        }
      }

      const tumOrtaklar = [...new Set([...ortaklar.values()].flat())];
      if (tumOrtaklar.length > 0) {
        // Son 24 saatte eklenen aktif alım lot'ları.
        const dun = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
        const { data: yeniLotlar } = await admin
          .from('assets')
          .select('user_id, portfoy_id')
          .in('user_id', tumOrtaklar)
          .eq('kind', 'buy')
          .is('deleted_at', null)
          .gte('added_date', dun);

        // Sahip, ortağa yalnız bazı portföylerini gösteriyorsa (0135) gizli
        // portföye eklenen lot SAYILMAZ: service-role RLS'i atlar, "ortağın
        // 3 varlık ekledi" gizli portföyün varlığını ele verirdi. Okunamazsa
        // (tablo yok) hiç kısıt yok sayılır — 0135 öncesi davranış.
        const { data: paylasimRows } = await admin
          .from('ortak_paylasimlari')
          .select('sahip_id, ortak_id, tumu, ana, portfoy_idler')
          .in('sahip_id', tumOrtaklar);
        const paylasimlar = new Map<string, OrtakPaylasimi>();
        for (const r of (paylasimRows ?? []) as Array<Record<string, unknown>>) {
          paylasimlar.set(`${r.sahip_id}|${r.ortak_id}`, {
            tumu: r.tumu !== false,
            ana: r.ana !== false,
            portfoyIdler: ((r.portfoy_idler ?? []) as unknown[]).map(String),
          });
        }
        const lotlar = (yeniLotlar ?? []) as Array<Record<string, unknown>>;

        for (const [alici, liste] of ortaklar) {
          if (profiller.get(alici)?.ister === false) continue;
          for (const ortak of liste) {
            const paylasim = paylasimlar.get(`${ortak}|${alici}`);
            const adet = lotlar.filter((r) =>
              String(r.user_id) === ortak &&
              ortakLotuGorur(
                paylasim,
                r.portfoy_id == null ? null : String(r.portfoy_id),
              )
            ).length;
            if (adet === 0) continue;
            const onceki = ortakHareketi.get(alici);
            // Birden çok ortak hareket ettiyse en ÇOK ekleyeni anlat —
            // hepsini saymak bildirimi rapora çevirirdi.
            if (!onceki || adet > onceki.adet) {
              ortakHareketi.set(alici, {
                ad: profiller.get(ortak)?.ad ?? '',
                adet,
              });
            }
          }
        }
      }
    } catch (_) {
      // Ortak hareketi ikincil bir zenginleştirme — sorgulanamazsa brifing
      // yine de hisse mesajıyla gider.
    }

    // ── 6) Gönderim ─────────────────────────────────────────────────────────
    const accessToken = dryRun
      ? ''
      : await createAccessToken(
        JSON.parse(fcmServiceAccountJson) as ServiceAccount,
      );

    let sent = 0;
    let skippedQuiet = 0;
    // Resmî tatilde fiyat mesajı gitmez (Ar-Ge 29 Eki #1): "son kapanış"
    // tatilden önceki günün kapanışıdır, aynı haber bir gün önce zaten
    // gitti. v2'de altın/döviz ve fon da aynı kapıdan geçer: tatilde fon
    // NAV'ı açıklanmaz, truncgil'in günlük değişimi önceki günü taşıyabilir
    // (yüzde alarmının hafta sonu gerekçesi). Ortak hareketi fiyata bağlı
    // değil, o tatilde de gider.
    const tatil = bistTatilMi(new Date());
    let skippedTatil = 0;
    let skippedQuietHours = 0;
    const failures: string[] = [];
    // Çan kaydı kullanıcı başına TEK (çok cihaz) — bkz. app_notifications.ts.
    const cankaydi = new Set<string>();

    // Sessiz saatler (0057): kullanıcı "bu saatte yazma" dediyse brifing
    // ATLANIR (ertelenmez — ertesi sabah zaten yeni brifing var).
    const sessiz = await sessizKullanicilar(admin, tokens.map((t) => t.user_id));

    let partnerSayisi = 0;
    for (const tokenRow of tokens) {
      if (zatenGonderildi.has(tokenRow.user_id)) continue;
      if (sessiz.has(tokenRow.user_id)) { skippedQuietHours += 1; continue; }

      // Ortak hareketi VARSA sözü o alır ve hareket eşiği aranmaz:
      // "ortağın ekleme yaptı" kendi başına bir haber, fiyat hareketine
      // bağlı değil. Bu aynı zamanda hiç hissesi olmayan (yalnız altın
      // tutan) kullanıcının da brifing almasını sağlar.
      const ortak = ortakHareketi.get(tokenRow.user_id);
      const aday = kullaniciAdaylari.get(tokenRow.user_id);

      // Hareket eşiği YALNIZCA fiyat mesajına uygulanır. "Ortağın ekleme
      // yaptı" kendi başına bir haber; fiyat hareketine bağlı değil.
      if (!ortak) {
        if (!aday) continue;
        if (tatil) {
          skippedTatil += 1;
          continue;
        }
        if (Math.abs(aday.en.changePct) < minMovePct) {
          skippedQuiet += 1;
          continue;
        }
      }

      const variant = ortak ? 'partner' : 'mover';
      const mesaj = ortak
        ? buildPartnerMessage(ortak.ad, ortak.adet)
        : buildBriefMessage(
          aday!.en.label,
          aday!.en.changePct,
          aday!.digerHareketli,
          aday!.en.tur ?? 'hisse',
          aday!.yalnizHisse ? 'hisse' : 'varlık',
        );
      if (ortak) partnerSayisi += 1;
      const veri = briefVerisi(bugun, variant, ortak ? undefined : aday!.en.sembol);

      if (dryRun) {
        sent += 1;
        continue;
      }

      // Çan sayfası kaydı — push'tan bağımsız (token reddedilse de kalır).
      const kayitHatasi = await recordAppNotification(
        admin,
        appNotificationRow({
          userId: tokenRow.user_id,
          type: 'daily_brief',
          title: mesaj.title,
          body: mesaj.body,
          data: veri,
        }),
        cankaydi,
      );
      if (kayitHatasi) failures.push(kayitHatasi);

      const r = await sendFcmNotification({
        accessToken,
        projectId: fcmProjectId,
        token: tokenRow.token,
        hesap: ekHesap(tokenRow),
        title: mesaj.title,
        body: mesaj.body,
        channelId: CHANNEL_ID,
        // Brifing/özet acil değil: iOS'ta sessiz, Bildirim Özeti'ne düşer
        // (müşteri raporu 2026-10-26 21:15 #1, `_shared/fcm.ts` › onem).
        onem: 'passive',
        data: veri,
        // Ortak mesajında kart yok: fiyat hareketi değil, bir kişinin
        // eylemi; halka ve yüzde anlatacak bir şey taşımaz.
        gorselUrl: ortak ? undefined : await kartGorseli(
          kart,
          tokenRow,
          degisimKarti(
            aday!.en.label,
            aday!.en.changePct,
            briefKartAltYazisi(aday!.en.tur ?? 'hisse'),
          ),
        ),
      });

      if (r.ok) {
        sent += 1;
        // Log YAZILIR ama hata yutulur: yazamazsak en kötü ihtimalle
        // yeniden denemede ikinci bildirim gider; bildirimi hiç
        // göndermemekten iyidir.
        await admin
          .from('daily_brief_log')
          .upsert(
            { user_id: tokenRow.user_id, sent_on: bugun },
            { onConflict: 'user_id,sent_on' },
          );
      } else {
        // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
        console.error('[daily-brief] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
        failures.push(`fcm: ${r.hataKodu}`);
        if (r.shouldDeleteToken) {
          await admin.from('user_push_tokens').delete().eq('token', tokenRow.token);
        }
      }
    }

    return jsonResponse({
      ok: true,
      sent,
      skipped_quiet: skippedQuiet,
      skipped_tatil: skippedTatil,
      skipped_quiet_hours: skippedQuietHours,
      candidates: kullaniciAdaylari.size,
      partner_variant: partnerSayisi,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    // Ayrıntı yalnızca günlüğe: yanıtta `error.message` dönmek tablo/sütun
    // ve secret adlarını sızdırır (CLAUDE.md sunucu kuralı, 2026-09-23 denetimi L2).
    console.error('[daily-brief] hata:', error);
    return jsonResponse({ error: 'Brifing gonderimi basarisiz.' }, 500);
  }
});
