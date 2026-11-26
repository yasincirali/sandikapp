// Saatli Bildirim Edge Function — kullanıcının seçtiği saatte fiyat (0188).
//
// pg_cron her 15 dakikada çağırır (`trigger_saatli_bildirim`). Bu dilime
// (TR saati + gün maskesi) düşen aktif `saatli_bildirimler` satırlarını
// okur, Premium'u olmayanı atlar (satır silinmez; istemci "Premium'la
// yeniden gönderilir" der), sembolleri tekilleştirip `fetchLiveQuotes` ile
// BİR KEZ fiyatlar ve kullanıcı başına TEK push gönderir (aynı saate düşen
// varlıklar tek bildirimde). Kurallar ve metin `_shared/saatli_bildirim.ts`.
//
// ── Çift push yok ───────────────────────────────────────────────────────────
// Push'tan ÖNCE `saatli_bildirim_gonderim (user_id, slot_ts)` yazılır;
// çakışma = bu dilimde zaten gönderildi. Yeniden deneme ya da üst üste iki
// çağrı ikinci push üretmez (`check-price-alerts` "önce damga" sırası).
//
// ── Sessiz saatler ──────────────────────────────────────────────────────────
// UYGULANMAZ (tasarım): saat kullanıcının açıkça seçtiği saattir; istemci
// seçerken pencereyle çakışırsa tek satır uyarır.
//
// ── Dokunuş ─────────────────────────────────────────────────────────────────
// `data.type = price_alert` + `symbol`: eski build'ler de fiyat alarmı gibi
// varlık ekranını açar. `saatli: '1'` + `label` eklemedir; yeni build
// portföyde olmayan varlıkta varlık sayfasını açmak için okur.
//
// ── Secret ──────────────────────────────────────────────────────────────────
// `PRICE_ALERTS_CRON_SECRET` PAYLAŞILIR (emsal hacim-gozlem, analiz-topla).
//
// Yanıt `{ ok, dilim, satir, kullanici, atlanan_premium, sent, ... }`.
// Gövde `{ "dry_run": true }` → okur ve sayar, yazmaz/göndermez. Hata mesajı,
// token, ham FCM yanıtı DÖNMEZ.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { createAccessToken, sendFcmNotification, ServiceAccount } from '../_shared/fcm.ts';
import { fetchLiveQuotes } from '../_shared/live_prices.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  TokenRow,
  tokenSatirlariniOku,
} from '../_shared/push_tokens.ts';
import { appNotificationRow, recordAppNotification } from '../_shared/app_notifications.ts';
import {
  gonderimKarari,
  kullaniciyaGore,
  mesajKur,
  saatMetni,
  SaatliSatir,
  tabloYokMu,
  trDilimi,
} from '../_shared/saatli_bildirim.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya; Allow-Origin yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Alarmla aynı kanal: kullanıcının kendi istediği, saatinde gelmesi
/// gereken fiyat (istemci `genelBildirimKanali('price_alert')`).
const CHANNEL_ID = 'alert_channel';
/// Gönderim kaydı bu kadar gün tutulur (yalnız çift push kapısı).
const KAYIT_SAKLAMA_GUN = 2;

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
    const simdi = new Date();
    const dilim = trDilimi(simdi);
    const dilimAdi = saatMetni(dilim.dakika);

    // ── 1) Bu dilimin satırları ─────────────────────────────────────────────
    const { data: satirVerisi, error: satirHatasi } = await admin
      .from('saatli_bildirimler')
      .select('user_id, symbol, label, saatler, gunler')
      .eq('aktif', true)
      .contains('saatler', [dilim.dakika]);
    if (satirHatasi) {
      if (tabloYokMu(satirHatasi)) {
        return jsonResponse({ ok: true, dilim: dilimAdi, satir: 0, tablo: 'yok' });
      }
      console.error('[saatli-bildirim] satirlar okunamadi:', satirHatasi.message);
      return jsonResponse({ ok: false }, 500);
    }
    const plan = kullaniciyaGore((satirVerisi ?? []) as SaatliSatir[], dilim);
    if (plan.size === 0) {
      return jsonResponse({ ok: true, dilim: dilimAdi, satir: 0, kullanici: 0, sent: 0 });
    }

    // ── 2) Premium kapısı ───────────────────────────────────────────────────
    // `saatli_gonderilmez_kullanicilar` (0188): kapı açık, acil kapalı ve
    // Premium değil. Okunamazsa kapı bu tur uygulanmaz: aboneye bir dilim
    // kaçırtmak, bitmiş birine bir dilim fazla göndermekten pahalı
    // (analyze-signals ile aynı karar).
    const gonderilmez = new Set<string>();
    {
      const { data, error } = await admin.rpc('saatli_gonderilmez_kullanicilar', {
        p_user_ids: [...plan.keys()],
      });
      if (error) {
        console.error('[saatli-bildirim] premium kapisi okunamadi, bu tur uygulanmadi');
      } else {
        for (const u of (data ?? []) as unknown[]) gonderilmez.add(String(u));
      }
    }
    for (const u of gonderilmez) plan.delete(u);
    if (plan.size === 0) {
      return jsonResponse({
        ok: true, dilim: dilimAdi, kullanici: 0, atlanan_premium: gonderilmez.size, sent: 0,
      });
    }

    // ── 3) Fiyatlar: sembol başına bir kez ─────────────────────────────────
    const semboller = new Set<string>();
    for (const l of plan.values()) for (const s of l) semboller.add(s.symbol);
    const kotasyonlar = await fetchLiveQuotes(semboller, admin);

    // ── 4) Token'lar ────────────────────────────────────────────────────────
    const userIds = [...plan.keys()];
    const tokensByUser = new Map<string, TokenRow[]>();
    if (!dryRun) {
      const { data: tokenRows } = await tokenSatirlariniOku((s) =>
        admin.from('user_push_tokens').select(s).in('user_id', userIds)
      );
      const tokens = collapseTokens([
        ...(tokenRows ?? []),
        ...await ekHesapSatirlari(admin, userIds),
      ]);
      for (const t of tokens) {
        const l = tokensByUser.get(t.user_id);
        if (l) l.push(t);
        else tokensByUser.set(t.user_id, [t]);
      }
    }
    const accessToken = dryRun
      ? ''
      : await createAccessToken(JSON.parse(fcmServiceAccountJson) as ServiceAccount);

    let sent = 0;
    let mesajli = 0;
    let fiyatsiz = 0;
    let zaten = 0;
    const failures: string[] = [];

    for (const [userId, satirlar] of plan) {
      const mesaj = mesajKur(satirlar, kotasyonlar, dilim, simdi);
      // Hiçbir fiyat bilinmiyor: push yok, kayıt da yok (uydurma sayı yasak).
      if (mesaj === null) { fiyatsiz += 1; continue; }
      mesajli += 1;
      if (dryRun) continue;

      const { error: kayitHatasi } = await admin
        .from('saatli_bildirim_gonderim')
        .insert({ user_id: userId, slot_ts: dilim.slotTs });
      const karar = gonderimKarari(kayitHatasi);
      if (karar === 'zaten') { zaten += 1; continue; }
      if (karar === 'hata') {
        console.error('[saatli-bildirim] gonderim kaydi yazilamadi:', kayitHatasi?.message);
        failures.push('kayit: yazilamadi');
        continue;
      }

      const data = { type: 'price_alert', symbol: mesaj.symbol, label: mesaj.label, saatli: '1' };
      const hata = await recordAppNotification(admin, appNotificationRow({
        userId,
        type: 'saatli_bildirim',
        title: mesaj.title,
        body: mesaj.body,
        data,
      }));
      if (hata) failures.push(hata);

      for (const t of tokensByUser.get(userId) ?? []) {
        const r = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token: t.token,
          hesap: ekHesap(t),
          title: mesaj.title,
          body: mesaj.body,
          channelId: CHANNEL_ID,
          // Kullanıcının seçtiği saatte gelmeli; `normal`de APNs 5 erteler.
          priority: 'high',
          data,
        });
        if (r.ok) {
          sent += 1;
        } else {
          console.error('[saatli-bildirim] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
          failures.push(`fcm: ${r.hataKodu}`);
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', t.token);
          }
        }
      }
    }

    // ── 5) Eski gönderim kayıtları ──────────────────────────────────────────
    if (!dryRun) {
      const sinir = new Date(simdi.getTime() - KAYIT_SAKLAMA_GUN * 86_400_000).toISOString();
      const { error } = await admin.from('saatli_bildirim_gonderim').delete().lt('slot_ts', sinir);
      if (error) failures.push('temizlik: yapilamadi');
    }

    return jsonResponse({
      ok: true,
      dilim: dilimAdi,
      kullanici: plan.size,
      atlanan_premium: gonderilmez.size,
      sembol: semboller.size,
      fiyatli: kotasyonlar.size,
      mesaj: mesajli,
      fiyatsiz,
      zaten,
      sent,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    // Ayrıntı yalnız günlüğe (CLAUDE.md sunucu kuralı).
    console.error('[saatli-bildirim] hata:', error);
    return jsonResponse({ error: 'Saatli bildirim basarisiz.' }, 500);
  }
});
