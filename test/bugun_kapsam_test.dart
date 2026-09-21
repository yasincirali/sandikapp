import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/utils/tr_iyelik.dart';

/// Bugün kartı kapsamı izler (2026-09-21, kullanıcı seçimi 3):
///   · Ortak / Birlikte görünümünde kişisel satırlar (hedef, aylık özet)
///     üretilmez; kapsamdan bağımsız satırlar kalır.
///   · Başlıktaki "Ayşe'nin bugünü" etiketi Türkçe ilgi ekini ünlü
///     uyumuyla alır.
void main() {
  group('BugunService.hesapla kisisel', () {
    // 2 Ekim 2026: ayın ilk üç günü → aylık özet girişi adayı.
    final now = DateTime(2026, 10, 2, 12);

    test('kişisel görünümde hedef ve aylık özet var', () {
      final v = BugunService.hesapla(
        karZararlar: const [1, -1],
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 5000,
        now: now,
      );
      expect(v.ikincil.whereType<HedefSatiri>(), isNotEmpty);
      expect(v.aylik, isNotNull);
    });

    test('kapsam görünümünde hedef ve aylık özet yok, diğerleri kalır', () {
      final v = BugunService.hesapla(
        karZararlar: const [1, -1],
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 5000,
        now: now,
        reel: const ReelGetiriSatiri(nominal: 40, inflation: 30),
        haftalikGetiriPct: 1.2,
        kisisel: false,
      );
      expect(v.ikincil.whereType<HedefSatiri>(), isEmpty,
          reason: 'ortağın hedefi sunucuda yok; uydurulmaz');
      expect(v.aylik, isNull, reason: 'aylık özet kendi recap ekranına gider');
      expect(v.ikincil.whereType<YesilOranSatiri>(), isNotEmpty);
      expect(v.reel, isNotNull);
      expect(v.olay, isNotNull, reason: 'ulusal takvim herkese');
    });

    test('kapsam görünümünde hedef 0 olsa bile "hedef belirle" çağrısı yok',
        () {
      final v = BugunService.hesapla(
        karZararlar: const [],
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, 21, 12),
        kisisel: false,
      );
      expect(v.ikincil, isEmpty);
    });
  });

  group('trIyelik', () {
    test('ünlü uyumu ve kaynaştırma', () {
      expect(trIyelik('Ayşe'), "Ayşe'nin");
      expect(trIyelik('Ali'), "Ali'nin");
      expect(trIyelik('Ebru'), "Ebru'nun");
      expect(trIyelik('Banu'), "Banu'nun");
      expect(trIyelik('Ahmet'), "Ahmet'in");
      expect(trIyelik('Yasin'), "Yasin'in");
      expect(trIyelik('Oğuz'), "Oğuz'un");
      expect(trIyelik('Gül'), "Gül'ün");
      expect(trIyelik('Ayla'), "Ayla'nın");
      expect(trIyelik('Kaan'), "Kaan'ın");
    });

    test('büyük I Türkçe okunur; ünlüsüz ad ince-düz ek alır', () {
      expect(trIyelik('IŞIK'), "IŞIK'ın");
      expect(trIyelik('XYZ'), "XYZ'in");
      expect(trIyelik('  '), '');
    });

    test('kart etiketi Türkçe büyük harf: noktalı i korunur', () {
      expect(trBuyukHarf("Ayşe'nin bugünü"), "AYŞE'NİN BUGÜNÜ");
      expect(trBuyukHarf('Birlikte'), 'BİRLİKTE');
      expect(trBuyukHarf('Işık'), 'IŞIK');
    });
  });
}
