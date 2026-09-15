/// Tetiklenmiş fiyat alarmının uygulama içi bildirim kaydı.
///
/// **Neden `SignalAlert`'ten ayrı bir model:** o sınıf teknik sinyale özgü
/// (`buyCount`, `sellCount`, `confidence`, al/sat/nötr). Fiyat alarmının
/// hiçbirinde karşılığı yok; aynı sınıfa sokmak dört alanı kalıcı olarak
/// anlamsız yapardı. Sunucu tarafındaki eşi `price_alert_notifications`
/// tablosudur (bkz. migration 0065).
///
/// İki tür bildirim çan sayfasında `bildirimAkisi` ile zaman sırasına göre
/// birleştirilir — ayrılık veri modelinde, birlik sunumda.
class PriceAlertNotification {
  final String id;

  /// Kaynak alarm. Alarm silinmiş olabilir (`on delete set null`): bildirim
  /// listede kalmaya devam eder, kullanıcı "dün ne oldu"yu sorabilmeli.
  final String? alertId;

  /// Fiyat kaynağının anladığı sembol ('ALTIN_GRAM', 'THYAO.IS').
  /// Varlığa geri eşleme bunun üstünden yapılır (`alarmSembolu`).
  final String symbol;

  /// Kullanıcıya gösterilecek ad — sembol kodu listede okunmaz.
  final String label;

  final double targetPrice;

  /// Tetiklendiği ANDAKİ fiyat. Hedeften farklı olabilir (fiyat hedefi
  /// aşarak geçer) ve kullanıcının görmek istediği sayı budur.
  final double triggeredPrice;

  /// 'above' → hedefe ulaştı/geçti · 'below' → altına indi
  final String direction;

  final DateTime sentAt;
  final DateTime? dismissedAt;

  const PriceAlertNotification({
    required this.id,
    this.alertId,
    required this.symbol,
    required this.label,
    required this.targetPrice,
    required this.triggeredPrice,
    required this.direction,
    required this.sentAt,
    this.dismissedAt,
  });

  bool get isDismissed => dismissedAt != null;

  /// Yukarı yönlü alarm mı — ok yönü ve renk kararı bunun üstünden.
  bool get yukari => direction == 'above';

  PriceAlertNotification copyWith({
    DateTime? dismissedAt,
    bool clearDismissed = false,
  }) =>
      PriceAlertNotification(
        id: id,
        alertId: alertId,
        symbol: symbol,
        label: label,
        targetPrice: targetPrice,
        triggeredPrice: triggeredPrice,
        direction: direction,
        sentAt: sentAt,
        dismissedAt: clearDismissed ? null : (dismissedAt ?? this.dismissedAt),
      );

  factory PriceAlertNotification.fromMap(Map<String, dynamic> m) =>
      PriceAlertNotification(
        id: m['id'] as String,
        alertId: m['alert_id'] as String?,
        symbol: m['symbol'] as String,
        label: (m['label'] as String?) ?? '',
        // numeric(18,4) JSON'da string gelebilir — `num` cast'i onu kaçırır.
        targetPrice: _sayi(m['target_price']),
        triggeredPrice: _sayi(m['triggered_price']),
        direction: (m['direction'] as String?) ?? 'above',
        sentAt: DateTime.parse(m['sent_at'] as String),
        dismissedAt: m['dismissed_at'] != null
            ? DateTime.parse(m['dismissed_at'] as String)
            : null,
      );

  /// Postgres `numeric` PostgREST'te string olarak dönebilir; iki biçim de
  /// kabul edilir. Doğrudan `as num` yapmak burada tip hatası veriyordu.
  static double _sayi(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
