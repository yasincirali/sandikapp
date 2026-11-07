import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/yillik_aralik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';

import 'helpers/kaynak.dart';

/// 52 haftalık aralık (Ar-Ge 2026-11-07 12:30 #1). Model saf: uçlar seriden
/// bir kez, canlı fiyat sonra; uydurma nokta yok; kısa seride "Son N ay".

final _simdi = DateTime(2026, 11, 7, 12);

/// [gunOnce] gün önceden bugüne haftalık seri; değerler [deger]'den.
Map<int, double> _haftalik(int gunOnce, double Function(int i) deger) => {
      for (var g = gunOnce, i = 0; g >= 0; g -= 7, i++)
        _simdi.subtract(Duration(days: g)).millisecondsSinceEpoch: deger(i),
    };

Widget _sar(Widget w, {double olcek = 1}) => MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(16), child: w),
          ),
        ),
      ),
    );

void main() {
  group('YillikUclar.hesapla', () {
    test('tam yıl: uçlar, ay null', () {
      final seri = _haftalik(364, (i) => 100.0 + i);
      final u = YillikUclar.hesapla(seri, simdi: _simdi)!;
      expect(u.dusuk, 100);
      expect(u.yuksek, 152);
      expect(u.ay, isNull);
    });

    test('yıldan eski noktalar pencereye girmez', () {
      final seri = {
        ..._haftalik(364, (i) => 100.0 + i),
        _simdi.subtract(const Duration(days: 500)).millisecondsSinceEpoch: 1.0,
      };
      expect(YillikUclar.hesapla(seri, simdi: _simdi)!.dusuk, 100);
    });

    test('kısa seri: Son N ay', () {
      final seri = _haftalik(7 * 30, (i) => 50.0 + i); // ~210 gün
      expect(YillikUclar.hesapla(seri, simdi: _simdi)!.ay, 6);
    });

    test('boş, tek nokta, ayı doldurmayan seri ve geçersiz değer → null', () {
      expect(YillikUclar.hesapla({}, simdi: _simdi), isNull);
      expect(
          YillikUclar.hesapla(
              {_simdi.millisecondsSinceEpoch: 10}, simdi: _simdi),
          isNull);
      expect(YillikUclar.hesapla(_haftalik(14, (i) => 10.0 + i), simdi: _simdi),
          isNull);
      // Sıfır/negatif nokta seriye girmez (uydurma sayı yok).
      final bozuk = _haftalik(364, (i) => i.isEven ? 0.0 : -1.0);
      expect(YillikUclar.hesapla(bozuk, simdi: _simdi), isNull);
    });
  });

  group('YillikUclar.bugunle', () {
    const u = YillikUclar(dusuk: 80, yuksek: 100, sonDeger: 92);

    test('konum ve zirveden uzaklık', () {
      final a = u.bugunle(92)!;
      expect(a.konum, closeTo(0.6, 1e-9));
      expect(a.yuksegeYakin, isTrue);
      expect(a.yuksektenUzaklikPct, closeTo(8, 1e-9));
      expect(a.uctaMi, isFalse);
    });

    test('dibe yakınsa dipten uzaklık', () {
      final a = u.bugunle(88)!;
      expect(a.yuksegeYakin, isFalse);
      expect(a.dusuktenUzaklikPct, closeTo(10, 1e-9));
    });

    test('canlı fiyat aralığın dışındaysa uçlar onu kapsar', () {
      final a = u.bugunle(110)!;
      expect(a.yuksek, 110);
      expect(a.konum, 1);
      expect(a.uctaMi, isTrue);
    });

    test('canlı fiyat bilinmiyorsa son nokta', () {
      expect(u.bugunle(0)!.bugun, 92);
      expect(u.bugunle(double.nan)!.bugun, 92);
    });

    test('düz aralık → null', () {
      const duz = YillikUclar(dusuk: 5, yuksek: 5, sonDeger: 5);
      expect(duz.bugunle(5), isNull);
    });
  });

  group('YillikAralikSatiri', () {
    testWidgets('cümle ve tek Semantics etiketi', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_sar(YillikAralikSatiri(
        aralik: const YillikAralik(dusuk: 80, yuksek: 100, bugun: 92),
        bicim: fiyatBicimi(92),
      )));
      expect(find.text('Yıllık aralık'), findsOneWidget);
      expect(find.text('Yılın en yükseğinin %8,0 altında'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(
            r'^Yıllık aralık: en düşük ₺80,00, en yüksek ₺100,00, bugün ₺92,00')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('kısa seri ve dip tarafı', (tester) async {
      await tester.pumpWidget(_sar(YillikAralikSatiri(
        aralik: const YillikAralik(dusuk: 80, yuksek: 100, bugun: 88, ay: 7),
        bicim: fiyatBicimi(88),
      )));
      expect(find.text('Son 7 ay'), findsOneWidget);
      expect(find.text('Son 7 ayın en düşüğünün %10,0 üstünde'), findsOneWidget);
    });

    testWidgets('3.1× yazı ve 320 pt\'de büyük tutarla taşmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_sar(
        YillikAralikSatiri(
          aralik: const YillikAralik(
              dusuk: 1234567.89, yuksek: 9876543.21, bugun: 5555555.55, ay: 11),
          bicim: fiyatBicimi(5555555.55),
        ),
        olcek: 3.1,
      ));
      expect(tester.takeException(), isNull);
    });
  });

  test('varlık ekranı: satır 1Y serisinden, yoksa yer kaplamaz, mevduatta yok',
      () {
    final kaynak = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(kaynak, contains('_yillikAralikSatiri(pnl.currentUnitTRY)'));
    expect(kaynak,
        contains('_yillikUclar = YillikUclar.hesapla(seri, simdi: now)'));
    final i = kaynak.indexOf('Widget _yillikAralikSatiri(');
    final govde = kaynak.substring(i, kaynak.indexOf('\n  }', i));
    expect(govde, contains('AssetType.mevduat'));
    expect(govde, contains('if (aralik == null) return const SizedBox.shrink()'));
    // Ölçek büyük fiyatla aynı (fiyat kaynağı sözleşmesi 2).
    expect(govde, contains('_birimBicimi('));
  });
}
