// Takip listesinde günlük büyük hareket — kapanış sonrası tek push.
//
// Neden var (2026-09-20, günlük giriş turu): sahip OLMADIĞI hisseyi
// izleyen kullanıcı "alayım mı" kararı için her gün döner; ama alarm kurmak
// üç dokunuş derinde ve çoğu kurmuyor. Bu modül alarm kurmadan, izlenen
// varlık gün içinde eşiğin üstünde oynadıysa kapanışta haber verir.
//
// Kurallar:
//   · Kullanıcı başına GÜNDE TEK push, en çok üç varlık (mutlak harekete
//     göre sıralı). Her sembole ayrı push yağdırmak alarm kanalını değersiz
//     kılardı.
//   · Yalnızca kullanıcının KENDİ seçtiği liste (watchlist) — proaktif değil,
//     istek üzerine bildirim; kanal fiyat alarmıyla aynı (`alert_channel`).
//   · TEFAS fonu değişim taşımaz (günlük tek NAV) → bu turda dışarıda.
//   · Sessiz saatler ve `watchlist_move_log` (0068) günlük tekilleştirme.
//
// Sembol kuralı istemcideki `alarmSembolu` ile AYNI: altın alt kategorisi
// (ALTIN_*) sembolün kendisi, aksi hâlde ticker. Farklı olsaydı kullanıcı
// ekranda 6.200 görürken sunucu başka bir seriye bakardı.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { collapseTokens, TokenRow } from './push_tokens.ts';
import { fetchLiveQuotes } from './live_prices.ts';
import { sessizKullanicilar } from './quiet_hours.ts';
import { appNotificationRow, recordAppNotification } from './app_notifications.ts';

/** Bildirime değer günlük hareket (mutlak, yüzde). */
export const HAREKET_ESIGI_PCT = 5;
/** Tek push'ta en çok kaç varlık anılır. */
export const EN_COK_VARLIK = 3;
export const CHANNEL_ID = 'alert_channel';

export type Hareket = { ad: string; pct: number };

/// İstemcideki `alarmSembolu` (lib/widgets/alarm_kur_sheet.dart) eşi.
export function takipSembolu(ticker: string, subCategory: string | null | undefined): string | null {
  const sub = (subCategory ?? '').trim();
  if (sub.startsWith('ALTIN_')) return sub;
  const t = ticker.trim();
  return t.length === 0 ? null : t;
}

/// Eşiği aşanları mutlak harekete göre sırala, ilk N.
export function hareketleriSec(
  adaylar: Hareket[],
  esikPct = HAREKET_ESIGI_PCT,
  enCok = EN_COK_VARLIK,
): Hareket[] {
  return adaylar
    .filter((h) => Number.isFinite(h.pct) && Math.abs(h.pct) >= esikPct)
    .sort((a, b) => Math.abs(b.pct) - Math.abs(a.pct))
    .slice(0, enCok);
}

/// Mesaj — tutar yok, tavsiye yok, emoji yok (RETENTION_STRATEJISI §8–9).
/// Ondalık ayırıcı Türkçe virgül; yön oku başlıkta.
export function hareketMesaji(hareketler: Hareket[]): { title: string; body: string } {
  const parca = (h: Hareket) => {
    const m = Math.abs(h.pct).toFixed(1).replace('.', ',');
    return `${h.ad} ${h.pct >= 0 ? '+' : '−'}%${m}`;
  };
  const ilk = hareketler[0];
  const title = hareketler.length === 1
    ? `${ilk.pct >= 0 ? '▲' : '▼'} Takip listende: ${parca(ilk)}`
    : `Takip listende ${hareketler.length} büyük hareket`;
  const body = hareketler.length === 1
    ? 'Bugünkü kapanış. Yatırım tavsiyesi değildir.'
    : `${hareketler.map(parca).join(' · ')}. Yatırım tavsiyesi değildir.`;
  return { title, body };
}

type WatchRow = {
  user_id: string;
  ticker: string;
  name: string;
  type: string;
  sub_category: string | null;
};

export async function takipListesiHareketleri(
  admin: SupabaseClient,
  args: {
    fcm: { projectId: string; serviceAccountJson: string } | null;
    dryRun: boolean;
    esikPct?: number;
  },
): Promise<Record<string, unknown>> {
  const esik = args.esikPct ?? HAREKET_ESIGI_PCT;

  const { data: rows, error } = await admin
    .from('watchlist')
    .select('user_id, ticker, name, type, sub_category');
  if (error) throw new Error(`watchlist okunamadi: ${error.message}`);
  const liste = (rows ?? []) as WatchRow[];
  if (liste.length === 0) return { ok: true, reason: 'Takip listesi bos.', sent: 0 };

  // Sembol ↔ satırlar. Fon (TEFAS) değişim taşımaz; dışarıda.
  const kullaniciSatirlari = new Map<string, Array<{ sembol: string; ad: string }>>();
  const semboller = new Set<string>();
  for (const r of liste) {
    if (r.type === 'fon') continue;
    const s = takipSembolu(r.ticker ?? '', r.sub_category);
    if (!s) continue;
    semboller.add(s);
    const l = kullaniciSatirlari.get(r.user_id) ?? [];
    l.push({ sembol: s, ad: r.name || s });
    kullaniciSatirlari.set(r.user_id, l);
  }
  if (semboller.size === 0) return { ok: true, reason: 'Fiyatlanabilir sembol yok.', sent: 0 };

  const kotasyon = await fetchLiveQuotes(semboller, admin);

  // Kullanıcı → seçilen hareketler.
  const secimler = new Map<string, Hareket[]>();
  for (const [uid, satirlar] of kullaniciSatirlari) {
    const adaylar: Hareket[] = [];
    for (const s of satirlar) {
      const q = kotasyon.get(s.sembol);
      if (!q || q.changePct === null) continue;
      adaylar.push({ ad: s.ad, pct: q.changePct });
    }
    const secili = hareketleriSec(adaylar, esik);
    if (secili.length > 0) secimler.set(uid, secili);
  }
  if (secimler.size === 0) {
    return { ok: true, reason: 'Esigi asan hareket yok.', checked: semboller.size, sent: 0 };
  }

  const userIds = [...secimler.keys()];
  const bugun = new Date().toISOString().slice(0, 10);
  const { data: gonderilmis } = await admin
    .from('watchlist_move_log')
    .select('user_id')
    .eq('sent_on', bugun)
    .in('user_id', userIds);
  const zaten = new Set((gonderilmis ?? []).map((r: { user_id: string }) => r.user_id));
  const sessiz = await sessizKullanicilar(admin, userIds);

  const { data: tokenRows } = await admin
    .from('user_push_tokens')
    .select('token, user_id, device_id, platform, updated_at')
    .in('user_id', userIds);
  const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);

  let sent = 0;
  let skippedQuietHours = 0;
  let skippedAlready = 0;
  const failures: string[] = [];
  const cankaydi = new Set<string>();
  const accessToken = args.dryRun || !args.fcm
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  for (const t of tokens) {
    const uid = t.user_id;
    const hareketler = secimler.get(uid);
    if (!hareketler) continue;
    if (zaten.has(uid)) { skippedAlready += 1; continue; }
    if (sessiz.has(uid)) { skippedQuietHours += 1; continue; }
    const mesaj = hareketMesaji(hareketler);
    if (args.dryRun || !args.fcm) { sent += 1; continue; }

    const kayitHatasi = await recordAppNotification(
      admin,
      appNotificationRow({
        userId: uid,
        type: 'watchlist_move',
        title: mesaj.title,
        body: mesaj.body,
        data: { sent_on: bugun },
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
      data: { type: 'watchlist_move', sent_on: bugun },
    });
    if (r.ok) {
      sent += 1;
      await admin
        .from('watchlist_move_log')
        .upsert({ user_id: uid, sent_on: bugun }, { onConflict: 'user_id,sent_on' });
    } else {
      // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
      console.error('[watchlist-moves] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
      failures.push(`fcm: ${r.hataKodu}`);
      if (r.shouldDeleteToken) {
        await admin.from('user_push_tokens').delete().eq('token', t.token);
      }
    }
  }

  return {
    ok: true,
    checked: semboller.size,
    users_with_moves: secimler.size,
    sent,
    skipped_already: skippedAlready,
    skipped_quiet_hours: skippedQuietHours,
    dry_run: args.dryRun,
    failures: failures.slice(0, 5),
  };
}
