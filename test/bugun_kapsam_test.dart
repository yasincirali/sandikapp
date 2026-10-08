import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/utils/tr_iyelik.dart';

/// Bugün kartı kapsamı izler (2026-09-21, kullanıcı seçimi 3):
///   · Hedef kapsamın KENDİ hedefidir (2026-09-30, `kapsamHedefiProvider`);
///     Ortak / Birlikte görünümünde de satır kalır.
///   · Başlıktaki "Ayşe'nin bugünü" etiketi Türkçe ilgi ekini ünlü
///     uyumuyla alır.
void main() {
  group('BugunService.hesapla kapsam', () {
    test('hedef verilen kapsamın hedefi, reel kalır', () {
      final v = BugunService.hesapla(
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 5000,
        now: DateTime(2026, 10, 2, 12),
        reel: const ReelGetiriSatiri(nominal: 40, inflation: 30),
      );
      // Kart Birlikte'ye geçince satır kaybolmamalı.
      expect(v.hedef.hedefTRY, 5000);
      expect(v.reel, isNotNull);
    });

    test('hedef 0 ise "hedef belirle" çağrısı görünür', () {
      final v = BugunService.hesapla(
        toplamDeger: 1000,
        ozet: null,
        hedefTRY: 0,
        now: DateTime(2026, 9, 21, 12),
      );
      expect(v.hedef.belirlenmedi, isTrue);
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
