import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/maliyet_kesisimi.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';

import 'helpers/kaynak.dart';

/// Grafikte maliyetini kestiğin gün (2026-11-11): titreşim + kısa söz.

List<FlSpot> _seri(List<double> y) =>
    [for (var i = 0; i < y.length; i++) FlSpot(i.toDouble(), y[i])];

void main() {
  group('maliyetKesisimleri', () {
    test('yukarı ve aşağı kesişim: yeni taraftaki ilk nokta', () {
      final k = maliyetKesisimleri(
        _seri([90, 95, 105, 110, 108, 107, 106, 105, 104, 103, 99, 97]),
        maliyet: 100,
        acik: true,
      );
      expect(k, {2.0: MaliyetKesisimi.yukari, 10.0: MaliyetKesisimi.asagi});
    });

    test('maliyete eşit nokta taraf sayılmaz (sahte kesişim yok)', () {
      final k = maliyetKesisimleri(_seri([105, 100, 106, 100, 104]),
          maliyet: 100, acik: true);
      expect(k, isEmpty);
    });

    test('gürültü sınırı: 7 gün içindeki ikinci kesişim atlanır', () {
      final k = maliyetKesisimleri(
          _seri([95, 105, 95, 105, 95, 95, 95, 95, 95, 95, 105]),
          maliyet: 100,
          acik: true);
      // 1: yukarı (rapor), 2/3/4: atlanır (<7 gün), 10: yukarı (9 gün sonra).
      expect(k, {1.0: MaliyetKesisimi.yukari, 10.0: MaliyetKesisimi.yukari});
    });

    test('maliyet yoksa ya da sıfırsa boş', () {
      final s = _seri([90, 110]);
      expect(maliyetKesisimleri(s, maliyet: null, acik: true), isEmpty);
      expect(maliyetKesisimleri(s, maliyet: 0, acik: true), isEmpty);
    });

    test('kapalı pozisyonda boş', () {
      expect(maliyetKesisimleri(_seri([90, 110]), maliyet: 100, acik: false),
          isEmpty);
    });
  });

  test('varlık grafiği: kesişimler titreşim noktalarına eklenir', () {
    final src = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    final i = src.indexOf('titresimNoktalari: imlecAcik');
    expect(i, greaterThan(0));
    final blok = src.substring(i, src.indexOf(': const {}', i));
    expect(blok, contains('donemUclariX'));
    expect(blok, contains('maliyetKesisim.keys'));
    expect(src, contains('maliyetKesisimleri(activeSeg.spots'));
  });

  group('fiyat bloğunda kesişim sözü', () {
    Future<void> ciz(WidgetTester t, ValueNotifier<String?> not,
            {bool azalt = false}) =>
        t.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: azalt),
            child: Scaffold(
              body: VarlikFiyatBlogu(
                etiket: 'Güncel fiyat',
                fiyat: '₺100',
                fiyatRengi: Colors.black,
                degisim: (metin: '+%1', renk: Colors.black),
                imlec: ValueNotifier(('₺101', '3 Mar 2026')),
                imlecNotu: not,
              ),
            ),
          ),
        ));

    testWidgets('kesişim gününde söz görünür, başka günde yok', (t) async {
      final not = ValueNotifier<String?>(null);
      await ciz(t, not);
      expect(find.textContaining('Maliyetinin'), findsNothing);
      not.value = 'Maliyetinin üstüne çıktı';
      await t.pumpAndSettle();
      expect(find.text(' · Maliyetinin üstüne çıktı'), findsOneWidget);
      expect(find.text('3 Mar 2026'), findsOneWidget);
    });

    testWidgets('hareketi azaltta anında görünür', (t) async {
      final not = ValueNotifier<String?>(null);
      await ciz(t, not, azalt: true);
      not.value = 'Maliyetinin altına indi';
      await t.pump();
      final op = t.widget<FadeTransition>(find
          .ancestor(
              of: find.text(' · Maliyetinin altına indi'),
              matching: find.byType(FadeTransition))
          .first);
      expect(op.opacity.value, 1);
    });
  });
}
