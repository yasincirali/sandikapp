import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/widgets/zirve_karti.dart';

/// Performans'taki küçük Zirve kartı — üç durum ve dokunuş.
///
/// Sunucu yerine sabit yükleyici geçilir; kart yalnızca ne gösterdiğiyle
/// ölçülür: dolu (cümle + şerit), boş (havuz ilerlemesi, "yakında" yok),
/// dokununca ekran açılır.
void main() {
  const birinci = TopGainerAllocation(
    rank: 1,
    roiPct: 2.70,
    allocation: {'altin': 55.7, 'kripto': 17.9, 'hisse': 12.9, 'doviz': 7.6, 'fon': 5.9},
  );

  Future<int> pump(
    WidgetTester tester, {
    required List<TopGainerAllocation> satirlar,
    int? havuz,
    ZirveDonem donem = ZirveDonem.ay,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var acildi = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZirveKarti(
              donem: donem,
              onAc: () => acildi++,
              yukleyici: (_) async => satirlar,
              havuzYukleyici: (_) async => havuz,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return acildi;
  }

  testWidgets('dolu: cümle, birincinin şeridi, çağrı satırı', (tester) async {
    await pump(tester, satirlar: const [birinci]);
    expect(find.text('Zirvedeki Portföyler'), findsOneWidget);
    expect(find.text('Bu ay zirvedeki portföy %2,7 kazandı.'), findsOneWidget);
    // Şerit altında en fazla üç tür yazılır (kart dar).
    expect(find.textContaining('Altın %56'), findsOneWidget);
    expect(find.textContaining('Kripto %18'), findsOneWidget);
    expect(find.textContaining('Hisse %13'), findsOneWidget);
    expect(find.textContaining('Döviz'), findsNothing);
    expect(find.textContaining('Kendi yerini'), findsOneWidget);
  });

  testWidgets('boş: havuz sayısı ve eşik, "yakında" yok', (tester) async {
    await pump(tester, satirlar: const [], havuz: 4);
    expect(
        find.text('Havuz oluşuyor: 4 portföy var, 8 olunca zirve belli olur.'),
        findsOneWidget);
    expect(find.byType(ZirveHavuzCubugu), findsOneWidget);
    expect(find.textContaining('akında'), findsNothing);
  });

  testWidgets('boş, havuz sayısı bilinmiyor: sayı uydurulmaz', (tester) async {
    await pump(tester, satirlar: const [], havuz: null);
    expect(find.textContaining('Havuz oluşuyor; 8 portföy olunca'),
        findsOneWidget);
    expect(find.byType(ZirveHavuzCubugu), findsNothing);
  });

  testWidgets('dönem alt başlıkta ve cümlede', (tester) async {
    await pump(tester, satirlar: const [birinci], donem: ZirveDonem.yil);
    expect(find.textContaining('yıllık · anonim'), findsOneWidget);
    expect(find.text('Bu yıl zirvedeki portföy %2,7 kazandı.'), findsOneWidget);
  });

  testWidgets('karta dokununca onAc', (tester) async {
    var acildi = 0;
    tester.view.physicalSize = const Size(390 * 3, 500 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ZirveKarti(
            donem: ZirveDonem.ay,
            onAc: () => acildi++,
            yukleyici: (_) async => const [birinci],
            havuzYukleyici: (_) async => 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zirvedeki Portföyler'));
    await tester.pumpAndSettle();
    expect(acildi, 1);
  });
}
