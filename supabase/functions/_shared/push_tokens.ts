// Push token satırları — cihaz başına TEK token.
//
// Aynı fiziksel cihaz zamanla birden çok token üretir (FCM rotasyonu:
// yeniden kurulum, veri temizleme, uygulama güncellemesi) ve eski satırlar
// tabloda kalır — istemci onları yalnızca bellekteki `_currentToken`
// doluyken siliyordu, uygulama yeniden başlayınca o alan null olur. Sonuç:
// kullanıcı tek olay için aynı telefonda birden çok bildirim alır.
//
// 2026-09-14: bu kural BEŞ fonksiyonda kopyaydı (analyze-signals
// `dedupeTokensByDevice`, daily-brief / weekly-summary / calendar-nudge /
// check-price-alerts `collapseTokens`). Kopyalar birebir aynı değildi:
// `updated_at` eksikken biri NaN karşılaştırıyor, öteki 0 sayıyordu. Tek
// kaynak: eksik damga 0 sayılır, eşitlikte İLK satır kalır.

export type TokenRow = {
  token: string;
  user_id: string;
  device_id?: string | null;
  platform?: string | null;
  updated_at?: string | null;
};

/// Gruplama anahtarı: `device_id` varsa o (istemcinin `shared_preferences`'ta
/// tuttuğu kalıcı kimlik). Yoksa `platform`'a düşülür: eski sürüm istemciler
/// ve migration öncesi satırlar `device_id` taşımaz, ama aynı kullanıcının
/// aynı platformdaki satırları büyük olasılıkla aynı cihazdır.
function cihazAnahtari(row: TokenRow): string {
  return `${row.user_id}|${row.device_id ?? `platform:${row.platform ?? '?'}`}`;
}

function damga(row: TokenRow): number {
  const t = row.updated_at ? Date.parse(row.updated_at) : NaN;
  return Number.isNaN(t) ? 0 : t;
}

/// Her (kullanıcı, cihaz) için en TAZE satır — FCM rotasyonda eskisini
/// geçersiz kılar. Sıra korunur (ilk görülen cihaz önce).
export function collapseTokens<T extends TokenRow>(rows: T[]): T[] {
  const enTaze = new Map<string, T>();
  for (const row of rows) {
    const anahtar = cihazAnahtari(row);
    const mevcut = enTaze.get(anahtar);
    if (mevcut === undefined || damga(row) > damga(mevcut)) {
      enTaze.set(anahtar, row);
    }
  }
  return [...enTaze.values()];
}

/// `analyze-signals` biçimi: kullanıcı → token listesi ve elenen satır
/// sayısı (teşhiste "neden beklediğimden az bildirim" sorusunun cevabı).
export function dedupeTokensByDevice(
  rows: TokenRow[],
): { tokensByUser: Map<string, string[]>; skipped: number } {
  const tek = collapseTokens(rows);
  const tokensByUser = new Map<string, string[]>();
  for (const r of tek) {
    const list = tokensByUser.get(r.user_id) ?? [];
    list.push(r.token);
    tokensByUser.set(r.user_id, list);
  }
  return { tokensByUser, skipped: rows.length - tek.length };
}
