// X ve Telegram istemcisi (0146). Saf parçalar `x_paylasim.ts`'te; burası
// yalnız ağ. Yanıt gövdeleri ve anahtarlar log'a YAZILMAZ — yalnız durum
// kodu (repo herkese açık, Actions log'ları da).

import { oauthBasligi, type XKimlik } from './x_paylasim.ts';

const X_API = 'https://api.x.com/2';

export function xKimligi(): XKimlik | null {
  const k = {
    consumerKey: Deno.env.get('X_API_KEY') ?? '',
    consumerSecret: Deno.env.get('X_API_SECRET') ?? '',
    token: Deno.env.get('X_ACCESS_TOKEN') ?? '',
    tokenSecret: Deno.env.get('X_ACCESS_SECRET') ?? '',
  };
  return Object.values(k).every((v) => v.length > 0) ? k : null;
}

export class XHatasi extends Error {
  constructor(public adim: string, public durum: number) {
    super(`x ${adim} ${durum}`);
  }
}

/// Görseli yükler, medya kimliğini döner (v2 media upload, tek parça).
export async function xGorselYukle(kimlik: XKimlik, png: Uint8Array<ArrayBuffer>): Promise<string> {
  const url = `${X_API}/media/upload`;
  const form = new FormData();
  form.append('media', new Blob([png], { type: 'image/png' }), 'kart.png');
  form.append('media_category', 'tweet_image');
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: await oauthBasligi('POST', url, kimlik) },
    body: form,
  });
  if (!r.ok) throw new XHatasi('medya', r.status);
  const j = await r.json();
  const id = j?.data?.id ?? j?.media_id_string;
  if (typeof id !== 'string') throw new XHatasi('medya_yanit', r.status);
  return id;
}

/// Gönderiyi atar, gönderi kimliğini döner.
export async function xGonder(kimlik: XKimlik, metin: string, medyaId: string | null): Promise<string> {
  const url = `${X_API}/tweets`;
  const govde: Record<string, unknown> = { text: metin };
  if (medyaId) govde.media = { media_ids: [medyaId] };
  const r = await fetch(url, {
    method: 'POST',
    headers: { Authorization: await oauthBasligi('POST', url, kimlik), 'Content-Type': 'application/json' },
    body: JSON.stringify(govde),
  });
  if (!r.ok) throw new XHatasi('gonderi', r.status);
  const j = await r.json();
  const id = j?.data?.id;
  if (typeof id !== 'string') throw new XHatasi('gonderi_yanit', r.status);
  return id;
}

// ── Telegram (onay kanalı) ──────────────────────────────────────────────────

export type TelegramAyar = { token: string; sohbet: string; gizli: string };

export function telegramAyari(): TelegramAyar | null {
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN') ?? '';
  const sohbet = Deno.env.get('TELEGRAM_ADMIN_CHAT_ID') ?? '';
  const gizli = Deno.env.get('TELEGRAM_WEBHOOK_SECRET') ?? '';
  return token && sohbet && gizli ? { token, sohbet, gizli } : null;
}

async function tg(ayar: TelegramAyar, yontem: string, govde: BodyInit, json = true): Promise<Response> {
  return await fetch(`https://api.telegram.org/bot${ayar.token}/${yontem}`, {
    method: 'POST',
    headers: json ? { 'Content-Type': 'application/json' } : undefined,
    body: govde,
  });
}

/// Taslağı görseliyle ve iki düğmeyle yöneticiye yollar.
export async function telegramTaslakGonder(
  ayar: TelegramAyar,
  id: number,
  baslik: string,
  png: Uint8Array<ArrayBuffer> | null,
  dugmeler: boolean,
): Promise<boolean> {
  const klavye = dugmeler
    ? JSON.stringify({ inline_keyboard: [[{ text: 'Yayınla', callback_data: `o:${id}` }, { text: 'Reddet', callback_data: `r:${id}` }]] })
    : undefined;
  let r: Response;
  if (png) {
    const form = new FormData();
    form.append('chat_id', ayar.sohbet);
    form.append('photo', new Blob([png], { type: 'image/png' }), 'kart.png');
    form.append('caption', baslik.slice(0, 1024));
    if (klavye) form.append('reply_markup', klavye);
    r = await tg(ayar, 'sendPhoto', form, false);
  } else {
    r = await tg(ayar, 'sendMessage', JSON.stringify({ chat_id: ayar.sohbet, text: baslik, reply_markup: klavye ? JSON.parse(klavye) : undefined }));
  }
  if (!r.ok) console.error('[x] telegram gonderim', r.status);
  return r.ok;
}

export async function telegramCevapla(ayar: TelegramAyar, geriCagriId: string, metin: string): Promise<void> {
  const r = await tg(ayar, 'answerCallbackQuery', JSON.stringify({ callback_query_id: geriCagriId, text: metin.slice(0, 190) }));
  if (!r.ok) console.error('[x] telegram cevap', r.status);
}

/// Onaylanan/reddedilen mesajın düğmelerini kaldırıp altına sonucu yazar.
export async function telegramSonucYaz(ayar: TelegramAyar, mesajId: number, eskiBaslik: string, sonuc: string): Promise<void> {
  const r = await tg(ayar, 'editMessageCaption', JSON.stringify({
    chat_id: ayar.sohbet,
    message_id: mesajId,
    caption: `${eskiBaslik}\n\n— ${sonuc}`.slice(0, 1024),
    reply_markup: { inline_keyboard: [] },
  }));
  if (!r.ok) console.error('[x] telegram duzenle', r.status);
}

/// Webhook'u kaydeder (idempotent). `x-onay` adresi ve gizli başlık.
export async function telegramWebhookKur(ayar: TelegramAyar, supabaseUrl: string): Promise<void> {
  const r = await tg(ayar, 'setWebhook', JSON.stringify({
    url: `${supabaseUrl}/functions/v1/x-onay`,
    secret_token: ayar.gizli,
    allowed_updates: ['callback_query'],
    drop_pending_updates: false,
  }));
  if (!r.ok) console.error('[x] telegram webhook', r.status);
}
