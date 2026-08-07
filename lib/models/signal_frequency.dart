/// Sinyal bildirimi sıklığı — varlık türü başına seçilir.
///
/// Sunucu (`analyze-signals` edge function) saatbaşı çalışır ve her tercih
/// için sıranın gelip gelmediğine bakar. `id` değerleri veritabanındaki
/// `signal_preferences.frequency` check constraint'i ile birebir aynı
/// olmak ZORUNDA — biri değişirse migration da değişmeli.
enum SignalFrequency {
  hourly('hourly', 'Saatlik', 'Her saat başı kontrol edilir'),
  every2h('every_2h', '2 saatte bir', 'İki saatte bir kontrol edilir'),
  every3h('every_3h', '3 saatte bir', 'Üç saatte bir kontrol edilir'),
  twiceDaily('twice_daily', 'Günde 2 kez', 'Seçtiğin iki saatte'),
  daily('daily', 'Günde 1 kez', 'Seçtiğin saatte');

  const SignalFrequency(this.id, this.label, this.description);

  final String id;
  final String label;
  final String description;

  /// Kullanıcının saat seçmesi gereken sıklıklar. Periyodik olanlarda
  /// (saatlik/2s/3s) saat seçimi anlamsızdır — pencere boyunca tekrarlar.
  bool get needsHourPicker =>
      this == SignalFrequency.twiceDaily || this == SignalFrequency.daily;

  /// Kaç saat seçilmeli.
  int get hourCount => switch (this) {
        SignalFrequency.twiceDaily => 2,
        SignalFrequency.daily => 1,
        _ => 0,
      };

  static SignalFrequency fromId(String? id) => SignalFrequency.values.firstWhere(
        (f) => f.id == id,
        orElse: () => SignalFrequency.twiceDaily,
      );
}

/// Bildirim penceresi — TR saati. Kullanıcı bu aralığın dışında bildirim
/// seçemez; sunucu tarafında da check constraint ile korunur.
const kSignalWindowStart = 10;
const kSignalWindowEnd = 18;

/// Pencere içindeki seçilebilir saatler.
List<int> get signalSelectableHours =>
    [for (var h = kSignalWindowStart; h <= kSignalWindowEnd; h++) h];
