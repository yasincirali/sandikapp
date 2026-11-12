import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/zekat_provider.dart';
import 'package:portfoy_takip/services/zekat_hesabi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_skeleton.dart';
import 'package:portfoy_takip/widgets/zekat_sheet.dart';

import 'helpers/yazi_olcegi.dart';

/// Zekât hesabı (2026-11-12): saf hesap + sheet.
final _bugun = DateTime(2026, 11, 12);

int _id = 0;
Asset _lot(
  AssetType tur,
  double adet,
  double fiyat, {
  int gunOnce = 400,
  String ticker = 'X',
  String para = 'TRY',
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: 'l${_id++}',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: para,
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: _bugun.subtract(Duration(days: gunOnce)),
      kind: kind,
    );

double _tl(double t, String p) => p == 'USD' ? t * 40 : t;

ZekatSonucu? _hesap(List<Asset> lotlar, {double? gram = 5000, double borc = 0}) =>
    zekatHesapla(
        lotlar: lotlar,
        gramAltin24Try: gram,
        toTRY: _tl,
        bugun: _bugun,
        borc: borc);

/// Hiç bitmeyen portföy yüklemesi (açılıştaki ilk kare).
class _YuklenenPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() => Completer<PortfolioState>().future;
}

class _HazirPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: [_lot(AssetType.mevduat, 1, 1000000)]);
}

void main() {
  group('zekatSonucuProvider', () {
    test('portföy yüklenirken yükleniyor (boş durum değil)', () async {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(_YuklenenPortfoy.new),
        zekatGramAltinProvider.overrideWith((ref) async => 5000),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(zekatSonucuProvider(0), (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(sub.read().isLoading, isTrue);
    });

    test('portföy ve fiyat hazır: sonuç', () async {
      final c = ProviderContainer(overrides: [
        portfolioProvider.overrideWith(_HazirPortfoy.new),
        zekatGramAltinProvider.overrideWith((ref) async => 5000),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(zekatSonucuProvider(0), (_, __) {});
      await c.read(portfolioProvider.future);
      await c.read(zekatGramAltinProvider.future);
      expect(sub.read().valueOrNull?.zekat, greaterThan(0));
    });
  });

  group('zekatHesapla', () {
    test('kur yoksa null (uydurma nisap yok)', () {
      final l = [_lot(AssetType.mevduat, 1, 1000000)];
      expect(_hesap(l, gram: null), isNull);
      expect(_hesap(l, gram: 0), isNull);
    });

    test('nisap = 80,18 g × gram fiyatı', () {
      final s = _hesap(const [])!;
      expect(s.nisapTutari, closeTo(80.18 * 5000, 1e-6));
      expect(s.zekat, 0);
      expect(s.nisabaUlasti, isFalse);
    });

    test('nisap üstü: %2,5', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 1000000)])!;
      expect(s.nisabaUlasti, isTrue);
      expect(s.zekat, closeTo(25000, 1e-6));
    });

    test('nisap altı: zekât 0', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 300000)])!;
      expect(s.nisabaUlasti, isFalse);
      expect(s.zekat, 0);
    });

    test('354 gün sınırı: 354 eski, 353 yeni', () {
      final s = _hesap([
        _lot(AssetType.hisse, 1, 1000, gunOnce: 354, ticker: 'A'),
        _lot(AssetType.hisse, 1, 700, gunOnce: 353, ticker: 'B'),
      ])!;
      expect(s.eskiTutar, closeTo(1000, 1e-9));
      expect(s.yeniTutar, closeTo(700, 1e-9));
    });

    test('borç düşülür, matrah eksiye inmez', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 1000000)], borc: 500000)!;
      expect(s.matrah, closeTo(500000, 1e-6));
      expect(s.zekat, closeTo(12500, 1e-6));
      final t = _hesap([_lot(AssetType.mevduat, 1, 100)], borc: 500)!;
      expect(t.matrah, 0);
    });

    test('borç nisabın altına indirirse zekât düşmez', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 450000)], borc: 100000)!;
      expect(s.nisabaUlasti, isFalse);
      expect(s.zekat, 0);
    });

    test('çok tür: dahil olanlar toplanır, BES/Diğer kapsam dışı', () {
      final s = _hesap([
        _lot(AssetType.altin, 10, 5000, ticker: 'ALTIN_GRAM24'),
        _lot(AssetType.doviz, 1000, 1, ticker: 'USD', para: 'USD'),
        _lot(AssetType.fon, 100, 10, ticker: 'AFT'),
        _lot(AssetType.kripto, 1, 2000, ticker: 'KRIPTO:BTC'),
        _lot(AssetType.emtia, 1, 300, ticker: 'GUMUS'),
        _lot(AssetType.bes, 1, 99999, ticker: 'BES1'),
        _lot(AssetType.diger, 1, 88888, ticker: 'ARABA'),
      ])!;
      // 50.000 + 40.000 (1000 USD × 40) + 1.000 + 2.000 + 300
      expect(s.eskiTutar, closeTo(93300, 1e-6));
      expect(s.haricTurler, {AssetType.bes, AssetType.diger});
    });

    test('satış en eski alımdan düşer (FIFO), kapanmış pozisyon girmez', () {
      final s = _hesap([
        _lot(AssetType.hisse, 10, 100, gunOnce: 500, ticker: 'A'),
        _lot(AssetType.hisse, 10, 100, gunOnce: 30, ticker: 'A'),
        _lot(AssetType.hisse, 15, 100,
            gunOnce: 10, ticker: 'A', kind: AssetKind.sell),
        // Tamamen satılmış pozisyon: aktifLotlar eler.
        _lot(AssetType.hisse, 5, 100, gunOnce: 500, ticker: 'K'),
        _lot(AssetType.hisse, 5, 100,
            gunOnce: 5, ticker: 'K', kind: AssetKind.sell),
      ])!;
      // Elde 5 adet: eski lot tamamen satıldı, kalan 5 yeni lottan.
      expect(s.eskiTutar, 0);
      expect(s.yeniTutar, closeTo(500, 1e-9));
    });

    test('havl dolmuş: yıl içinde eklenenler DAHİL (Hanefi)', () {
      final s = _hesap([
        _lot(AssetType.mevduat, 1, 500000, gunOnce: 400, ticker: 'M'),
        _lot(AssetType.hisse, 1, 100000, gunOnce: 30, ticker: 'H'),
      ])!;
      expect(s.havlDoldu, isTrue);
      expect(s.matrah, closeTo(600000, 1e-6));
      expect(s.zekat, closeTo(15000, 1e-6));
      expect(s.havlTarihi, isNull);
    });

    test('havl dolmamış: zekât yok, yılın dolacağı gün nisaba ulaşılan alış'
        ' + 354', () {
      final s = _hesap([
        _lot(AssetType.mevduat, 1, 200000, gunOnce: 400, ticker: 'M'),
        _lot(AssetType.hisse, 1, 150000, gunOnce: 100, ticker: 'H'),
        _lot(AssetType.fon, 1, 100000, gunOnce: 20, ticker: 'F'),
        _lot(AssetType.altin, 1, 50000, gunOnce: 5, ticker: 'A'),
      ])!;
      // Toplam 500.000 ≥ nisap 400.900, ama bir yıldan eskisi 200.000.
      expect(s.havlDoldu, isFalse);
      expect(s.nisabaUlasti, isFalse);
      expect(s.zekat, 0);
      // 200k + 150k = 350k < nisap; + 100k (20 gün önce) = 450k ≥ nisap.
      expect(s.havlTarihi,
          _bugun.subtract(const Duration(days: 20)).add(const Duration(days: 354)));
    });

    test('toplam nisaba hiç ulaşmıyorsa havl tarihi yok', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 1000, gunOnce: 10)])!;
      expect(s.havlTarihi, isNull);
    });

    test('borç havl dolmuşken matrahı nisap altına indirir', () {
      final s = _hesap([_lot(AssetType.mevduat, 1, 450000, gunOnce: 400)],
          borc: 100000)!;
      expect(s.havlDoldu, isTrue);
      expect(s.nisabaUlasti, isFalse);
    });

    test('fiyatı düşmüş varlık tutara girmez, sayılır', () {
      final s = _hesap([_lot(AssetType.hisse, 10, 0, ticker: 'Z')])!;
      expect(s.eskiTutar, 0);
      expect(s.fiyatsizVarlik, 1);
    });
  });

  group('sheet', () {
    Future<void> ac(WidgetTester t, AsyncValue<ZekatSonucu?> deger,
        {AsyncValue<ZekatSonucu?> Function(double borc)? hesap}) async {
      yaziOlceginiUygula(t);
      await t.pumpWidget(ProviderScope(
        overrides: [
          zekatSonucuProvider
              .overrideWith((ref, borc) => hesap?.call(borc) ?? deger),
        ],
        child: MaterialApp(
          theme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [SandikPalette.dark]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          home: const Scaffold(
            body: SingleChildScrollView(child: ZekatProfilSatiri()),
          ),
        ),
      ));
      await t.tap(find.text('Zekât hesabı'));
      // pumpAndSettle değil: yükleniyor iskeleti sürekli parlar.
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    const dipnot = "Diyanet'in yayımladığı ölçüyle tahmini hesaptır; "
        'dini hüküm için müftülüğe danış.';

    yaziOlcegiEkseni(() {
      testWidgets('nisap üstü: sonuç, nisap ayrıntısı ve dipnot', (t) async {
        await ac(
            t,
            AsyncValue.data(_hesap([
              _lot(AssetType.mevduat, 1, 1000000),
              _lot(AssetType.hisse, 1, 7000, gunOnce: 10, ticker: 'Y'),
              _lot(AssetType.bes, 1, 5, ticker: 'B'),
            ])));
        expect(find.text('Verilecek zekât (%2,5)'), findsOneWidget);
        expect(find.textContaining('80,18 g altın'), findsOneWidget);
        expect(find.text('Yıl içinde eklenenler'), findsOneWidget);
        expect(find.text('Hesaba dahil'), findsOneWidget);
        expect(find.textContaining('BES'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        await t.scrollUntilVisible(find.text(dipnot), 100,
            scrollable: find.byType(Scrollable).last);
        expect(find.text(dipnot), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });

    testWidgets('nisap altı: söz, sonuç tutarı yok', (t) async {
      await ac(t,
          AsyncValue.data(_hesap([_lot(AssetType.mevduat, 1, 1000)])));
      expect(find.textContaining('nisabın altında'), findsOneWidget);
      expect(find.text('Verilecek zekât (%2,5)'), findsNothing);
    });

    testWidgets('kur yokken boş durum: nisap ve sonuç yok, dipnot var',
        (t) async {
      await ac(t, const AsyncValue.data(null));
      expect(find.text('Altın fiyatı şu an alınamadı'), findsOneWidget);
      expect(find.text('Nisap'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(dipnot), findsOneWidget);
    });

    testWidgets('borç yazılınca düşülür (parseTrNumber, bellek içi)',
        (t) async {
      final lotlar = [_lot(AssetType.mevduat, 1, 1000000)];
      await ac(t, const AsyncValue.loading(),
          hesap: (b) => AsyncValue.data(_hesap(lotlar, borc: b)));
      expect(find.text('Düşülen borç'), findsNothing);
      await t.enterText(find.byType(TextField), '600.000');
      await t.pumpAndSettle();
      expect(find.text('Düşülen borç'), findsOneWidget);
      // 400.000 < nisap (80,18 × 5.000 = 400.900)
      expect(find.textContaining('nisabın altında'), findsOneWidget);
    });

    testWidgets('havl dolmamış: tutar yok, "bir yıl dolunca" + gün', (t) async {
      await ac(
          t,
          AsyncValue.data(_hesap([
            _lot(AssetType.mevduat, 1, 500000, gunOnce: 30),
          ])));
      expect(find.text('Bir yıl dolunca hesaplanır.'), findsOneWidget);
      expect(find.textContaining('Portföyün böyle kalırsa yıl'),
          findsOneWidget);
      expect(find.text('Verilecek zekât (%2,5)'), findsNothing);
    });

    testWidgets('portföy yüklenirken iskelet, "fiyat alınamadı" değil',
        (t) async {
      await ac(t, const AsyncValue.loading());
      expect(find.byType(SandikSkeletonList), findsOneWidget);
      expect(find.text('Altın fiyatı şu an alınamadı'), findsNothing);
    });

    testWidgets('Profil satırı ≥44 pt', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: const Scaffold(body: ZekatProfilSatiri()),
      ));
      expect(t.getSize(find.byType(SandikCard)).height,
          greaterThanOrEqualTo(44));
    });
  });
}
