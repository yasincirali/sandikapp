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
import { loadPriceHistories, resolveSymbol } from '../_shared/price_history.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
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

type AssetRow = {
  id: string;
  user_id: string;
  name: string;
  ticker: string;
  type: string;
  is_manual_price: boolean | null;
  kind: string | null;
};

type TokenRow = {
  token: string;
  user_id: string;
  device_id: string | null;
  platform: string | null;
  updated_at: string | null;
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
export function buildBriefMessage(
  label: string,
  changePct: number,
  otherCount: number,
): { title: string; body: string } {
  const yukari = changePct >= 0;
  const mutlak = Math.abs(changePct).toFixed(1).replace('.', ',');
  const kalan = otherCount > 0
    ? `Portföyündeki diğer ${otherCount} hisse daha var. `
    : '';
  return {
    title: `${yukari ? '▲' : '▼'} ${label} son kapanışta %${mutlak} ` +
      `${yukari ? 'yükseldi' : 'düştü'}`,
    body: `Portföyünde en çok hareket eden hisse. ${kalan}` +
      'Yatırım tavsiyesi değildir.',
  };
}

/// Ortak hareketi mesajı.
///
/// Ne EKLENDİĞİ söylenmez, yalnızca ekleme YAPILDIĞI. Varlık adı bildirimde
/// geçseydi kilit ekranında omzunun üstünden bakan biri ortağın ne aldığını
/// görürdü; uygulama içinde zaten görünen bir bilgi, kilit ekranında
/// görünmek zorunda değil.
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
export function collapseTokens(rows: TokenRow[]): TokenRow[] {
  const enTaze = new Map<string, TokenRow>();
  for (const row of rows) {
    const anahtar = `${row.user_id}|${row.device_id ?? `platform:${row.platform ?? '?'}`}`;
    const mevcut = enTaze.get(anahtar);
    if (
      !mevcut ||
      Date.parse(row.updated_at ?? '') > Date.parse(mevcut.updated_at ?? '')
    ) {
      enTaze.set(anahtar, row);
    }
  }
  return [...enTaze.values()];
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
    const cronSecret = Deno.env.get('DAILY_BRIEF_CRON_SECRET');

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

    if (cronSecret) {
      const authHeader = request.headers.get('Authorization');
      if (authHeader !== `Bearer ${cronSecret}`) {
        return jsonResponse({ error: 'Yetkisiz cron cagrisi.' }, 401);
      }
    }

    let dryRun = false;
    let minMovePct = DEFAULT_MIN_MOVE_PCT;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.min_move_pct === 'number') minMovePct = body.min_move_pct;
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // ── 1) Push token'ı olan kullanıcılar ───────────────────────────────────
    const { data: tokenRows, error: tokenError } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at');
    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);
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

    // ── 3) Varlıklar ────────────────────────────────────────────────────────
    // Yalnızca BIST hissesi (bkz. dosya başındaki kapsam notu), aktif alım
    // lot'ları ve fiyatı otomatik çekilenler.
    //
    // `deleted_at is null` ŞART: silme fiziksel değil, damgalı
    // (bkz. 0027_soft_delete_lots). Filtre olmadan kullanıcı sildiği hisse
    // için brifing alırdı.
    const { data: assetRows, error: assetError } = await admin
      .from('assets')
      .select('id, user_id, name, ticker, type, is_manual_price, kind')
      .in('user_id', userIds)
      .eq('type', 'hisse')
      .is('deleted_at', null);
    if (assetError) {
      throw new Error(`Varliklar alinamadi: ${assetError.message}`);
    }

    const assets = ((assetRows ?? []) as AssetRow[]).filter((a) =>
      a.is_manual_price !== true && (a.kind ?? 'buy') === 'buy'
    );
    if (assets.length === 0) {
      return jsonResponse({ ok: true, reason: 'Brifing icin hisse yok.', sent: 0 });
    }

    // ── 4) Fiyat serileri (semboller arası paylaşımlı cache) ────────────────
    const semboller = new Set<string>();
    for (const a of assets) {
      const s = resolveSymbol(a.ticker ?? '', a.type);
      if (s) semboller.add(s);
    }
    const histories = await loadPriceHistories(admin, semboller);

    // ── 5) Kullanıcı başına en çok hareket eden hisse ───────────────────────
    type Aday = { label: string; changePct: number };
    const kullaniciAdaylari = new Map<string, { en: Aday; toplam: number }>();

    for (const a of assets) {
      if (zatenGonderildi.has(a.user_id)) continue;
      const sembol = resolveSymbol(a.ticker ?? '', a.type);
      if (!sembol) continue;
      const closes = histories.get(sembol);
      if (!closes) continue;
      const degisim = lastChangePct(closes);
      if (degisim === null) continue;

      const label = shortLabel(a.name, a.ticker ?? '');
      const mevcut = kullaniciAdaylari.get(a.user_id);
      if (!mevcut) {
        kullaniciAdaylari.set(a.user_id, {
          en: { label, changePct: degisim },
          toplam: 1,
        });
        continue;
      }
      mevcut.toplam += 1;
      if (Math.abs(degisim) > Math.abs(mevcut.en.changePct)) {
        mevcut.en = { label, changePct: degisim };
      }
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
          .select('user_id')
          .in('user_id', tumOrtaklar)
          .eq('kind', 'buy')
          .is('deleted_at', null)
          .gte('added_date', dun);

        const sayac = new Map<string, number>();
        for (const r of (yeniLotlar ?? []) as Array<Record<string, unknown>>) {
          const u = String(r.user_id);
          sayac.set(u, (sayac.get(u) ?? 0) + 1);
        }

        for (const [alici, liste] of ortaklar) {
          if (profiller.get(alici)?.ister === false) continue;
          for (const ortak of liste) {
            const adet = sayac.get(ortak) ?? 0;
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
    const failures: string[] = [];

    let partnerSayisi = 0;
    for (const tokenRow of tokens) {
      if (zatenGonderildi.has(tokenRow.user_id)) continue;

      // Ortak hareketi VARSA sözü o alır ve hareket eşiği aranmaz:
      // "ortağın ekleme yaptı" kendi başına bir haber, fiyat hareketine
      // bağlı değil. Bu aynı zamanda hiç hissesi olmayan (yalnız altın
      // tutan) kullanıcının da brifing almasını sağlar.
      const ortak = ortakHareketi.get(tokenRow.user_id);
      const aday = kullaniciAdaylari.get(tokenRow.user_id);

      // Hareket eşiği YALNIZCA hisse mesajına uygulanır. "Ortağın ekleme
      // yaptı" kendi başına bir haber; fiyat hareketine bağlı değil.
      if (!ortak) {
        if (!aday) continue;
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
          Math.max(0, aday!.toplam - 1),
        );
      if (ortak) partnerSayisi += 1;

      if (dryRun) {
        sent += 1;
        continue;
      }

      const r = await sendFcmNotification({
        accessToken,
        projectId: fcmProjectId,
        token: tokenRow.token,
        title: mesaj.title,
        body: mesaj.body,
        channelId: CHANNEL_ID,
        data: { type: 'daily_brief', sent_on: bugun, variant },
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
        failures.push(r.rawText.slice(0, 200));
        if (r.shouldDeleteToken) {
          await admin.from('user_push_tokens').delete().eq('token', tokenRow.token);
        }
      }
    }

    return jsonResponse({
      ok: true,
      sent,
      skipped_quiet: skippedQuiet,
      candidates: kullaniciAdaylari.size,
      partner_variant: partnerSayisi,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
