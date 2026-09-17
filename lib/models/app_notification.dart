/// Genel uygulama bildirimi — ortaklık daveti, günlük brifing, haftalık özet,
/// takvim hatırlatması. Sunucu eşi `app_notifications` (migration 0066).
///
/// **Neden `SignalAlert`/`PriceAlertNotification`'dan ayrı:** o ikisi türe
/// özgü sayısal alan taşıyor (güven, hedef fiyat). Bu dört türün ortak yapısı
/// başlık + gövde + küçük bir yönlendirme sözlüğü; tek model yeter. Çan
/// sayfasında üçü `bildirimAkisi` ile zaman sırasına göre birleşir.
class AppNotification {
  static const partnerInvite = 'partner_invite';
  static const dailyBrief = 'daily_brief';
  static const weeklySummary = 'weekly_summary';
  static const calendarNudge = 'calendar_nudge';

  final String id;
  final String type;
  final String title;
  final String body;

  /// Yönlendirme için gereken kimlikler (`invite_id` vb.). Tür başına farklı.
  final Map<String, dynamic> data;
  final DateTime sentAt;
  final DateTime? dismissedAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    required this.sentAt,
    this.dismissedAt,
  });

  bool get isDismissed => dismissedAt != null;

  AppNotification copyWith({DateTime? dismissedAt}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        data: data,
        sentAt: sentAt,
        dismissedAt: dismissedAt ?? this.dismissedAt,
      );

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: (m['type'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        data: (m['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        sentAt: DateTime.parse(m['sent_at'] as String),
        dismissedAt: m['dismissed_at'] != null
            ? DateTime.parse(m['dismissed_at'] as String)
            : null,
      );
}
