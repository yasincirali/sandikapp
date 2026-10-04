import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';

import 'helpers/kaynak.dart';

/// Sadeleştirme 2, madde 6 — "aynı varlık sayfası iki kez yazılmış".
///
/// Portföy varlık detayı ile varlık sayfasının üst özeti (başlık + fiyat
/// bloğu + dönem değişimi satırı) tek parçadan (`widgets/varlik_ozeti.dart`)
/// gelir. Bu test iki şeyi kilitler: (1) iki kabuk da ortak parçayı
/// kullanır — kopya geri gelmesin; (2) ortak satır biçimi refactor
/// öncesindeki iki kopyanın birebir aynısını üretir.

late BuildContext _ctx;

Future<void> _baglam(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: Builder(builder: (c) {
      _ctx = c;
      return const SizedBox();
    }),
  ));
}

void main() {
  final bicim = tryFormatter(digits: 2);

  group('donemDegisimSatiri — iki eski kopyanın biçimi', () {
    testWidgets('yüzde yoksa boş satır, nötr renk (yer tutulur)', (t) async {
      await _baglam(t);
      final s = donemDegisimSatiri(_ctx, pct: null, donem: '1 yıl', bicim: bicim);
      expect(s.metin, ' ');
      expect(s.renk, _ctx.c.text36);
    });

    testWidgets('düz değişim nötr renkle "değişmedi" der', (t) async {
      await _baglam(t);
      final s = donemDegisimSatiri(_ctx,
          pct: 0.001, donem: '1 yıl', fark: 0.01, bicim: bicim);
      expect(s.renk, _ctx.c.text36);
      expect(s.metin, isNot(contains('%')));
      // `duz` verilirse (varlık sayfası: `isFlat`) eşik yerine o geçerli.
      final z = donemDegisimSatiri(_ctx,
          pct: 2.0, donem: '1 yıl', fark: 2, bicim: bicim, duz: true);
      expect(z.renk, _ctx.c.text36);
    });

    testWidgets('yüzde · işaretli fark · dönem', (t) async {
      await _baglam(t);
      final art = donemDegisimSatiri(_ctx,
          pct: 2.66, donem: '1 yıl', fark: 8, bicim: bicim);
      expect(art.metin, '+%2,66 · +₺8,00 · 1 yıl');
      expect(art.renk, _ctx.signColor(2.66));
      final azal = donemDegisimSatiri(_ctx,
          pct: -1.5, donem: '1 hf', fark: -3.25, bicim: bicim);
      expect(azal.metin, '−%1,50 · −₺3,25 · 1 hf');
      expect(azal.renk, _ctx.signColor(-1.5));
    });

    testWidgets('fark yoksa (mevduat) yalnız yüzde', (t) async {
      await _baglam(t);
      final s = donemDegisimSatiri(_ctx, pct: 1.2, donem: '1 ay', bicim: bicim);
      expect(s.metin, '+%1,20 · 1 ay');
    });
  });

  group('VarlikBasligi', () {
    Future<void> ciz(WidgetTester t, VarlikKimligi k, {bool atla = false}) =>
        t.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
              body: VarlikBasligi(kimlik: k, adTekrariniAtla: atla)),
        ));

    testWidgets('kısa etiket + "ad · tür"', (t) async {
      await ciz(
          t,
          const VarlikKimligi(
              ticker: 'THYAO.IS',
              name: 'Türk Hava Yolları',
              type: AssetType.hisse,
              currency: 'TRY'));
      expect(find.text('THYAO'), findsOneWidget);
      expect(find.text('Türk Hava Yolları · Hisse'), findsOneWidget);
    });

    testWidgets('ad tekrarı yalnız istenince atlanır', (t) async {
      const ev = VarlikKimligi(
          ticker: '',
          name: 'Kadıköy daire',
          type: AssetType.diger,
          currency: 'TRY');
      await ciz(t, ev);
      expect(find.textContaining('Kadıköy daire ·'), findsOneWidget,
          reason: 'varlık sayfası davranışı birebir eski');
      await ciz(t, ev, atla: true);
      expect(find.textContaining('Kadıköy daire ·'), findsNothing,
          reason: 'detay ekranı: kısa etiket ad ise alt satır yalnız tür');
    });
  });

  test('iki kabuk da ortak üst özeti kullanır — kopya geri gelmesin', () {
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    for (final w in [
      'VarlikBasligi(',
      'VarlikFiyatBlogu(',
      'donemDegisimSatiri(',
    ]) {
      expect(sayfa, contains(w), reason: 'varlık sayfası $w kullanmalı');
      expect(detay, contains(w), reason: 'varlık detayı $w kullanmalı');
    }
    // Eski kopyaların imzası: "değişmedi" satırı ve büyük fiyatın stili
    // ekranlarda ikinci kez yazılmasın.
    for (final kopya in [
      'periodNoChange',
      'numLarge.copyWith(color: context.c.gold)',
      'numLarge.copyWith(color: context.c.text90)',
    ]) {
      expect(sayfa, isNot(contains(kopya)), reason: 'sayfada $kopya kopyası');
      expect(detay, isNot(contains(kopya)), reason: 'detayda $kopya kopyası');
    }
  });
}
