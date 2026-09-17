import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ölçek hafızası ve son birincil fiyat SOĞUK AÇILIŞTA da bilinmeli.
///
/// Kullanıcı (2026-09-17): "Bazen doğru gösteriyordu ancak bazen zıplamalar
/// oluyordu, ihtimalleri de bitirmen gerek." İlk sürümde iki bellek de
/// oturum içiydi: uygulama yeniden açıldığında birincil kaynak (truncgil)
/// bir tur cevap vermezse oran bilinmiyor, yedek HAM ölçekte (%1-2 farklı)
/// gösteriliyordu. Bu test iki belleğin diske yazılıp geri okunduğunu ve
/// bayat birincil fiyatın (6 saat) geri okunMAdığını kilitler.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OlcekHafizasi.instance.temizle();
    PriceService.instance.sonBilinenFiyatlariTemizle();
  });

  group('OlcekHafizasi kalıcı', () {
    test('öğrenilen oran diskten geri gelir', () async {
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6212.28, yedek: 6328.70);
      // `ogren` diske asenkron yazar — bir mikro-görev turu yeter.
      await Future<void>.delayed(Duration.zero);

      // "Yeniden başlat": RAM sıfır, disk duruyor.
      OlcekHafizasi.instance.temizle();
      expect(OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot),
          isNull);

      await OlcekHafizasi.instance.yukle();
      expect(
        OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot),
        closeTo(6212.28 / 6328.70, 1e-9),
        reason: 'soğuk açılışta oran bilinmiyorsa yedek ham kalır — zıplama',
      );
    });

    test('bu oturumda öğrenilen oran diskteki eskiyi EZER', () async {
      SharedPreferences.setMockInitialValues({
        'olcek_hafizasi_v1': jsonEncode({'ALTIN_GRAM|spot': 0.90}),
      });
      OlcekHafizasi.instance.ogren('ALTIN_GRAM', FiyatKaynagiEtiketi.spot,
          birincil: 6212.28, yedek: 6328.70);
      await OlcekHafizasi.instance.yukle();
      expect(
        OlcekHafizasi.instance.oran('ALTIN_GRAM', FiyatKaynagiEtiketi.spot),
        closeTo(6212.28 / 6328.70, 1e-9),
        reason: 'taze ölçüm bayat kayıttan üstündür',
      );
    });
  });

  group('son birincil fiyat kalıcı', () {
    test('taze kayıt geri okunur ve yurt içi olarak etiketlenir', () async {
      SharedPreferences.setMockInitialValues({
        'son_birincil_fiyat_v1': jsonEncode({
          'ALTIN_GRAM': {
            'p': 6212.28,
            'ts': DateTime.now()
                .subtract(const Duration(minutes: 30))
                .millisecondsSinceEpoch,
          },
        }),
      });
      await PriceService.instance.birincilHafizayiYukle();
      expect(PriceService.instance.sonBilinenFiyat('ALTIN_GRAM'), 6212.28);
      expect(PriceService.instance.sonKaynak('ALTIN_GRAM'),
          FiyatKaynagiEtiketi.yurtIci,
          reason: 'ilk yedek geçişi oranı bu etiket üzerinden öğrenir');
    });

    test('6 saatten eski kayıt geri okunMAZ', () async {
      // Dünkü fiyattan öğrenilen oran bir günlük gerçek hareketi ölçek
      // sanıp kalıcılaştırırdı — bayat kayıt, kayıt yokluğundan kötü.
      SharedPreferences.setMockInitialValues({
        'son_birincil_fiyat_v1': jsonEncode({
          'ALTIN_GRAM': {
            'p': 6100.0,
            'ts': DateTime.now()
                .subtract(const Duration(hours: 7))
                .millisecondsSinceEpoch,
          },
        }),
      });
      await PriceService.instance.birincilHafizayiYukle();
      expect(PriceService.instance.sonBilinenFiyat('ALTIN_GRAM'), isNull);
      expect(PriceService.instance.sonKaynak('ALTIN_GRAM'), isNull);
    });
  });

  group('fetchQuotes kaynak kodu sözleşmesi', () {
    final src = File('lib/services/price_service.dart').readAsStringSync();

    test('iki bellek ağa çıkmadan ÖNCE yüklenir', () {
      final yukleme = src.indexOf('OlcekHafizasi.instance.yukle()');
      final ag = src.indexOf('_fetchTruncgilData().catchError');
      expect(yukleme, greaterThan(0));
      expect(yukleme, lessThan(ag),
          reason: 'yedek yol oranı bilmeden koşarsa soğuk açılışta zıplar');
    });

    test('EUR/GBP için uydurma çapraz kur YOK', () {
      expect(src.contains('usdTry * 1.1'), isFalse);
      expect(src.contains('usdTry * 1.28'), isFalse);
    });
  });
}
