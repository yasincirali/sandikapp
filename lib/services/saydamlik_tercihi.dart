import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS Ayarlar › Erişilebilirlik › "Saydamlığı azalt" anahtarı.
///
/// Flutter bu ayarı `MediaQuery`'ye taşımıyor (yalnız `highContrast` geliyor;
/// iOS'ta o "Koyu renkler"e karşılık gelir). Cam yüzeyler (`SandikCam`)
/// `goz_alici` varsayılan açılınca mağaza kullanıcısına da gideceği için
/// HIG'in "saydamlığı azalt'a uy" maddesi platform kanalıyla bağlandı
/// (2026-10-12; önceden `TECHNICAL_DEBT.md`'de açıktı).
///
/// Kanal `AppDelegate.swift` içinde (`SaydamlikChannel`): `durum` ilk
/// değeri döner, ayar değişince yerel taraf `degisti(bool)` çağırır —
/// uygulama açıkken Ayarlar'dan dönen kullanıcı yeniden başlatmadan opak
/// zemini görür. Android'de ve testte kanal yoktur, değer `false` kalır.
class SaydamlikTercihi {
  SaydamlikTercihi._();
  static final SaydamlikTercihi instance = SaydamlikTercihi._();

  static const MethodChannel _kanal =
      MethodChannel('com.sandik.app/saydamlik');

  /// `true` → cam çizilmez, yüzey opak (yüksek kontrastla aynı yol).
  final ValueNotifier<bool> azalt = ValueNotifier<bool>(false);

  bool _basladi = false;

  /// Uygulama açılışında bir kez çağrılır; ikinci çağrı etkisizdir.
  Future<void> baslat() async {
    if (_basladi || defaultTargetPlatform != TargetPlatform.iOS) return;
    _basladi = true;
    _kanal.setMethodCallHandler((call) async {
      if (call.method == 'degisti' && call.arguments is bool) {
        azalt.value = call.arguments as bool;
      }
    });
    try {
      azalt.value = await _kanal.invokeMethod<bool>('durum') ?? false;
    } on MissingPluginException {
      // Eski yerel derleme ya da test kabuğu: kanal yok, cam varsayılanı
      // kalır. Hata değil, raporlanmaz.
    }
  }
}
