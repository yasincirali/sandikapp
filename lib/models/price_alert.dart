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

/// Bir sembolün ETKİN alarmlarının satır özeti: gösterilecek tek hedef +
/// kalan etkin alarm sayısı (takip listesi çanı, 2026-10-26).
class EtkinAlarmOzeti {
  /// Güncel fiyata en yakın etkin alarm.
  final PriceAlert enYakin;

  /// [enYakin] dışında kalan etkin alarm sayısı ("+N").
  final int digerSayisi;

  const EtkinAlarmOzeti(this.enYakin, this.digerSayisi);
}

/// [alarmlar] içinden yalnız ETKİN olanları ([PriceAlert.isActive]) alır,
/// güncel fiyata en yakın hedefi seçer. Etkin alarm yoksa `null`.
///
/// **Neden en yakın:** satırda tek hedefe yer var; kullanıcının "ne zaman
/// haber gelecek" sorusunun cevabı fiyata en yakın eşiktir, en yeni ya da en
/// eski alarm değil. Tetiklenmiş/kapalı alarm haber vermeyeceği için sayılmaz
/// — çan "bekleyen bir alarm var" demektir.
///
/// [guncelFiyat] bilinmiyorsa (null/0) mesafe hesaplanamaz; sayı uydurulmaz,
/// listenin sırası (provider: en yeni önce) korunur ve ilk etkin alarm
/// gösterilir. Eşit mesafede de listedeki ilk kazanır (deterministik).
EtkinAlarmOzeti? etkinAlarmOzeti(Iterable<PriceAlert> alarmlar,
    {double? guncelFiyat}) {
  final etkin = [for (final a in alarmlar) if (a.isActive) a];
  if (etkin.isEmpty) return null;
  var enYakin = etkin.first;
  final f = guncelFiyat;
  if (f != null && f > 0) {
    var enKisa = (enYakin.targetPrice - f).abs();
    for (final a in etkin.skip(1)) {
      final m = (a.targetPrice - f).abs();
      if (m < enKisa) {
        enKisa = m;
        enYakin = a;
      }
    }
  }
  return EtkinAlarmOzeti(enYakin, etkin.length - 1);
}
