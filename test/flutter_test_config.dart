// `flutter test` bu dosyayı test/ altındaki HER test için otomatik yükler.
import 'dart:async';

import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/yukleme_isareti.dart';

/// Yükleme işaretinin sonsuz sayacı testlerde kapalı (2026-09-24).
///
/// `pumpAndSettle` ekranda dönen bir sayaç varken asla bitmez; 35 test
/// dosyası ona dayanıyor. Eski GIF widget testinde hiç çözülmediği için
/// sessizce hareketsizdi — bu ayar aynı davranışı açıkça verir. Sayacı
/// sınayan test bayrağı kendi içinde geçici olarak açar.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  YuklemeIsareti.hareketli = false;
  // 2026-10-04'te AÇIK doğan bayraklar testlerde varsayılan olarak KAPALI:
  // o güne kadarki testler "bayrak kapalı = eski davranış" diye yazıldı;
  // açık dal her testte `RemoteConfigService.testAcik` ile ayrıca sınanır.
  // Üretim varsayılanı `remote_config_defaults_test`'te kilitli (true).
  RemoteConfigService.testKapali = {
    'ilk_varlik_kolay',
    'karsilama_tanitimi',
    'seviye_anketi',
    'bugun_karti_kiyas',
    'varlik_islem_cubugu',
    'tek_ortak_secici',
    'tek_kiyas_yuzeyi',
    'siralama_tek_sayfa',
    'performans_ayar_sade',
    'yaris_duello_arena',
    'tek_onay_kutusu',
    'ortak_secimi_tasi',
    'yasal_onay_kaydi',
    'yasal_kapi_en_yeni',
    'zorunlu_okuma',
  };
  await testMain();
}
