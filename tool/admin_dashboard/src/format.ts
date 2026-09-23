/* Biçimlendirme — panel Türkçe ve TR saat diliminde okunur.
 *
 * Uygulamadaki lib/utils/tr_format.dart'ın karşılığı değil (burada para
 * yok, süre ve zaman var); ama aynı yerelleştirme kararı: tr-TR. */

const TZ = 'Europe/Istanbul';

const dtFull = new Intl.DateTimeFormat('tr-TR', {
  timeZone: TZ,
  day: '2-digit',
  month: '2-digit',
  year: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  second: '2-digit',
});

const dtShort = new Intl.DateTimeFormat('tr-TR', {
  timeZone: TZ,
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});

const hourOnly = new Intl.DateTimeFormat('tr-TR', {
  timeZone: TZ,
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
});

export const fmtTs = (s: string | null | undefined) => (s ? dtFull.format(new Date(s)) : '—');
export const fmtTsShort = (s: string | null | undefined) => (s ? dtShort.format(new Date(s)) : '—');
export const fmtHour = (s: string) => hourOnly.format(new Date(s));

export const fmtNum = (n: number | null | undefined) =>
  n === null || n === undefined ? '—' : new Intl.NumberFormat('tr-TR').format(n);

/** "3 dk önce" — log listesinde mutlak zamandan daha hızlı okunur. */
export function fmtRelative(s: string | null | undefined): string {
  if (!s) return '—';
  const diff = Date.now() - new Date(s).getTime();
  const sec = Math.round(diff / 1000);
  if (sec < 0) return 'az sonra';
  if (sec < 60) return `${sec} sn önce`;
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} dk önce`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr} sa önce`;
  const day = Math.round(hr / 24);
  if (day < 30) return `${day} gün önce`;
  return fmtTsShort(s);
}

export const fmtMs = (ms: number | null | undefined) =>
  ms === null || ms === undefined ? '—' : ms >= 1000 ? `${(ms / 1000).toFixed(1)} sn` : `${ms} ms`;

/** Kilit kalan süresi: 610 → "10 dk 10 sn". */
export function fmtDuration(sec: number): string {
  if (sec <= 0) return '—';
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return m > 0 ? `${m} dk ${s} sn` : `${s} sn`;
}

export const pct = (v: number | null | undefined) =>
  v === null || v === undefined ? '—' : `%${Number(v).toFixed(1)}`;

/** Uzun hata metinlerini tabloda kısalt; tam metin detayda. */
export const kisalt = (s: string | null | undefined, n = 90) =>
  !s ? '—' : s.length > n ? `${s.slice(0, n)}…` : s;

export function prettyJson(v: unknown): string {
  if (v === null || v === undefined) return '—';
  try {
    return JSON.stringify(v, null, 2);
  } catch {
    return String(v);
  }
}

/** `source` alanından servis adını ayıkla: "AuthService.login" → "AuthService". */
export const servisAdi = (source: string) => source.split('.')[0] ?? source;

/* ── 0071: seans / cihaz / zaman biçimleri ───────────────────────────── */

/** Seans süresi: 4512 sn → "1 sa 15 dk". Liste sütununda kompakt durur. */
export function fmtSure(sn: number | null | undefined): string {
  if (sn === null || sn === undefined) return '—';
  const s = Math.round(sn);
  if (s < 60) return `${s} sn`;
  const dk = Math.floor(s / 60);
  if (dk < 60) return `${dk} dk ${s % 60} sn`;
  const sa = Math.floor(dk / 60);
  return `${sa} sa ${dk % 60} dk`;
}

/**
 * Olaylar arası boşluk. Kullanıcı davranışını okutan alan: 40 sn'lik
 * boşluk "düşündü/bekledi", 0.2 sn "otomatik yeniden deneme".
 */
export function fmtBosluk(sn: number | null | undefined): string {
  if (sn === null || sn === undefined) return '—';
  if (sn < 1) return `+${sn.toFixed(1)} sn`;
  if (sn < 60) return `+${Math.round(sn)} sn`;
  const dk = Math.round(sn / 60);
  if (dk < 60) return `+${dk} dk`;
  return `+${Math.round(dk / 60)} sa`;
}

/**
 * Cihaz saati sapması. `ts - requested_at`: istemcinin "isteği attım"
 * dediği an ile sunucunun satırı yazdığı an arası. Birkaç saniye normal
 * (ağ + kuyruk); dakikalar cihaz saatinin şaştığını söyler ve OTP/token
 * akışlarında asıl sebep olabilir.
 */
export function fmtSapma(ms: number | null | undefined): string {
  if (ms === null || ms === undefined) return '—';
  const a = Math.abs(ms);
  const isaret = ms < 0 ? '−' : '+';
  if (a < 1000) return `${isaret}${a} ms`;
  if (a < 60000) return `${isaret}${(a / 1000).toFixed(1)} sn`;
  return `${isaret}${Math.round(a / 60000)} dk`;
}

/** Sapma ciddi mi? Eşik 2 dk: altı ağ gecikmesi, üstü saat problemi. */
export const sapmaCiddi = (ms: number | null | undefined) =>
  ms !== null && ms !== undefined && Math.abs(ms) > 120_000;

/** Seans/cihaz kimliği uzun ve okunmaz; ilk 8 karakter ayırt etmeye yeter. */
export const kisaKimlik = (id: string | null | undefined) =>
  !id ? '—' : id.length > 10 ? `${id.slice(0, 8)}…` : id;

/** Cihaz künyesi tek satır: "ios 18.2 · 1.1.4+7 · iPhone14,2". */
export function cihazKunye(d: {
  platform?: string | null;
  os_version?: string | null;
  app_version?: string | null;
  device_model?: string | null;
}): string {
  const p = [
    [d.platform, d.os_version].filter(Boolean).join(' '),
    d.app_version,
    d.device_model,
  ].filter((x) => x && x.length > 0);
  return p.length ? p.join(' · ') : 'bilinmiyor';
}
