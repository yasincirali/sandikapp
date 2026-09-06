/// Kullanıcının kurduğu fiyat alarmı.
///
/// [symbol] fiyat kaynağının anladığı koddur (`THYAO.IS`, `ALTIN_GRAM`,
/// `USDTRY=X`); [label] kullanıcıya gösterilen addır. İkisi ayrı tutulur
/// çünkü bildirimde kod okunmaz — "ALTIN_GRAM 5.400'ü geçti" kimseye bir
/// şey ifade etmez.
class PriceAlert {
  final String id;
  final String userId;
  final String symbol;
  final String label;
  final double targetPrice;

  /// `above` → fiyat hedefe ulaşınca · `below` → hedefin altına inince.
  final String direction;

  final bool enabled;

  /// Tetiklendiği an. Doluysa alarm susmuştur; kullanıcı yeniden kurabilir.
  final DateTime? triggeredAt;
  final DateTime createdAt;

  const PriceAlert({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.targetPrice,
    required this.direction,
    required this.enabled,
    required this.createdAt,
    this.triggeredAt,
  });

  bool get isAbove => direction == 'above';

  /// Hâlâ beklemede mi? (kapatılmamış ve tetiklenmemiş)
  bool get isActive => enabled && triggeredAt == null;

  factory PriceAlert.fromMap(Map<String, dynamic> m) => PriceAlert(
        id: m['id'].toString(),
        userId: m['user_id'].toString(),
        symbol: m['symbol']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        targetPrice: (m['target_price'] as num?)?.toDouble() ?? 0,
        direction: m['direction']?.toString() == 'below' ? 'below' : 'above',
        enabled: m['enabled'] == true,
        triggeredAt: m['triggered_at'] == null
            ? null
            : DateTime.tryParse(m['triggered_at'].toString()),
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'target_price': targetPrice,
        'direction': direction,
      };

  /// Verilen fiyat için mantıklı bir yön önerir.
  ///
  /// Kullanıcı hedefi yazdıktan sonra yönü ayrıca seçmek zorunda kalmasın:
  /// güncel fiyatın ÜSTÜNDE bir hedef "yükselince", ALTINDA bir hedef
  /// "düşünce" demektir. Yanlış yön seçimi alarmın hiç çalışmaması demek
  /// olurdu ve kullanıcı sebebini anlamazdı.
  static String suggestDirection({
    required double currentPrice,
    required double targetPrice,
  }) =>
      targetPrice >= currentPrice ? 'above' : 'below';
}
