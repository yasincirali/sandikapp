import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

/// iOS kilit ekranı widget'ı (karar 4.1 / 4.3 / 4.4 / 4.5, 2026-09-30).
///
/// Swift bu makinede derlenmiyor; iki taraf arasındaki SÖZLEŞME (anahtar
/// adları, widget türü, paket kaydı) kaynak metinden kilitlenir — tek harf
/// farkı widget'ı sessizce "veri yok" hâline düşürür. Dart tarafının
/// yazdığı değerler kanal taklidiyle doğrulanır.
String _oku(String yol) =>
    File(yol).readAsStringSync().replaceAll('\r\n', '\n');

class _Kanal {
  final Map<String, Object?> yazilan = {};
  final List<Map<String, Object?>> yenilemeler = [];

  void kur() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      switch (call.method) {
        case 'saveWidgetData':
          final a = (call.arguments as Map).cast<String, Object?>();
          yazilan[a['id'] as String] = a['data'];
          return true;
        case 'updateWidget':
          yenilemeler
              .add((call.arguments as Map? ?? {}).cast<String, Object?>());
          return true;
        case 'setAppGroupId':
          return true;
      }
      return null;
    });
  }

  void kaldir() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
}

PortfolioState _durum() => PortfolioState(
      assets: [
        Asset(
          id: 'a1',
          userId: 'u1',
          name: 'Türk Hava Yolları',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 100,
          purchasePrice: 200,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 300,
          addedDate: DateTime(2026, 1, 1),
          kind: AssetKind.buy,
        ),
      ],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Kanal kanal;

  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => kanal = _Kanal()..kur());
  tearDown(() {
    kanal.kaldir();
    HomeWidgetService.instance.lockScreenAmounts = false;
  });

  group('Dart tarafı yazımı', () {
    test('bakiye gizliyken kilit ekranı yüzdeyi de göstermez (4.5)', () async {
      await HomeWidgetService.instance.update(_durum(), hideBalance: true);
      expect(kanal.yazilan['sandik_hidden'], isTrue);
      expect(kanal.yazilan['sandik_lock_pct'], '');
      expect(kanal.yazilan['sandik_change_pct_num'], 0.0);
    });

    test('görünürken: gizli değil; ölçüm yoksa yüzde uydurulmaz ("—")',
        () async {
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_hidden'], isFalse);
      expect(kanal.yazilan['sandik_lock_pct'], '—');
    });

    test('tutar izni Canlı Etkinlik tercihinden taşınır (4.4)', () async {
      HomeWidgetService.instance.lockScreenAmounts = false;
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_lock_amounts'], isFalse);
      HomeWidgetService.instance.lockScreenAmounts = true;
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_lock_amounts'], isTrue);
    });
  });

  group('Swift sözleşmesi', () {
    final dart = _oku('lib/services/home_widget_service.dart');
    final swift = _oku('ios/SandikWidget/SandikHomeWidget.swift');
    final paket = _oku('ios/SandikWidget/SandikWidgetBundle.swift');

    test('kilit ekranı anahtarları iki tarafta BİREBİR', () {
      for (final anahtar in const [
        'sandik_lock_amounts',
        'sandik_lock_pct',
        'sandik_change_pct_num',
        'sandik_hidden',
      ]) {
        expect(dart, contains("'$anahtar'"), reason: 'Dart: $anahtar');
        expect(swift, contains('"$anahtar"'), reason: 'Swift: $anahtar');
      }
    });

    test('widget türü Dart yenileme adıyla aynı ve pakette kayıtlı', () {
      expect(dart, contains("_iOSKilitWidgetName = 'SandikKilitWidget'"));
      expect(swift, contains('let kind = "SandikKilitWidget"'));
      expect(paket, contains('SandikKilitWidget()'));
    });

    test('yalnız kilit ekranı aileleri; 4.2 (tek satır) YOK', () {
      expect(
          swift,
          contains(
              '.supportedFamilies([.accessoryRectangular, .accessoryCircular])'));
      expect(swift, isNot(contains('.accessoryInline')),
          reason: 'Karar 4.2: tek satırlık widget yapılmadı');
    });

    test('Dinamik Ada: renkli yön halkası; gizli/ölçümsüz → logo (4.3)', () {
      final ada = _oku('ios/SandikWidget/SandikLiveActivity.swift');
      final bas = ada.indexOf('} compactLeading: {');
      final son = ada.indexOf('} compactTrailing: {');
      final kompakt = ada.substring(bas, son);
      expect(kompakt, contains('SandikYonHalkasi('));
      expect(kompakt, contains('SandikLogoMark('));
      final minimal = ada.substring(ada.indexOf('} minimal: {'));
      expect(minimal.substring(0, 1500), contains('SandikYonHalkasi('));
      // Sayı METİNDEN okunur (sunucu push'u yeni alan taşımaz) ve gizliyken
      // yok sayılır.
      expect(ada, contains('static func yuzde(state:'));
      expect(ada, contains('if state.isHidden { return nil }'));
    });
  });
}
