import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';

import 'helpers/kaynak.dart';

/// Varlık sayfası ikinci tur (Ar-Ge 5 Kas 14:45, müşteri raporu 15:15):
/// teknik şerit tek satır ve panelle aynı sayım (#1), "En büyük düşüş"
/// günlükte ve ~%0'da gizli (#3), başlıktaki günlük tutar "/ lot" (#4).
void main() {
  group('#4 başlıktaki tutarın birimi', () {
    late BuildContext ctx;
    Future<void> baglam(WidgetTester t) => t.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ));

    testWidgets('birim verilirse fark "/ lot" yazar', (t) async {
      await baglam(t);
      final s = donemDegisimSatiri(ctx,
          pct: 0.30,
          donem: 'Bugün',
          fark: 9.22,
          bicim: tryFormatter(digits: 2),
          birim: 'lot');
      expect(s.metin, '+%0,30 · +₺9,22 / lot · Bugün');
    });

    test('yalnız hisse ve fon birim verir', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail/ozet.dart');
      expect(k, contains('birim: widget.asset.type == AssetType.hisse ||'));
    });
  });

  group('#3 en büyük düşüş', () {
    DonemIstatistigi ist(double dd) => DonemIstatistigi(
          ilk: 100,
          son: 101,
          yuksek: 102,
          dusuk: 99,
          enBuyukDususPct: dd,
          oynaklikPct: null,
        );

    test('günlükte ve %0,05 altında hücre yok', () {
      expect(DonemIstatistikIzgarasi.dususVar(ist(-4.2), gunIci: false),
          isTrue);
      expect(DonemIstatistikIzgarasi.dususVar(ist(-4.2), gunIci: true),
          isFalse);
      expect(DonemIstatistikIzgarasi.dususVar(ist(-0.01), gunIci: false),
          isFalse);
      expect(DonemIstatistikIzgarasi.dususVar(ist(0), gunIci: false), isFalse);
      expect(
          DonemIstatistikIzgarasi.hucreSayisi(
              donemGetirisiGizli: true,
              bugunGizli: true,
              oynaklikVar: false,
              dususVar: false),
          0);
    });

    testWidgets('ızgara %0,00 kartı çizmez, boşsa yer kaplamaz',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: DonemIstatistikIzgarasi(
            ist: ist(0),
            gun: 30,
            donemPct: 1,
            bugunPct: null,
            donemGetirisiGizli: true,
            bugunGizli: true,
          ),
        ),
      ));
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsNothing);
      expect(find.textContaining('%0,00'), findsNothing);
      expect(tester.getSize(find.byType(DonemIstatistikIzgarasi)).height, 0);
    });

    test('iki ekran da günlük bilgisini ızgaraya verir', () {
      expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
          contains('gunIci: gun == 1'));
      expect(ekranKaynagiSync('lib/screens/asset_detail/ozet.dart'),
          contains('gunIci: days == 0'));
    });
  });

  group('#1 teknik şerit', () {
    final k = ekranKaynagiSync('lib/screens/asset_detail/sinyal_widgetlari.dart');
    final bas = k.indexOf('class _AssetSignalCardState');
    final son = k.indexOf('class TechnicalSignalPanel ');
    final serit = k.substring(bas, son);

    test('kesilen üst etiket ve "ŞU AN" pili yok', () {
      expect(serit, isNot(contains('technicalOutlookUpper')));
      expect(serit, isNot(contains('nowUpper')));
      expect(serit, contains('technicalPrefix'));
    });

    test('canlı sayım panelle aynı cümle', () {
      expect(serit, contains('buySellNeutralCounts'));
      expect(k.substring(son), contains('buySellNeutralCounts'));
    });

    test('sığmazsa sarar, kesilmez; ağırlık w600', () {
      expect(serit, contains('Wrap('));
      expect(serit, isNot(contains('FontWeight.w800')));
    });
  });
}
