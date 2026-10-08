import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset_type.dart';
import '../models/signal_frequency.dart';
import '../services/technical_analysis_service.dart';
import 'preferences_provider.dart';

/// Sinyal ön ayarı — "Ne sıklıkta haber verelim?" (Sadeleştirme 2, bayrak
/// `sinyal_on_ayar`).
///
/// Sinyal Ayarları ~80 denetimle açılıyordu (8 kategori × eşik + sıklık +
/// saat + 8 gösterge). Kullanıcının çoğu tek bir şey ister: "az mı, çok mu".
/// Ön ayar TÜM kategorilere birden yazar; kategori ayarları yerinde kalır
/// ("Kategoriye göre özelleştir" altında). Yeni bir saklama yok: ön ayar
/// yalnız var olan eşik/gösterge/sıklık tercihlerinin bir BİRLEŞİMİDİR ve
/// hangisinin seçili olduğu kayıtlı değerlerden geri okunur.
enum SinyalOnAyar { az, dengeli, cok }

/// Bir ön ayarın bir türe yazdığı değerler.
///
/// [gostergeler] yalnız Premium OLMAYAN göstergeleri kapsar: Premium
/// göstergeler ön ayarın konusu değildir — kullanıcının açtığı ADX/CCI/
/// Williams %R olduğu gibi kalır, kilidi de eskisi gibi ekranda
/// (`premiumUnlocked: !paywallOn || premium`). [saatler] `null`: periyodik
/// sıklık, saat seçilmez (kayıtlı saatlere dokunulmaz).
typedef SinyalOnAyarTanimi = ({
  int esik,
  SignalFrequency siklik,
  List<int>? saatler,
  Set<String> gostergeler,
});

/// Ön ayarın uygulandığı türler — ayar ekranının gösterdiği türlerle aynı
/// (mevduat hariç; bkz. `signal_settings_screen.dart` ve
/// `sinyal_turleri_test`).
List<AssetType> get sinyalOnAyarTurleri =>
    [for (final t in AssetType.values) if (t != AssetType.mevduat) t];

/// "Az"ın göstergeleri: en yaygın iki gösterge. Daha az gösterge daha az
/// sinyal demektir; RSI ve MACD sunucu analizinin de omurgası.
const kSinyalCekirdekGostergeler = <String>{IndicatorId.rsi, IndicatorId.macd};

Set<String> _premiumsuz(Iterable<String> ids) =>
    ids.where((id) => !IndicatorId.premium.contains(id)).toSet();

/// Ön ayarın [tur] için değerleri.
///
/// "Dengeli" UYDURULMAZ: bugünkü varsayılanların ta kendisidir
/// (`kSignalThresholdDefault`, `kDefaultSchedule`,
/// `TechnicalAnalysisService.defaultEnabledFor`). Hiç dokunmamış kullanıcı
/// ekranı açınca "Dengeli"yi seçili görür; varsayılan değişirse Dengeli de
/// onunla değişir (`sinyal_on_ayar_test` kilitler).
SinyalOnAyarTanimi sinyalOnAyarTanimi(SinyalOnAyar a, AssetType tur) =>
    switch (a) {
      SinyalOnAyar.az => (
          esik: 85,
          siklik: SignalFrequency.daily,
          saatler: const [11],
          gostergeler: kSinyalCekirdekGostergeler,
        ),
      SinyalOnAyar.dengeli => (
          esik: kSignalThresholdDefault,
          siklik: kDefaultSchedule.frequency,
          saatler: kDefaultSchedule.hours,
          gostergeler:
              _premiumsuz(TechnicalAnalysisService.defaultEnabledFor(tur)),
        ),
      // Saatlik değil 2 saatte bir: saatlik (günde 9) çoğu kullanıcı için
      // gürültü; "çok" yine de Dengeli'nin 2,5 katı tur demek.
      SinyalOnAyar.cok => (
          esik: 50,
          siklik: SignalFrequency.every2h,
          saatler: null,
          gostergeler: _premiumsuz(IndicatorId.all),
        ),
    };

/// Kayıtlı tercihler hangi ön ayara BİREBİR uyuyor; hiçbirine uymuyorsa
/// `null` ("Özel").
///
/// Eksik tür değeri notifier'ların kendi varsayılanıyla okunur (ekranla
/// aynı `?? kSignalThresholdDefault` / `?? kDefaultSchedule` /
/// `?? defaultEnabledFor`). Premium göstergeler karşılaştırmaya girmez.
SinyalOnAyar? sinyalOnAyarEslesen({
  required Map<AssetType, int> esikler,
  required Map<AssetType, SignalSchedule> zamanlamalar,
  required Map<AssetType, Set<String>> gostergeler,
}) {
  bool uyar(SinyalOnAyar a) {
    for (final t in sinyalOnAyarTurleri) {
      final tanim = sinyalOnAyarTanimi(a, t);
      if ((esikler[t] ?? kSignalThresholdDefault) != tanim.esik) return false;
      final z = zamanlamalar[t] ?? kDefaultSchedule;
      if (z.frequency != tanim.siklik) return false;
      final saatler = tanim.saatler;
      if (saatler != null &&
          !listEquals([...z.hours]..sort(), [...saatler]..sort())) {
        return false;
      }
      final g = gostergeler[t] ?? TechnicalAnalysisService.defaultEnabledFor(t);
      if (!setEquals(_premiumsuz(g), tanim.gostergeler)) return false;
    }
    return true;
  }

  for (final a in SinyalOnAyar.values) {
    if (uyar(a)) return a;
  }
  return null;
}

/// Ekrandaki seçim: kayıtlı tercihlerden türetilir, ayrıca saklanmaz.
final sinyalOnAyarProvider = Provider<SinyalOnAyar?>((ref) {
  return sinyalOnAyarEslesen(
    esikler: ref.watch(signalThresholdProvider),
    zamanlamalar: ref.watch(signalScheduleProvider),
    gostergeler: ref.watch(indicatorPrefsProvider),
  );
});

/// Ön ayarı tüm türlere VAR OLAN notifier'lar üzerinden yazar.
///
/// Ön ayarın kapsamadığı hiçbir şey sıfırlanmaz: Premium göstergeler
/// korunur, periyodik sıklıkta kayıtlı saatler olduğu gibi kalır, "nötr
/// sinyaller" ve ana bildirim anahtarı bu işin dışında. Yerel yazmalar
/// `senkron: false` ile toplanır, sunucuya tür başına bir kez yazılır.
Future<void> sinyalOnAyariUygula(WidgetRef ref, SinyalOnAyar a) async {
  final esik = ref.read(signalThresholdProvider.notifier);
  final gosterge = ref.read(indicatorPrefsProvider.notifier);
  final zaman = ref.read(signalScheduleProvider.notifier);
  final turler = sinyalOnAyarTurleri;
  for (final t in turler) {
    final tanim = sinyalOnAyarTanimi(a, t);
    await esik.setForType(t, tanim.esik, senkron: false);
    final mevcut = ref.read(indicatorPrefsProvider)[t] ??
        TechnicalAnalysisService.defaultEnabledFor(t);
    await gosterge.setForType(
      t,
      {...tanim.gostergeler, ...mevcut.where(IndicatorId.premium.contains)},
      senkron: false,
    );
    await zaman.setFrequency(t, tanim.siklik, senkron: false);
    final saatler = tanim.saatler;
    if (saatler != null) await zaman.setHours(t, saatler, senkron: false);
  }
  await syncSignalPreferencesFor(ref, turler);
}
