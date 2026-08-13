import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

/// Ana ekran widget'ı — gün içi sparkline üretimi.
///
/// Grafik Flutter tarafında `dart:ui` ile PNG'ye rasterize edilir çünkü
/// Android `RemoteViews` custom view çizemez. Native taraf yalnızca hazır
/// görseli gösterir.
///
/// Burada kilitlenen davranışlar:
///   1. Yeterli veri varsa GERÇEK bir PNG dosyası üretilir.
///   2. İki noktadan az veri varsa çizim YAPILMAZ — tek noktalı "çizgi"
///      kullanıcıya düz/boş bir grafik gösterirdi.
///   3. Nokta sayısı native tarafa bildirilir (o, alanı gizleyip
///      göstermeye buna bakarak karar verir).
///   4. Bakiye gizliyken grafik de çizilmez (gizlilik değişmezi).

class _FakeHomeWidgetChannel {
  final Map<String, Object?> saved = {};

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async {
        if (call.method == 'saveWidgetData') {
          final args = (call.arguments as Map).cast<String, Object?>();
          saved[args['id'] as String] = args['data'];
        }
        return true;
      },
    );
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  }
}

/// `path_provider` testte native yol döndüremez — geçici dizine yönlendir.
void _installPathProvider(Directory dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => dir.path,
  );
}

PortfolioState _state() => PortfolioState(
      assets: [
        Asset(
          id: 'a1',
          userId: 'u1',
          name: 'Test',
          ticker: 'TEST',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 120,
          addedDate: DateTime(2026, 1, 1),
          kind: AssetKind.buy,
        ),
      ],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

/// Gün içi seri — 5 dakikalık slotlar.
Map<int, double> _series(int points) {
  final base = DateTime(2026, 8, 11, 10).millisecondsSinceEpoch;
  return {
    for (var i = 0; i < points; i++)
      base + i * 5 * 60 * 1000: 1000.0 + i * 37.5,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeHomeWidgetChannel channel;
  late Directory tmp;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  setUp(() {
    channel = _FakeHomeWidgetChannel()..install();
    tmp = Directory.systemTemp.createTempSync('sandik_widget_test');
    _installPathProvider(tmp);
  });

  tearDown(() {
    channel.remove();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('sparkline üretimi', () {
    test('yeterli veri varsa GERÇEK bir PNG yazılır', () async {
      await HomeWidgetService.instance.update(
        _state(),
        hideBalance: false,
        intraday: _series(24),
      );

      final path = channel.saved['sandik_sparkline'] as String?;
      expect(path, isNotNull, reason: 'Grafik yolu native tarafa yazılmalı');

      final file = File(path!);
      expect(file.existsSync(), isTrue, reason: 'PNG diske inmeli');

      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(100),
          reason: 'Boş/bozuk dosya widget\'ta kırık görsel olur');
      // PNG imzası: 89 50 4E 47
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
          reason: 'Dosya gerçekten PNG olmalı');

      expect(channel.saved['sandik_spark_points'], 24);
    });

    test('tek nokta varsa çizim YAPILMAZ', () async {
      await HomeWidgetService.instance.update(
        _state(),
        hideBalance: false,
        intraday: _series(1),
      );

      expect(channel.saved['sandik_sparkline'], isNull,
          reason: 'Tek nokta çizgi oluşturmaz; native taraf alanı gizlemeli');
      expect(channel.saved['sandik_spark_points'], 1);
    });

    test('hiç veri yoksa çizim YAPILMAZ', () async {
      await HomeWidgetService.instance.update(
        _state(),
        hideBalance: false,
        intraday: const {},
      );

      expect(channel.saved['sandik_sparkline'], isNull);
      expect(channel.saved['sandik_spark_points'], 0);
    });

    test('düz seri (min == max) çökmeden çizilir', () async {
      // Sıfıra bölme riski: tüm değerler aynıysa span 0 olur.
      final flat = {
        for (var i = 0; i < 6; i++)
          DateTime(2026, 8, 11, 10).millisecondsSinceEpoch + i * 300000: 500.0,
      };

      await HomeWidgetService.instance
          .update(_state(), hideBalance: false, intraday: flat);

      final path = channel.saved['sandik_sparkline'] as String?;
      expect(path, isNotNull, reason: 'Düz seri de geçerli bir grafiktir');
      expect(File(path!).existsSync(), isTrue);
    });
  });

  group('gizlilik', () {
    test('bakiye gizliyken grafik de çizilmez', () async {
      await HomeWidgetService.instance.update(
        _state(),
        hideBalance: true,
        intraday: _series(24),
      );

      expect(channel.saved['sandik_sparkline'], isNull,
          reason: 'Grafiğin şekli de portföy bilgisidir — gizliyken çizilmez');
    });
  });
}
