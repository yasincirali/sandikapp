import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/yenileme_sikligi.dart';

/// Kullanıcı seçimli yenileme sıklığı (yasin 27 Kas 2026). Seçim bayrağa
/// göre çözülür; native taraf ve sunucu yalnız sunulan seçenekleri tanır.
void main() {
  group('yenilemeEtkin', () {
    test('hiç seçilmediyse en sık seçenek = bugünkü davranış', () {
      expect(yenilemeEtkin(0, canliEtkinlikYenilemeSecenekleri(dakikalik: true)), 1);
      expect(yenilemeEtkin(0, canliEtkinlikYenilemeSecenekleri(dakikalik: false)), 5);
    });

    test('bayrak kapanınca "Her dakika" 5 dk olur, sunulmayan değer yukarı oturur', () {
      final kapali = canliEtkinlikYenilemeSecenekleri(dakikalik: false);
      expect(yenilemeEtkin(1, kapali), 5);
      expect(yenilemeEtkin(15, kapali), 15);
      expect(yenilemeEtkin(30, canliEtkinlikYenilemeSecenekleri(dakikalik: true)), 15);
    });

    test('widget varsayılanı 30 dk, seçeneklerde', () {
      expect(widgetYenilemeSecenekleri, contains(widgetYenilemeVarsayilan));
      expect(widgetYenilemeVarsayilan, 30);
    });
  });

  group('sözleşme', () {
    final swift = File('ios/SandikWidget/SandikVarlikWidget.swift').readAsStringSync();
    final kt = File(
            'android/app/src/main/kotlin/com/sandik/app/SandikVarlikWidgetProvider.kt')
        .readAsStringSync();
    final ts = File('supabase/functions/_shared/canli_etkinlik_yenileme.ts')
        .readAsStringSync();
    final secenek = widgetYenilemeSecenekleri.join(', ');

    test('native widget aynı anahtarı ve aynı seçenekleri tanır', () {
      expect(swift, contains('"${HomeWidgetService.kWidgetYenilemeDk}"'));
      expect(swift, contains('[$secenek].contains(dk)'));
      expect(swift, contains('SandikWidgetFiyatServisi.seciliAralik'));
      expect(kt, contains('KEY_YENILEME_DK = "${HomeWidgetService.kWidgetYenilemeDk}"'));
      expect(kt, contains('listOf($secenek)'));
      expect(kt, contains('seciliAralikMs(context)'));
    });

    test('sunucu 1 dışındaki Canlı Etkinlik seçeneklerini tanır', () {
      final hepsi = {
        ...canliEtkinlikYenilemeSecenekleri(dakikalik: true),
        ...canliEtkinlikYenilemeSecenekleri(dakikalik: false),
      }.where((d) => d > 1).toList()
        ..sort();
      expect(ts, contains('new Set([${hepsi.join(', ')}])'));
    });
  });
}
