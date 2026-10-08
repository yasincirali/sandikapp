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

  /// TR 10:00–18:00 penceresinde günde en fazla kaç bildirim turu.
  ///
  /// Ücretsiz sürümün günlük bildirim kapısı (`free_signal_slots_per_day`)
  /// bununla kıyaslar. Sunucudaki `GUNLUK_EN_FAZLA` (analyze-signals) ile
  /// birebir aynı olmalı; `sinyal_slot_kapisi_test` ikisini karşılaştırır.
  int get gunlukEnFazla => switch (this) {
        SignalFrequency.hourly => 9, // 10..18
        SignalFrequency.every2h => 5, // 10, 12, 14, 16, 18
        SignalFrequency.every3h => 3, // 10, 13, 16
        SignalFrequency.twiceDaily => 2,
        SignalFrequency.daily => 1,
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

/// Ücretsiz sürümün günlük bildirim kapısına sığdırılmış zamanlama.
///
/// Kayıtlı tercih DEĞİŞMEZ; bu yalnız gösterilen/uygulanan hâldir ve Premium
/// alınınca kullanıcının kendi seçimi geri gelir. Sığmayan sıklık "günde 1
/// kez"e iner; saat, saat seçilen sıklıkta seçilen İLK saat, periyodikte
/// 11:00 (sabah). Sunucudaki `slotaSigdir` (analyze-signals) ile aynı kural.
({SignalFrequency frequency, List<int> hours}) slotaSigdir(
  ({SignalFrequency frequency, List<int> hours}) s,
  int slot,
) {
  if (slot <= 0 || s.frequency.gunlukEnFazla <= slot) return s;
  final ilk = s.frequency.needsHourPicker && s.hours.isNotEmpty
      ? s.hours.first
      : 11;
  return (frequency: SignalFrequency.daily, hours: [ilk]);
}
