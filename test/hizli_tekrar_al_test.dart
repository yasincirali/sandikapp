// "Bunu tekrar al" + Hızlı Al "Son alımın" çipi (Ar-Ge 8 Kas #1).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/hizli_tekrar_al.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/islem_notu_sheet.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Asset _lot(
  String id, {
  String userId = 'u1',
  AssetType tur = AssetType.fon,
  String ticker = 'IPB',
  AssetKind kind = AssetKind.buy,
  double adet = 12,
  double fiyat = 10,
  double guncel = 11,
  DateTime? t,
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: guncel,
      addedDate: t ?? DateTime(2026, 10, 1),
      kind: kind,
      deletedAt: silindi,
    );

class _Defter extends PortfolioNotifier {
  _Defter(this.lotlar);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(assets: lotlar);
}

Future<void> _acDiyalog(
  WidgetTester tester,
  Asset pozisyon, {
  List<Asset> defter = const [],
  QuickAdjustMode mod = QuickAdjustMode.add,
  double? baslangic,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [portfolioProvider.overrideWith(() => _Defter(defter))],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              // Defter yüklensin: diyalog `valueOrNull` okur.
              await ref.read(portfolioProvider.future);
              if (!context.mounted) return;
              await showQuickAdjustDialog(context, ref,
                  asset: pozisyon, mode: mod, baslangicMiktar: baslangic);
            },
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('tekrarAlinabilir', () {
    test('yalnız kendi, silinmemiş alışı', () {
      expect(tekrarAlinabilir(_lot('a'), benimId: 'u1'), isTrue);
      expect(tekrarAlinabilir(_lot('a', kind: AssetKind.sell), benimId: 'u1'),
          isFalse,
          reason: 'satış');
      expect(
          tekrarAlinabilir(_lot('a', kind: AssetKind.dividend), benimId: 'u1'),
          isFalse,
          reason: 'temettü');
      expect(
          tekrarAlinabilir(_lot('a', userId: 'ortak'), benimId: 'u1'), isFalse,
          reason: 'ortağın hareketi');
      expect(
          tekrarAlinabilir(_lot('a', silindi: DateTime(2026, 10, 2)),
              benimId: 'u1'),
          isFalse,
          reason: 'silinmiş hareket');
      expect(tekrarAlinabilir(_lot('a'), benimId: null), isFalse);
    });
  });

  group('sonAlim', () {
    test('ham defterden en yeni, silinmemiş alış; satış sayılmaz', () {
      final poz = _lot('poz');
      final defter = [
        _lot('eski', adet: 5, t: DateTime(2026, 8, 1)),
        _lot('son', adet: 12, t: DateTime(2026, 10, 1)),
        _lot('silinen',
            adet: 99,
            t: DateTime(2026, 10, 20),
            silindi: DateTime(2026, 10, 21)),
        _lot('satis', kind: AssetKind.sell, adet: 3, t: DateTime(2026, 11, 1)),
        _lot('baska', ticker: 'TTE', adet: 7, t: DateTime(2026, 11, 2)),
      ];
      expect(sonAlim(defter, poz)?.id, 'son');
    });

    test('alış yoksa null', () {
      expect(sonAlim([_lot('x', ticker: 'TTE')], _lot('poz')), isNull);
    });

    test('mevduatta alan değeri TL tutarı', () {
      final m = _lot('m', tur: AssetType.mevduat, adet: 4990.5, fiyat: 1.002);
      expect(alimAlanDegeri(m), closeTo(5000.48, 0.001));
    });
  });

  group('tekrarAlHedefi', () {
    test('açık pozisyonda o hareketin miktarı', () {
      final islem = _lot('a', adet: 12);
      final h =
          tekrarAlHedefi([islem, _lot('b', adet: 3)], islem, benimId: 'u1');
      expect(h, isNotNull);
      expect(h!.miktar, 12);
      expect(h.pozisyon.quantity, 15, reason: 'pozisyonun görünüm varlığı');
    });

    test('kapanmış pozisyonda yok (bugünkü fiyat tazelenmez)', () {
      final islem = _lot('a', adet: 12);
      final satis = _lot('s', kind: AssetKind.sell, adet: 12);
      expect(tekrarAlHedefi([islem, satis], islem, benimId: 'u1'), isNull);
    });

    test('ortağın alışında yok', () {
      final islem = _lot('a', userId: 'ortak');
      expect(tekrarAlHedefi([islem], islem, benimId: 'u1'), isNull);
    });
  });

  group('hizliMiktarOnerileri + son alım', () {
    test('son alım verilince çip sayısı aynı: en büyük adım düşer', () {
      final std = hizliMiktarOnerileri(
          tur: AssetType.fon, birimTuru: 'piece', eldeki: 50, satis: false);
      final yeni = hizliMiktarOnerileri(
          tur: AssetType.fon,
          birimTuru: 'piece',
          eldeki: 50,
          satis: false,
          sonAlim: 12);
      expect(std, [1, 10, 100, 1000]);
      expect(yeni, [1, 10, 100]);
    });

    test('son alım standart değere eşitse o değer düşer (tekrar yok)', () {
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.fon,
              birimTuru: 'piece',
              eldeki: 50,
              satis: false,
              sonAlim: 10),
          [1, 100, 1000]);
    });

    test('satışta son alım yok sayılır', () {
      expect(
          hizliMiktarOnerileri(
              tur: AssetType.fon,
              birimTuru: 'piece',
              eldeki: 150,
              satis: true,
              sonAlim: 12),
          [1, 10, 100]);
    });
  });

  group('Hızlı Al diyaloğu', () {
    testWidgets('"Son alımın · 12 pay" ilk çip; çip sayısı aynı; 44 pt',
        (tester) async {
      // Küçük fiyat: Ahem fontunda "Toplam maliyet" tutarı taşmasın.
      final lot = _lot('a', adet: 12);
      final poz = _lot('poz', adet: 12, fiyat: 1, guncel: 1);
      await _acDiyalog(tester, poz, defter: [lot]);
      final cip = find.text('Son alımın · 12 pay');
      expect(cip, findsOneWidget);
      expect(find.text('1000'), findsNothing, reason: 'son standart çip düştü');
      expect(find.text('100'), findsOneWidget);
      // Çip ilk sırada: diğer çiplerin solunda.
      expect(tester.getTopLeft(cip).dx,
          lessThan(tester.getTopLeft(find.text('100')).dx));
      // Dokunma alanı ≥ 44 pt.
      final hedef =
          find.ancestor(of: cip, matching: find.byType(SandikTappable));
      expect(
          tester.getSize(hedef).height, greaterThanOrEqualTo(SandikTouch.min));
      // Ekran okuyucu: virgüllü cümle.
      expect(find.bySemanticsLabel('Son alımın, 12 pay'), findsOneWidget);
      await tester.tap(cip);
      await tester.pump();
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && w.controller?.text == '12'),
          findsOneWidget);
    });

    testWidgets('alış yoksa çip yok, standart çipler aynen', (tester) async {
      await _acDiyalog(tester, _lot('poz'), defter: const []);
      expect(find.textContaining('Son alımın'), findsNothing);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('Sat modunda çip yok', (tester) async {
      await _acDiyalog(tester, _lot('poz', adet: 50),
          defter: [_lot('a', adet: 12)], mod: QuickAdjustMode.remove);
      expect(find.textContaining('Son alımın'), findsNothing);
    });

    testWidgets('baslangicMiktar alanı doldurur, fiyat bugünün',
        (tester) async {
      await _acDiyalog(tester, _lot('poz', fiyat: 1, guncel: 1.5),
          defter: [_lot('a')], baslangic: 2);
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && w.controller?.text == '2'),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is TextField && w.controller?.text == '1,5'),
          findsOneWidget);
    });
  });

  group('Not sayfası "Bunu tekrar al" satırı', () {
    Future<void> pump(WidgetTester tester, Widget w) => tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark],
            ),
            home: Scaffold(body: w),
          ),
        );

    testWidgets('tekrarAl verilmezse satır yok', (tester) async {
      await pump(tester,
          IslemNotuSheet(asset: _lot('a'), not: null, duzenlenebilir: true));
      expect(find.text('Bunu tekrar al'), findsNothing);
    });

    testWidgets('verilirse satır 44 pt, dokununca çağrılır', (tester) async {
      var cagrildi = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                builder: (_) => IslemNotuSheet(
                  asset: _lot('a'),
                  not: null,
                  duzenlenebilir: true,
                  tekrarAl: () => cagrildi++,
                ),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      final satir = find.byKey(const ValueKey('tekrar_al_satiri'));
      expect(satir, findsOneWidget);
      expect(
          tester.getSize(satir).height, greaterThanOrEqualTo(SandikTouch.min));
      expect(find.bySemanticsLabel('Bunu tekrar al'), findsOneWidget);
      await tester.tap(satir);
      await tester.pumpAndSettle();
      expect(cagrildi, 1);
      expect(find.byType(IslemNotuSheet), findsNothing,
          reason: 'sayfa kapanır, Hızlı Al çağıran tarafından açılır');
    });
  });
}
