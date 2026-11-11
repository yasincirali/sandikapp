import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/seri_disk_depo.dart';
import 'package:portfoy_takip/services/sparkline_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/asset_sparkline.dart';

/// Soğuk açılışta mini çizgi diskteki son iyi kopyadan anında, ağdan arka
/// planda tazelenir (2026-11-11; karar kaydı `SparklineService._ilkYukleme`).
///
/// Ağ yok: gerçek çekim kapısı (`HistoryService.seriCek`) koşar, ham çekim
/// `seriCekici` kancasından, disk geçici klasörden. Soğuk açılış =
/// `HistoryService.clearCache()` + `SparklineService.clear()` (bellek boş,
/// disk dolu).
void main() {
  late Directory gecici;
  late SeriDiskDepo depo;
  Completer<List<(int, double)>>? ag;
  var agCagrisi = 0;

  final simdi = DateTime.now();
  List<(int, double)> seri(List<double> degerler) => [
        for (var i = 0; i < degerler.length; i++)
          (
            simdi
                .subtract(Duration(days: degerler.length - i))
                .millisecondsSinceEpoch,
            degerler[i],
          ),
      ];

  final Asset varlik = SparklineService.takipAnahtari(WatchlistItem(
    id: '1',
    userId: 'u1',
    ticker: 'SISE.IS',
    name: 'Şişe Cam',
    type: AssetType.hisse,
    currency: 'TRY',
    addedAt: DateTime(2026, 9, 1),
  ));
  const anahtar = 'SISE.IS_1mo';

  setUp(() {
    HistoryService.clearCache();
    SparklineService.instance.clear();
    SparklineService.instance.debugCekici = null;
    gecici = Directory.systemTemp.createTempSync('sparkline_disk');
    depo = SeriDiskDepo(kokDizin: () async => gecici);
    HistoryService.kaliciDepo = depo;
    agCagrisi = 0;
    ag = Completer();
    HistoryService.seriCekici = (sym, range, interval) {
      agCagrisi++;
      return ag!.future;
    };
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.kaliciDepo = null;
    HistoryService.clearCache();
    SparklineService.instance.clear();
    try {
      gecici.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget sar(Widget w) => MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: Scaffold(body: Center(child: w)),
      );

  /// Disk okuması gerçek G/Ç: her adımı test saatinin dışında tamamlanır,
  /// devamı ise sahte saatte; birkaç tur ikisini sırayla ilerletir.
  Future<void> gercekGc(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  List<double>? cizilen(WidgetTester tester) {
    final f = find.descendant(
        of: find.byType(AssetSparkline), matching: find.byType(CustomPaint));
    if (f.evaluate().isEmpty) return null;
    final painter = tester.widget<CustomPaint>(f.first).painter;
    return painter == null ? null : (painter as dynamic).series as List<double>;
  }

  test('disk dolu + ağ yavaş: seri ağ gelmeden diskten döner', () async {
    await depo.yaz(anahtar, seri([10, 12, 11, 14]));
    final s = await SparklineService.instance
        .seriesFor(varlik)
        .timeout(const Duration(seconds: 2));
    expect(s, SparklineService.normalize(seri([10, 12, 11, 14])));
    expect(SparklineService.instance.peek(varlik), s,
        reason: 'satır yeniden kurulunca ilk karede çizebilmeli');
    expect(agCagrisi, 1, reason: 'ağ arka planda bir kez sorulur');
  });

  testWidgets('disk dolu + ağ yavaş: çizgi ağ yanıtından önce çizilir; '
      'tazelenen veri farklıysa satır güncellenir', (tester) async {
    await tester.runAsync(() => depo.yaz(anahtar, seri([10, 12, 11, 14])));
    await tester.pumpWidget(
        sar(AssetSparkline(asset: varlik, isPositive: true)));
    await gercekGc(tester);
    await tester.pumpAndSettle();
    expect(ag!.isCompleted, isFalse);
    expect(cizilen(tester), SparklineService.normalize(seri([10, 12, 11, 14])));

    // Ağ farklı seri getirir → aynı satır yeni eğriyi çizer, diske de yazılır.
    ag!.complete(seri([20, 18, 19, 15, 16]));
    await gercekGc(tester);
    await tester.pump();
    expect(cizilen(tester),
        SparklineService.normalize(seri([20, 18, 19, 15, 16])));
    final diskte = await tester.runAsync(() => depo.oku(anahtar));
    expect(diskte!.map((p) => p.$2), [20, 18, 19, 15, 16]);
  });

  test('ağ hatası: disk kopyası önbellekte kalır', () async {
    await depo.yaz(anahtar, seri([10, 12, 11, 14]));
    final ilk = await SparklineService.instance.seriesFor(varlik);
    var bildirim = 0;
    void dinle() => bildirim++;
    SparklineService.instance.tazeleme.addListener(dinle);
    addTearDown(() => SparklineService.instance.tazeleme.removeListener(dinle));
    ag!.completeError(const SocketException('yok'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(identical(SparklineService.instance.peek(varlik), ilk), isTrue);
    expect(bildirim, 0, reason: 'değişmeyen seri satırı yeniden çizdirmez');
    expect((await depo.oku(anahtar))!.map((p) => p.$2), [10, 12, 11, 14]);
  });

  test('diskte yok: eski davranış, seri ağdan gelir', () async {
    final bekleyen = SparklineService.instance.seriesFor(varlik);
    var bitti = false;
    unawaited(bekleyen.then((_) => bitti = true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bitti, isFalse, reason: 'disk boşken ağ beklenir');
    ag!.complete(seri([5, 6, 7]));
    expect(await bekleyen, SparklineService.normalize(seri([5, 6, 7])));
    expect(agCagrisi, 1);
  });
}
