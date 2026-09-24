// TÜFE günü push'u — TÜİK aylık enflasyonu açıkladığında tek bildirim.
//
// Neden var (2026-09-20, günlük giriş turu): "enflasyonu geçtin mi?"
// uygulamanın markası; açıklama günü o sorunun en canlı olduğu gün. Push
// ulusal oranı taşır (aylık + yıllık), kişisel reel getiri istemcide
// hesaplanır (`RealReturnService`) — dokununca Özet'te görünür. Sunucuda
// kişisel sayı YOK: yanlış bir yüzde göndermektense oranı söyleyip soruyu
// sormak dürüst.
//
// Tekilleştirme `inflation_push_log(period)`: `fetch-inflation` cron'u
// açıklama günü birkaç kez koşabilir (0053: 10:05, gecikmede tekrar); aynı
// ay için ikinci push gitmez. Tercih anahtarı yok (ayda bir, markanın
// kalbi); sessiz saatlere uyar.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { collapseTokens, TokenRow } from './push_tokens.ts';
import { sessizKullanicilar } from './quiet_hours.ts';
import { appNotificationRow, recordAppNotification } from './app_notifications.ts';

export const CHANNEL_ID = 'summary_channel';

const AY_ADLARI = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/** 'YYYY-MM-DD' → Türkçe ay adı; bozuksa null. */
export function ayAdi(period: string): string | null {
  const m = Number(period.slice(5, 7));
  if (!Number.isInteger(m) || m < 1 || m > 12) return null;
  return AY_ADLARI[m - 1];
}

/**
 * Endeks serisinden son ayın aylık ve yıllık oranı.
 * Yıllık için 12 ay önceki satır şart; yoksa null (uydurma yok).
 * Seri `period` artan sıralı olmalı.
 */
export function enflasyonOranlari(
  satirlar: Array<{ period: string; value: number }>,
): { period: string; aylikPct: number; yillikPct: number | null } | null {
  if (satirlar.length < 2) return null;
  const son = satirlar[satirlar.length - 1];
  const onceki = satirlar[satirlar.length - 2];
  if (!(son.value > 0) || !(onceki.value > 0)) return null;
  const aylik = (son.value / onceki.value - 1) * 100;
  const yilOnce = satirlar.length >= 13 ? satirlar[satirlar.length - 13] : null;
  const yillik = yilOnce && yilOnce.value > 0 ? (son.value / yilOnce.value - 1) * 100 : null;
  return { period: son.period, aylikPct: aylik, yillikPct: yillik };
}

/// Mesaj — oran + soru. Tutar yok, emoji yok, tavsiye yok.
export function tufeMesaji(
  ay: string,
  aylikPct: number,
  yillikPct: number | null,
): { title: string; body: string } {
  const a = aylikPct.toFixed(2).replace('.', ',');
  const title = `${ay} enflasyonu %${a}`;
  const yil = yillikPct === null ? '' : `Yıllık %${yillikPct.toFixed(1).replace('.', ',')}. `;
  const body = `${yil}Portföyün geçti mi? Reel getirin Özet'te. Yatırım tavsiyesi değildir.`;
  return { title, body };
}

export async function tufeGunuPushu(
  admin: SupabaseClient,
  args: {
    period: string;
    aylikPct: number;
    yillikPct: number | null;
    fcm: { projectId: string; serviceAccountJson: string } | null;
    dryRun: boolean;
  },
): Promise<Record<string, unknown>> {
  const ay = ayAdi(args.period);
  if (!ay) return { ok: false, reason: 'period bozuk', sent: 0 };

  // Kilit: aynı ay için ikinci koşu hiç göndermez. Kuru koşu kilidi yazmaz.
  if (!args.dryRun) {
    const { error } = await admin
      .from('inflation_push_log')
      .insert({ period: args.period });
    if (error) {
      // 23505 = unique ihlali → bu ay zaten gönderildi.
      if (error.code === '23505') return { ok: true, reason: 'zaten gonderildi', sent: 0 };
      throw new Error(`inflation_push_log yazilamadi: ${error.message}`);
    }
  }

  const { data: tokenRows } = await admin
    .from('user_push_tokens')
    .select('token, user_id, device_id, platform, updated_at');
  const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);
  if (tokens.length === 0) return { ok: true, reason: 'Kayitli push token yok.', sent: 0 };
  const userIds = [...new Set(tokens.map((t) => t.user_id))];
  const sessiz = await sessizKullanicilar(admin, userIds);

  const mesaj = tufeMesaji(ay, args.aylikPct, args.yillikPct);
  let sent = 0;
  let skippedQuietHours = 0;
  const failures: string[] = [];
  const cankaydi = new Set<string>();
  const accessToken = args.dryRun || !args.fcm
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  for (const t of tokens) {
    if (sessiz.has(t.user_id)) { skippedQuietHours += 1; continue; }
    if (args.dryRun || !args.fcm) { sent += 1; continue; }

    const kayitHatasi = await recordAppNotification(
      admin,
      appNotificationRow({
        userId: t.user_id,
        type: 'inflation_day',
        title: mesaj.title,
        body: mesaj.body,
        data: { period: args.period },
      }),
      cankaydi,
    );
    if (kayitHatasi) failures.push(kayitHatasi);

    const r = await sendFcmNotification({
      accessToken,
      projectId: args.fcm.projectId,
      token: t.token,
      title: mesaj.title,
      body: mesaj.body,
      channelId: CHANNEL_ID,
      data: { type: 'inflation_day', period: args.period },
    });
    if (r.ok) {
      sent += 1;
    } else {
      // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
      console.error('[tufe-push] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
      failures.push(`fcm: ${r.hataKodu}`);
      if (r.shouldDeleteToken) {
        await admin.from('user_push_tokens').delete().eq('token', t.token);
      }
    }
  }

  return {
    ok: true,
    period: args.period,
    title: mesaj.title,
    sent,
    skipped_quiet_hours: skippedQuietHours,
    dry_run: args.dryRun,
    failures: failures.slice(0, 5),
  };
}
