import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/bedelli_artirim.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bedelli_artirim_sheet.dart';

import 'helpers/kaynak.dart';

/// Bedelli sermaye artırımı (Ar-Ge 2026-11-07 16:06#1): rüçhan hakkını
/// kullanan yatırımcının yeni lotları lot başı 1 ₺ alış olarak yazılır.
Asset _lot(
  double adet, {
  AssetKind kind = AssetKind.buy,
  required DateTime tarih,
  String ticker = 'THYAO.IS',
  String? subCategory,
  DateTime? silindi,
  double fiyat = 300,
  bool? maliyetBilinmiyor,
}) =>
    Asset(
      id: 'l-${adet.toString()}-${tarih.toIso8601String()}-${kind.name}',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: ticker,
      type: AssetType.hisse,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      addedDate: tarih,
      kind: kind,
      subCategory: subCategory,
      deletedAt: silindi,
      maliyetBilinmiyor: maliyetBilinmiyor,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('BedelliArtirim.hesapla', () {
    final lotlar = [
      _lot(100, tarih: DateTime(2026, 1, 10)),
      _lot(50, tarih: DateTime(2026, 3, 1)),
      _lot(30, kind: AssetKind.sell, tarih: DateTime(2026, 4, 1)),
    ];

    test('örnek: 120 lota %100 → 120 yeni lot, toplam 120 ₺', () {
      final h = BedelliArtirim.hesapla(
          lotlar: lotlar, oranYuzde: 100, tarih: DateTime(2026, 5, 1));
      expect(h.eldekiLot, 120);
      expect(h.yeniLot, 120);
      expect(h.toplamTutar, 120);
      expect(h.yuvarlandi, isFalse);
      expect(h.kaydedilebilir, isTrue);
    });

    test('eldeki adet seçilen günün sonundaki adettir', () {
      // 1 Mart'ta (gün içinde) alınan 50 sayılır, 1 Nisan satışı sayılmaz.
      final h = BedelliArtirim.hesapla(
          lotlar: lotlar, oranYuzde: 10, tarih: DateTime(2026, 3, 1));
      expect(h.eldekiLot, 150);
      expect(h.yeniLot, 15);
      // Alıştan önce: hiç lot yok.
      final once = BedelliArtirim.hesapla(
          lotlar: lotlar, oranYuzde: 100, tarih: DateTime(2026, 1, 9));
      expect(once.eldekiLot, 0);
      expect(once.kaydedilebilir, isFalse);
    });

    test('kesirli hak aşağı yuvarlanır ve bu söylenir', () {
      final h = BedelliArtirim.hesapla(
          lotlar: [_lot(125, tarih: DateTime(2026, 1, 1))],
          oranYuzde: 10,
          tarih: DateTime(2026, 2, 1));
      expect(h.hakSayisi, closeTo(12.5, 1e-9));
      expect(h.yeniLot, 12);
      expect(h.yuvarlandi, isTrue);
    });

    test('kayan nokta tam sonucu bir eksik yuvarlamaz', () {
      // 3 × 33,333… / 100 gibi değil; 70 × 10 / 100 = 7 → 7 (6 değil).
      final h = BedelliArtirim.hesapla(
          lotlar: [_lot(70, tarih: DateTime(2026, 1, 1))],
          oranYuzde: 10,
          tarih: DateTime(2026, 2, 1));
      expect(h.yeniLot, 7);
      expect(h.yuvarlandi, isFalse);
    });

    test('oran yok / sıfır / eksi → kaydedilemez', () {
      for (final o in [null, 0.0, -50.0]) {
        final h = BedelliArtirim.hesapla(
            lotlar: lotlar, oranYuzde: o, tarih: DateTime(2026, 5, 1));
        expect(h.yeniLot, 0, reason: 'oran $o');
        expect(h.kaydedilebilir, isFalse);
      }
    });

    test('silinmiş lot ve temettü adede girmez', () {
      final h = BedelliArtirim.hesapla(lotlar: [
        _lot(100, tarih: DateTime(2026, 1, 1)),
        _lot(40, tarih: DateTime(2026, 1, 2), silindi: DateTime(2026, 1, 3)),
        _lot(5, kind: AssetKind.dividend, tarih: DateTime(2026, 1, 4)),
      ], oranYuzde: 50, tarih: DateTime(2026, 2, 1));
      expect(h.eldekiLot, 100);
      expect(h.yeniLot, 50);
    });

    group('yeni ortalama maliyet', () {
      test('örnek: 120 lot ₺287,50 + %150 → ₺115,60 (Portföy ile aynı)', () {
        final lotlar = [_lot(120, tarih: DateTime(2026, 1, 10), fiyat: 287.5)];
        final h = BedelliArtirim.hesapla(
            lotlar: lotlar, oranYuzde: 150, tarih: DateTime(2026, 5, 1));
        expect(h.yeniLot, 180);
        expect(h.yeniOrtalama, closeTo(115.6, 1e-9));
        // Kayıttan sonra Portföy'ün göstereceği ortalama: aynı lot setine
        // sayfanın yazdığı alış eklenince `aggregatePositions` aynı sayıyı
        // vermeli.
        final kayit = Asset(
          id: 'yeni',
          userId: 'u1',
          name: 'Türk Hava Yolları',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: 180,
          purchasePrice: BedelliArtirim.nominal,
          currency: 'TRY',
          notes: 'Bedelli artırım',
          addedDate: DateTime(2026, 5, 1, 12),
        );
        final p = aggregatePositions([...lotlar, kayit]).single;
        expect(p.weightedPurchasePrice, closeTo(h.yeniOrtalama!, 1e-9));
      });

      test('satış sonrası defterde yürüyen ortalamayı izler', () {
        // 100 @ ₺200, 50 sat → elde 50 @ ₺200; %100 → 50 @ ₺1.
        // Yürüyen: (50 × 200 + 50) ÷ 100 = ₺100,50.
        final h = BedelliArtirim.hesapla(lotlar: [
          _lot(100, tarih: DateTime(2026, 1, 1), fiyat: 200),
          _lot(50, kind: AssetKind.sell, tarih: DateTime(2026, 2, 1)),
        ], oranYuzde: 100, tarih: DateTime(2026, 3, 1));
        expect(h.yeniOrtalama, closeTo(100.5, 1e-9));
      });

      test('uydurma sayı yok: lot yok, yeni lot yok, maliyet bilinmiyor', () {
        final lotYok = BedelliArtirim.hesapla(
            lotlar: [_lot(10, tarih: DateTime(2026, 6, 1))],
            oranYuzde: 100,
            tarih: DateTime(2026, 5, 1));
        expect(lotYok.yeniOrtalama, isNull);
        final oransiz = BedelliArtirim.hesapla(
            lotlar: [_lot(10, tarih: DateTime(2026, 1, 1))],
            oranYuzde: null,
            tarih: DateTime(2026, 5, 1));
        expect(oransiz.yeniOrtalama, isNull);
        final isaretli = BedelliArtirim.hesapla(lotlar: [
          _lot(10, tarih: DateTime(2026, 1, 1), maliyetBilinmiyor: true),
        ], oranYuzde: 100, tarih: DateTime(2026, 5, 1));
        expect(isaretli.yeniOrtalama, isNull);
        final sifir = BedelliArtirim.hesapla(
            lotlar: [_lot(10, tarih: DateTime(2026, 1, 1), fiyat: 0)],
            oranYuzde: 100,
            tarih: DateTime(2026, 5, 1));
        expect(sifir.yeniOrtalama, isNull);
      });
    });

    test('yalnız BIST hissesi uygun', () {
      expect(BedelliArtirim.uygunMu(_lot(1, tarih: DateTime(2026))), isTrue);
      expect(
          BedelliArtirim.uygunMu(_lot(1,
              tarih: DateTime(2026), ticker: 'AAPL', subCategory: 'abd')),
          isFalse);
      final fon = Asset(
        id: 'f',
        userId: 'u1',
        name: 'Fon',
        ticker: 'TEFAS:AFT',
        type: AssetType.fon,
        quantity: 1,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
      );
      expect(BedelliArtirim.uygunMu(fon), isFalse);
    });
  });

  group('BedelliArtirimSheet', () {
    final lotlar = [_lot(120, tarih: DateTime(2026, 1, 10))];

    Future<void> ac(WidgetTester t, Widget govde,
        {double olcek = 1, Size boy = const Size(390, 844)}) async {
      t.view.physicalSize = boy;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => showSandikSheet<void>(
                  context: c,
                  isScrollControlled: true,
                  baslik: 'Bedelli artırım',
                  altMetin: 'Yeni lotlar lot başı ₺1 alış olarak eklenir',
                  builder: (_) => govde,
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('aç'));
      await t.pumpAndSettle();
    }

    testWidgets('oran yazılmadan düğme kapalı; yazınca önizleme cümlesi',
        (t) async {
      await ac(
          t,
          BedelliArtirimSheet(
              lotlar: lotlar,
              ilkTarih: DateTime(2026, 5, 1),
              kaydet: (_, __) async {}));
      final dugme = find.byKey(const ValueKey('bedelli-kaydet'));
      expect(t.widget<FilledButton>(
              find.descendant(of: dugme, matching: find.byType(FilledButton)))
          .onPressed, isNull);
      expect(find.byKey(const ValueKey('bedelli-onizleme')), findsNothing);
      expect(find.byKey(const ValueKey('bedelli-yeni-ortalama')), findsNothing);

      await t.enterText(find.byKey(const ValueKey('bedelli-oran')), '100');
      await t.pump();
      expect(find.text('Elindeki 120 lota 120 yeni lot, lot başı ₺1, toplam ₺120'),
          findsOneWidget);
      // 120 @ ₺300 + 120 @ ₺1 → ₺150,50; tutar w600 vurgulu.
      final satir = find.byKey(const ValueKey('bedelli-yeni-ortalama'));
      expect(t.widget<Text>(satir).textSpan!.toPlainText(),
          'Yeni ortalama maliyetin ₺150,50 olur.');
      final parcalar = (t.widget<Text>(satir).textSpan! as TextSpan).children!;
      expect((parcalar[1] as TextSpan).text, '₺150,50');
      expect((parcalar[1] as TextSpan).style?.fontWeight, FontWeight.w600);
      expect(t.widget<FilledButton>(
              find.descendant(of: dugme, matching: find.byType(FilledButton)))
          .onPressed, isNotNull);
    });

    testWidgets('kesirde yuvarlama satırı görünür', (t) async {
      await ac(
          t,
          BedelliArtirimSheet(
              lotlar: [_lot(125, tarih: DateTime(2026, 1, 1))],
              ilkTarih: DateTime(2026, 5, 1),
              kaydet: (_, __) async {}));
      await t.enterText(find.byKey(const ValueKey('bedelli-oran')), '10');
      await t.pump();
      expect(find.textContaining('12,5 hakkın 12 tanesi lot olur'),
          findsOneWidget);
    });

    testWidgets('kaydet hesabı ve gün içi tarihi verir, sayfa kapanır',
        (t) async {
      BedelliArtirim? giden;
      DateTime? gidenTarih;
      await ac(
          t,
          BedelliArtirimSheet(
              lotlar: lotlar,
              ilkTarih: DateTime(2026, 5, 1),
              kaydet: (h, tarih) async {
                giden = h;
                gidenTarih = tarih;
              }));
      await t.enterText(find.byKey(const ValueKey('bedelli-oran')), '50');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('bedelli-kaydet')));
      await t.pumpAndSettle();
      expect(giden?.yeniLot, 60);
      expect(gidenTarih, DateTime(2026, 5, 1, 12));
      expect(find.byType(BedelliArtirimSheet), findsNothing);
    });

    testWidgets('düğme ve oran alanı en az 44 pt', (t) async {
      await ac(
          t,
          BedelliArtirimSheet(
              lotlar: lotlar,
              ilkTarih: DateTime(2026, 5, 1),
              kaydet: (_, __) async {}));
      expect(t.getSize(find.byKey(const ValueKey('bedelli-kaydet'))).height,
          greaterThanOrEqualTo(SandikTouch.min));
      expect(t.getSize(find.byKey(const ValueKey('bedelli-oran'))).height,
          greaterThanOrEqualTo(SandikTouch.min));
    });

    for (final (ad, olcek, boy) in [
      ('320 pt, 1×', 1.0, const Size(320, 568)),
      ('320 pt, 3.1×', 3.1, const Size(320, 568)),
      ('390 pt, 3.1×', 3.1, const Size(390, 844)),
    ]) {
      testWidgets('taşma yok — $ad', (t) async {
        await ac(
            t,
            BedelliArtirimSheet(
                lotlar: lotlar,
                ilkTarih: DateTime(2026, 5, 1),
                kaydet: (_, __) async {}),
            olcek: olcek,
            boy: boy);
        await t.enterText(find.byKey(const ValueKey('bedelli-oran')), '33,5');
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('menü → sayfa → kayıt', () {
    testWidgets('⋯ düğmeye bağlı menü açar: tek satır, 44 pt, etiketli',
        (t) async {
      final handle = t.ensureSemantics();
      final lot = _lot(120, tarih: DateTime(2026, 1, 10));
      await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_Auth.new),
          portfolioProvider.overrideWith(_KayitYazan.new),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: Consumer(
                builder: (_, ref, __) => Builder(
                  builder: (c) => IconButton(
                    key: const ValueKey('dugme'),
                    tooltip: 'Diğer işlemler',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => showVarlikDigerIslemler(c, ref,
                        varlik: lot, lotlar: [lot]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const ValueKey('dugme')));
      await t.pumpAndSettle();
      // Alt sayfa yok: başlıklı "Diğer işlemler" sayfası açılmaz.
      expect(find.byType(BottomSheet), findsNothing);
      final satir = find.byKey(const ValueKey('menu-bedelli-artirim'));
      expect(satir, findsOneWidget);
      expect(find.text('Bedelli artırım'), findsOneWidget);
      expect(t.getSize(satir).height, greaterThanOrEqualTo(SandikTouch.min));
      // Menü düğmenin altında açılır.
      expect(t.getRect(satir).top,
          greaterThanOrEqualTo(t.getRect(find.byKey(const ValueKey('dugme'))).bottom - 1));
      expect(
          find.bySemanticsLabel(
              'Bedelli artırım. Rüçhan hakkını kullandıysan yeni lotları ekle'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('alış lotu 1 ₺, not etiketi, BIST hissesine', (t) async {
      final portfoy = _KayitYazan();
      final lot = _lot(120, tarih: DateTime(2026, 1, 10));
      await t.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_Auth.new),
          portfolioProvider.overrideWith(() => portfoy),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Scaffold(
            body: Consumer(
              builder: (_, ref, __) => Builder(
                builder: (c) => TextButton(
                  onPressed: () => showVarlikDigerIslemler(c, ref,
                      varlik: lot, lotlar: [lot]),
                  child: const Text('⋯'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('⋯'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('menu-bedelli-artirim')));
      await t.pumpAndSettle();
      // Menü kapandı, tek modal: bedelli sayfası.
      expect(find.byKey(const ValueKey('menu-bedelli-artirim')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('bedelli-oran')), '100');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('bedelli-kaydet')));
      await t.pumpAndSettle();

      expect(portfoy.yazilan, hasLength(1));
      final y = portfoy.yazilan.single;
      expect(y.quantity, 120);
      expect(y.purchasePrice, 1);
      expect(y.currency, 'TRY');
      expect(y.ticker, 'THYAO.IS');
      expect(y.notes, 'Bedelli artırım');
      expect(y.yol, 'bedelli');
      expect(find.text('120 yeni lot eklendi'), findsOneWidget);
    });
  });

  test('varlık ekranı "⋯" yalnız kendi açık BIST hissesinde', () {
    final kaynak = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(kaynak, contains('_digerIslemlerDugmesi(isOwnAsset)'));
    final govde = kaynak.substring(kaynak.indexOf('Widget? _digerIslemlerDugmesi'));
    final ilk = govde.substring(0, govde.indexOf('IconButton('));
    expect(ilk, contains('if (!isOwnAsset) return null;'));
    expect(ilk, contains('BedelliArtirim.uygunMu'));
    expect(ilk, contains('canli.acik'));
  });
}

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 't@e.com',
        displayName: 'T',
        createdAt: DateTime(2026),
      );
}

typedef _Yazim = ({
  String ticker,
  double quantity,
  double purchasePrice,
  String currency,
  String notes,
  String yol,
});

/// `addAsset` çağrılarını kaydeder; sunucuya gitmez.
class _KayitYazan extends PortfolioNotifier {
  final yazilan = <_Yazim>[];

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
    String? sozlesmeId,
    String? portfoyId,
    String yol = 'form',
    bool maliyetBilinmiyor = false,
  }) async =>
      yazilan.add((
        ticker: ticker,
        quantity: quantity,
        purchasePrice: purchasePrice,
        currency: currency,
        notes: notes,
        yol: yol,
      ));
}
