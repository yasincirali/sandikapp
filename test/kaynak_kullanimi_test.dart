import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';

import 'helpers/kaynak.dart';

/// Kaynak kullanımı denetiminin (2026-10-12) kilitleri.
///
///   1. Mum önbelleği büyümez: seans boyunca her dakika yeni pencere
///      istense de kayıt sayısı [MumVerisi.azamiKayit]'ı aşmaz (önce 480
///      dakikada +48 MB ölçülmüştü).
///   2. Widget aynı içeriği iki kez yazmaz ve yenilemez; ama ekranda görünen
///      her alan (saat dahil) değişince yazılır — tazelik kaybı yok.
///   3. iOS'ta sparkline PNG'si çizilmez (iOS widget'ı okumuyor), sayı
///      dizisi yine yazılır.
///   4. Bugün kartındaki canlı nokta sonsuz `repeat()` ile dönmez.

Asset _lot() => Asset(
      id: 'THYAO-1',
      userId: 'u1',
      name: 'THY',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: AssetKind.buy,
    );

PortfolioState _state() => PortfolioState(
      assets: [_lot()],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

Map<int, double> _seri(int n) {
  final base = DateTime(2026, 8, 11, 10).millisecondsSinceEpoch;
  return {
    for (var i = 0; i < n; i++) base + i * 5 * 60 * 1000: 1000.0 + i * 37.5,
  };
}

class _Kanal {
  final Map<String, Object?> kayit = {};
  final List<String> yazilan = [];
  int yenileme = 0;

  void kur() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      if (call.method == 'saveWidgetData') {
        final a = (call.arguments as Map).cast<String, Object?>();
        kayit[a['id'] as String] = a['data'];
        yazilan.add(a['id'] as String);
      } else if (call.method == 'updateWidget') {
        yenileme++;
      }
      return true;
    });
  }

  void sifirla() {
    yazilan.clear();
    yenileme = 0;
  }

  void kaldir() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mum önbelleği', () {
    tearDown(() {
      MumVerisi.testCekici = null;
      MumVerisi.instance.onbellegiTemizle();
    });

    test('seans boyu dakikalık pencereler önbelleği büyütmez', () async {
      var cekim = 0;
      MumVerisi.testCekici = (a, aralik, bas, son) async {
        cekim++;
        return [
          for (var i = 0; i < 10; i++)
            OhlcBar(
                t: bas.millisecondsSinceEpoch + i * 60000,
                acilis: 100,
                enYuksek: 101,
                enDusuk: 99,
                kapanis: 100.5),
        ];
      };
      final bas = DateTime(2026, 10, 12, 10);
      for (var dk = 0; dk < 120; dk++) {
        await MumVerisi.instance.mumlar(
            a: _lot(),
            aralik: MumAraligi.dk1,
            bas: bas,
            son: bas.add(Duration(minutes: 480 + dk)),
            canliBirim: 100);
      }
      expect(cekim, 120);
      expect(MumVerisi.instance.kayitSayisi,
          lessThanOrEqualTo(MumVerisi.azamiKayit));
    });

    test('taze kayıt yine önbellekten sunulur (davranış aynı)', () async {
      var cekim = 0;
      MumVerisi.testCekici = (a, aralik, bas, son) async {
        cekim++;
        return [
          OhlcBar(
              t: bas.millisecondsSinceEpoch,
              acilis: 1,
              enYuksek: 1,
              enDusuk: 1,
              kapanis: 1),
        ];
      };
      final bas = DateTime(2026, 10, 12, 10);
      final son = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await MumVerisi.instance.mumlar(
            a: _lot(),
            aralik: MumAraligi.gun1,
            bas: bas,
            son: son,
            canliBirim: 1);
      }
      expect(cekim, 1);
    });

    test('bellek baskısında bırakılır', () async {
      MumVerisi.testCekici = (a, aralik, bas, son) async => [
            OhlcBar(
                t: bas.millisecondsSinceEpoch,
                acilis: 1,
                enYuksek: 1,
                enDusuk: 1,
                kapanis: 1),
          ];
      await MumVerisi.instance.mumlar(
          a: _lot(),
          aralik: MumAraligi.gun1,
          bas: DateTime(2026),
          son: DateTime.now(),
          canliBirim: 1);
      expect(MumVerisi.instance.kayitSayisi, 1);
      MumVerisi.instance.bellegiBirak();
      expect(MumVerisi.instance.kayitSayisi, 0);
    });
  });

  group('widget yazımı', () {
    late _Kanal kanal;
    late Directory tmp;

    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
    });

    setUp(() async {
      kanal = _Kanal()..kur();
      tmp = Directory.systemTemp.createTempSync('kaynak_kullanimi');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (call) async => tmp.path);
      // Önceki testin kıyas belleği bu testi etkilemesin.
      await HomeWidgetService.instance.clear();
      kanal.sifirla();
    });

    tearDown(() {
      HomeWidgetService.pngCizilsinMi = () => !Platform.isIOS;
      kanal.kaldir();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('aynı içerik ikinci kez yazılmaz ve widget yenilenmez', () async {
      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: _seri(24));
      expect(kanal.yazilan, isNotEmpty);
      expect(kanal.yenileme, greaterThan(0));

      kanal.sifirla();
      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: _seri(24));
      // Dakika iki çağrı arasında dönerse yalnızca saat/tarih/seans durumu
      // yazılabilir — rakam alanları ASLA yeniden yazılmaz.
      expect(
          kanal.yazilan.toSet().difference(const {
            'sandik_updated_at',
            'sandik_date',
            'sandik_market_open',
          }),
          isEmpty);
      if (kanal.yazilan.isEmpty) expect(kanal.yenileme, 0);
    });

    test('rakam değişince yalnız değişen alanlar yazılır ve yenilenir',
        () async {
      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: _seri(24));
      kanal.sifirla();
      final yeni = _state();
      await HomeWidgetService.instance.update(
        PortfolioState(
          assets: [
            Asset(
              id: 'THYAO-1',
              userId: 'u1',
              name: 'THY',
              ticker: 'THYAO.IS',
              type: AssetType.hisse,
              quantity: 10,
              purchasePrice: 100,
              currency: 'TRY',
              notes: '',
              isManualPrice: false,
              currentPrice: 135,
              addedDate: DateTime(2026, 1, 1),
              kind: AssetKind.buy,
            ),
          ],
          usdTry: yeni.usdTry,
          eurTry: yeni.eurTry,
          gbpTry: yeni.gbpTry,
        ),
        hideBalance: false,
        intraday: _seri(24),
      );
      expect(kanal.yazilan, contains('sandik_total'));
      expect(kanal.kayit['sandik_total'], isNot(contains('1.200')));
      expect(kanal.yenileme, greaterThan(0));
    });

    test('gizlemeye geçiş her zaman yazılır', () async {
      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: _seri(24));
      kanal.sifirla();
      await HomeWidgetService.instance
          .update(_state(), hideBalance: true, intraday: const {});
      expect(kanal.kayit['sandik_total'], '••••••');
      expect(kanal.kayit['sandik_spark_series'], '');
      expect(kanal.yenileme, greaterThan(0));
    });

    test('iOS: PNG çizilmez, sayı dizisi yazılır', () async {
      HomeWidgetService.pngCizilsinMi = () => false;
      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: _seri(24));
      expect(kanal.yazilan, isNot(contains('sandik_sparkline')));
      expect(kanal.kayit['sandik_spark_points'], 24);
      expect((kanal.kayit['sandik_spark_series'] as String).split(','),
          hasLength(24));
      expect(File('${tmp.path}/sandik_widget_spark.png').existsSync(), isFalse);
    });
  });

  test('canlı nokta sonsuz döngüde değil', () {
    final kaynak = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    final nokta = kaynak.substring(
        kaynak.indexOf('class _CanliNoktaState'),
        kaynak.indexOf('class _HukumSatiri'));
    expect(nokta.contains('.repeat('), isFalse,
        reason: 'Sürekli nabız Ana ekranı seans boyunca hiç uyutmuyordu');
    expect(nokta.contains('nefesSayisi'), isTrue);
  });
}
