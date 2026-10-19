import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/hizli_eylemler.dart';
import 'package:portfoy_takip/services/sistem_eylemleri.dart';

/// Siri Kestirmeleri + Spotlight (2026-10-19): Swift'in bıraktığı metin
/// doğru hedefe çözülür, Spotlight'a yalnız kişinin kendi açık
/// pozisyonları yazılır, iki uç aynı adları kullanır.
Asset _lot(String id, String ticker,
        {String userId = 'u1', String name = '', AssetKind kind = AssetKind.buy}) =>
    Asset(
      id: id,
      userId: userId,
      name: name,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      currentPrice: 110,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

void main() {
  test('bekleyen eylem çözülür, bilinmeyen yok sayılır', () {
    final v = SistemEylemleri.cozumle('varlik:abc-123');
    expect(v, isA<SistemEylemiVarlik>());
    expect((v! as SistemEylemiVarlik).id, 'abc-123');

    for (final e in HizliEylem.values) {
      final k = SistemEylemleri.cozumle(e.name);
      expect(k, isA<SistemEylemiKisayol>());
      expect((k! as SistemEylemiKisayol).eylem, e);
    }

    expect(SistemEylemleri.cozumle('varlik:'), isNull);
    expect(SistemEylemleri.cozumle('bugun'), isNull);
    expect(SistemEylemleri.cozumle(''), isNull);
    expect(SistemEylemleri.cozumle(null), isNull);
  });

  test('Spotlight: kendi pozisyonu, varlık başına bir öğe, tutar yok', () {
    final ogeler = SistemEylemleri.spotlightOgeleri([
      _lot('a1', 'THYAO', name: 'Türk Hava Yolları'),
      _lot('a2', 'THYAO', name: 'Türk Hava Yolları'),
      _lot('b1', 'ASELS'),
      _lot('p1', 'GARAN', userId: 'ortak'),
    ], 'u1');

    expect(ogeler.map((o) => o['id']), ['a1', 'b1']);
    expect(ogeler.first['baslik'], 'Türk Hava Yolları');
    expect(ogeler.first['aciklama'], 'THYAO · Sandık');
    expect(ogeler.last['baslik'], 'ASELS');
    for (final o in ogeler) {
      expect(o.keys.toSet(), isNot(contains('tutar')));
      expect(o.values.join(' '), isNot(contains('110')));
    }
  });

  test('Swift ve Dart aynı kanal, önek ve eylem adlarını kullanır', () {
    final swift = File('ios/Runner/SistemEylemleri.swift').readAsStringSync();
    final dart = File('lib/services/sistem_eylemleri.dart').readAsStringSync();
    const kanal = 'com.sandik.app/sistem_eylemleri';
    expect(swift, contains('"$kanal"'));
    expect(dart, contains("'$kanal'"));
    expect(swift, contains('varlikOnek = "${SistemEylemleri.varlikOnek}"'));
    for (final e in HizliEylem.values) {
      expect(swift, contains('SistemEylemleri.birak("${e.name}")'));
    }
    // Swift dosyası Runner hedefinde derlenmeli; yoksa Siri sessizce yok olur.
    final proje =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(proje, contains('SistemEylemleri.swift in Sources'));
    expect(File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        contains('SistemEylemleri.register(registrar:'));
  });
}
