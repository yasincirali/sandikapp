// Genel uygulama bildirimi kaydı — çan sayfasında görünsün diye.
//
// **Neden (kullanıcı, 2026-09-17):** ortaklık daveti, günlük brifing, haftalık
// özet ve takvim hatırlatması YALNIZCA push olarak gidiyordu; kaçırılırsa
// uygulama içinde izi kalmıyordu. Sinyal ve alarm kendi tablolarına yazıyor;
// bu dört tür `app_notifications`'a (0066) yazılır.
//
// **Push'tan BAĞIMSIZ kaydedilir:** kullanıcının token'ı yoksa ya da FCM
// reddederse bile satır yazılır — çan, push'un yedeğidir. Kayıt hatası
// gönderimi DÜŞÜRMEZ: çağıran sabit hata kodunu `failures`'a ekler, akış sürer.

export type AppNotificationType =
  | 'partner_invite'
  | 'daily_brief'
  | 'weekly_summary'
  | 'monthly_summary' // 0067 — CHECK kısıtı da orada genişletildi
  | 'watchlist_move' // 0068 — takip listesinde günlük büyük hareket
  | 'inflation_day' // 0068 — TÜİK açıklama günü
  | 'calendar_nudge';

export interface AppNotificationRow {
  user_id: string;
  type: AppNotificationType;
  title: string;
  body: string;
  data: Record<string, string>;
}

/// Yapısal tip: gerçek SupabaseClient'ı import etmeden test edilebilsin.
interface Yazici {
  from(table: string): {
    insert(row: AppNotificationRow): PromiseLike<{
      error: { message: string } | null;
    }>;
  };
}

/// Satırı kurar — saf, test edilir. Boş başlık ya da kullanıcı `null`:
/// yazılacak bir şey yoksa çanda boş bir satır göstermenin anlamı yok.
export function appNotificationRow(p: {
  userId: string;
  type: AppNotificationType;
  title: string;
  body: string;
  data?: Record<string, string>;
}): AppNotificationRow | null {
  const title = p.title.trim();
  const body = p.body.trim();
  if (!p.userId || !title) return null;
  return {
    user_id: p.userId,
    type: p.type,
    title,
    body,
    data: p.data ?? {},
  };
}

/// Kaydeder; hata varsa sabit bir kod döner (çağıran `failures`'a ekler), yoksa
/// `null`. Kullanıcı başına TEK satır: aynı kullanıcının birden çok cihazı
/// (token'ı) varsa [kaydedilen] kümesi ikinci kaydı engeller.
export async function recordAppNotification(
  admin: Yazici,
  row: AppNotificationRow | null,
  kaydedilen?: Set<string>,
): Promise<string | null> {
  if (row === null) return null;
  if (kaydedilen) {
    if (kaydedilen.has(row.user_id)) return null;
    kaydedilen.add(row.user_id);
  }
  // DB hata metni yalnızca günlüğe; dönen değer cron yanıtının `failures`'ına
  // girdiği için sabit koddur (2026-09-23 denetimi L2).
  try {
    const { error } = await admin.from('app_notifications').insert(row);
    if (!error) return null;
    console.error('[app_notifications] kayit yazilamadi:', error.message);
    return 'bildirim kaydı: yazilamadi';
  } catch (e) {
    console.error('[app_notifications] kayit yazilamadi:', e);
    return 'bildirim kaydı: yazilamadi';
  }
}
