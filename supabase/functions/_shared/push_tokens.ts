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
  /// 0092: cihazın anladığı bildirim biçimi (yeni istemci yazar; eski NULL).
  bildirim_surumu?: number | null;
  /// 0137 çoklu hesap: satır cihazın PASİF hesabına aitse (o an başka hesap
  /// açık) bildirim başlığına konacak hesap adı. Birincil satırda yok.
  hesap_etiketi?: string | null;
};

/// Gönderen fonksiyonların okuduğu sütunlar.
export const TOKEN_SUTUNLARI = 'token, user_id, device_id, platform, updated_at';

type SorguSonucu = {
  data: unknown;
  error: { code?: string; message: string } | null;
};

/// Token satırlarını `bildirim_surumu` ile okur; sütun o projede henüz
/// yoksa (0092 dağıtılmadan fonksiyon dağıtıldıysa) eski seçime düşer.
///
/// Düşüş şart: sütunu körlemesine seçmek 42703 döndürür ve o turda HİÇ
/// bildirim gitmez — kart gibi bir süs için bütün push'u riske atmak olmaz.
/// `sorgu` sütun listesini alıp aynı sorguyu kurar (filtreler çağıranda).
export async function tokenSatirlariniOku(
  sorgu: (sutunlar: string) => PromiseLike<SorguSonucu>,
): Promise<{ data: TokenRow[] | null; error: SorguSonucu['error'] }> {
  const ilk = await sorgu(`${TOKEN_SUTUNLARI}, bildirim_surumu`);
  if (
    ilk.error &&
    (ilk.error.code === '42703' || ilk.error.message.includes('bildirim_surumu'))
  ) {
    const eski = await sorgu(TOKEN_SUTUNLARI);
    return { data: (eski.data ?? null) as TokenRow[] | null, error: eski.error };
  }
  return { data: (ilk.data ?? null) as TokenRow[] | null, error: ilk.error };
}

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

/// `SupabaseClient` yapısal olarak uyar; test sahte istemci verir.
type RpcIstemcisi = {
  rpc: (fn: string, args?: Record<string, unknown>) => unknown;
};

/// Cihazlardaki PASİF hesapların token satırları (0137,
/// `push_ek_hesap_hedefleri`). Çoklu hesap kullanan cihazda token'ın birincil
/// sahibi o an açık hesaptır; öteki hesapların bildirimi bu satırlarla gider.
///
/// `userIds` verilirse yalnız o kullanıcılar. Hata (RPC henüz dağıtılmamış,
/// 42883/PGRST202 vb.) boş liste döner: ek hesap bildirimi bir süstür, onun
/// yüzünden birincil gönderim düşmemeli. Tablo boşken (bayrak kapalı, kimse
/// hesap eklememiş) sonuç boştur — mevcut gönderim birebir aynı kalır.
export async function ekHesapSatirlari(
  admin: RpcIstemcisi,
  userIds: string[] | null = null,
): Promise<TokenRow[]> {
  if (userIds !== null && userIds.length === 0) return [];
  try {
    const { data, error } = (await admin.rpc(
      'push_ek_hesap_hedefleri',
      userIds === null ? {} : { p_user_ids: userIds },
    )) as SorguSonucu;
    if (error) {
      console.warn('push_ek_hesap_hedefleri', error.code ?? 'hata');
      return [];
    }
    return Array.isArray(data) ? (data as TokenRow[]) : [];
  } catch (_) {
    return [];
  }
}

/// `sendFcmNotification({ hesap })` değeri: pasif hesap satırıysa hesap
/// kimliği + etiketi, birincil satırsa `undefined` (gövde birebir eskisi).
export function ekHesap(
  row: Pick<TokenRow, 'user_id' | 'hesap_etiketi'>,
): { uid: string; etiket: string } | undefined {
  const etiket = row.hesap_etiketi?.trim();
  return etiket ? { uid: row.user_id, etiket } : undefined;
}
