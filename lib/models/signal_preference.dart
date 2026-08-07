import 'signal_frequency.dart';

/// Sunucudaki `signal_preferences` tablosunun bir satırı.
///
/// Kullanıcı × varlık türü başına: güven eşiği, aktif göstergeler ve nötr
/// bildirim tercihi. Sunucu taraflı sinyal analizi (`analyze-signals` edge
/// function) push kararını bu değerlere göre verir.
///
/// Oturum açılışında sunucu doğruluk kaynağıdır: kayıt varsa cihaza indirilir,
/// yoksa cihazdaki değerler yukarı taşınır. Bkz.
/// `syncSignalPreferencesOnLogin`.
class SignalPreferenceRow {
  const SignalPreferenceRow({
    required this.assetType,
    required this.threshold,
    required this.indicators,
    required this.neutralPush,
    required this.signalsEnabled,
    this.frequency = SignalFrequency.twiceDaily,
    this.notifyHours = const [11, 15],
  });

  /// Bildirim sıklığı — sunucu saatbaşı çalışıp bu değere göre karar verir.
  final SignalFrequency frequency;

  /// twice_daily/daily için seçilen TR saatleri. Periyodik sıklıklarda
  /// kullanılmaz. Pencere (10-18) dışına çıkamaz.
  final List<int> notifyHours;

  /// `AssetType.name` karşılığı ('hisse', 'fon', 'altin', ...).
  final String assetType;

  /// Güven eşiği (0-100). Bu değerin altındaki sinyaller push edilmez.
  final int threshold;

  /// Aktif gösterge id'leri ('rsi', 'macd', ...). Boş liste = sunucudaki
  /// varsayılan set kullanılır.
  final List<String> indicators;

  /// Nötr sinyaller de bildirilsin mi.
  final bool neutralPush;

  /// Bu tür için sinyal bildirimi gönderilsin mi (ana anahtar).
  ///
  /// Sunucuda tutulmasının sebebi: push'u sunucu gönderiyor. Tercih yalnızca
  /// cihazda kalsaydı kullanıcı bildirimleri kapatsa bile sunucu göndermeye
  /// devam ederdi.
  final bool signalsEnabled;
}
