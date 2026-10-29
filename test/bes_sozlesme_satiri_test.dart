import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/bes_sozlesme_pozisyonu.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';

/// BES sözleşmesi Portföy'de TEK satır (2026-10-29, yasin: "BES varlığı
/// fon dağılımıyla birlikte tek mi gözükmeli").
///
/// Kilitlenen kararlar:
///   1. İki sözleşmedeki AYNI fon ayrı pozisyondur (`positionKey`
///      sözleşme kimliğini taşır); kimliksiz lot eski anahtarı korur.
///   2. Gruplama görünümdedir: sözleşme satırının değeri/maliyeti fonların
///      toplamı; gruplanmış liste ile gruplanmamış listenin toplamı eşit.
///   3. Satır açılınca fonlar kod + pay + tutarla görünür.
const _uid = 'user-1';
const _s1 = '11111111-0000-4000-8000-000000000001';
const _s2 = '22222222-0000-4000-8000-000000000002';

Asset _bes(
  String id, {
  required String kod,
  required String sozlesme,
  String kurum = 'MetLife Emeklilik',
  double pay = 100,
  double maliyet = 10,
  double fiyat = 12,
  String sub = BesAltKategori.katki,
  AssetKind kind = AssetKind.buy,
  DateTime? tarih,
  String? ad,
}) =>
    Asset(
      id: id,
      userId: _uid,
      name: ad ?? (sub == BesAltKategori.devletKatkisi
          ? '$kurum · $kod · Devlet'
          : '$kurum · $kod'),
      ticker: 'TEFAS:$kod',
      type: AssetType.bes,
      subCategory: sub,
      quantity: pay,
      purchasePrice: maliyet,
      sellPrice: kind == AssetKind.sell ? maliyet : null,
      currency: 'TRY',
      notes: '',
      // Varlık ekranı/sparkline ağa çıkmasın.
      isManualPrice: true,
      currentPrice: fiyat,
      addedDate: tarih ?? DateTime(2026, 3, 1),
      kind: kind,
      sozlesmeId: sozlesme,
    );

Asset _hisse() => Asset(
      id: 'h1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 250,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 300,
      addedDate: DateTime(2026, 3, 14),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('positionKey — sözleşme sınırı', () {
    test('iki sözleşmede aynı fon AYRI pozisyon (birleşme hatası)', () {
      final a = _bes('a', kod: 'AH5', sozlesme: _s1);
      final b = _bes('b', kod: 'AH5', sozlesme: _s2, kurum: 'Anadolu Hayat');
      expect(positionKey(a) == positionKey(b), isFalse);
      expect(aggregatePositions([a, b]).length, 2);
    });

    test('sözleşmesiz BES lotu eski anahtarı korur (veri taşınmaz)', () {
      final eski = Asset.fromSupabase({
        ..._bes('e', kod: 'AH5', sozlesme: _s1).toSupabase(),
        'sozlesme_id': null,
      });
      expect(eski.sozlesmeId, isNull);
      expect(positionKey(eski), 'bes|TEFAS:AH5|sub:katki|TRY');
    });

    test('fon değişimi satışı yalnız kendi sözleşmesinden düşer', () {
      final lotlar = [
        _bes('a', kod: 'AH5', sozlesme: _s1, pay: 100),
        _bes('b', kod: 'AH5', sozlesme: _s2, pay: 50),
        _bes('s', kod: 'AH5', sozlesme: _s1, pay: 100,
            kind: AssetKind.sell, tarih: DateTime(2026, 4, 1)),
      ];
      final p = aggregatePositions(lotlar);
      expect(p.length, 1, reason: 'S1 kapandı, S2 açık kalır');
      expect(p.single.representative.sozlesmeId, _s2);
      expect(p.single.totalQuantity, 50);
    });
  });

  group('besSozlesmeleriniGrupla', () {
    final lotlar = [
      _bes('a', kod: 'AH5', sozlesme: _s1, pay: 100, maliyet: 10, fiyat: 12),
      _bes('b', kod: 'AEA', sozlesme: _s1, pay: 50, maliyet: 20, fiyat: 18),
      _bes('d', kod: 'AEK', sozlesme: _s1, pay: 10, maliyet: 5, fiyat: 6,
          sub: BesAltKategori.devletKatkisi),
      _bes('c', kod: 'AH5', sozlesme: _s2, kurum: 'Anadolu Hayat',
          pay: 40, maliyet: 10, fiyat: 12),
      _hisse(),
    ];
    final pozisyonlar = aggregatePositions(lotlar);
    final satirlar = besSozlesmeleriniGrupla(pozisyonlar);

    test('sözleşme başına bir satır, diğer varlıklar dokunulmaz', () {
      expect(satirlar.length, 3);
      final soz = satirlar.whereType<BesSozlesmePozisyonu>().toList();
      expect(soz.map((s) => s.sozlesmeId).toSet(), {_s1, _s2});
      expect(satirlar.where((p) => p.representative.ticker == 'THYAO.IS'),
          hasLength(1));
    });

    test('toplamlar değişmez: Σ satır == Σ fon', () {
      double deger(Iterable<Position> l) =>
          l.fold(0.0, (s, p) => s + p.totalValue);
      double maliyet(Iterable<Position> l) =>
          l.fold(0.0, (s, p) => s + p.totalCost);
      expect(deger(satirlar), closeTo(deger(pozisyonlar), 1e-9));
      expect(maliyet(satirlar), closeTo(maliyet(pozisyonlar), 1e-9));
      final s1 = satirlar
          .whereType<BesSozlesmePozisyonu>()
          .firstWhere((s) => s.sozlesmeId == _s1);
      // 100×12 + 50×18 + 10×6
      expect(s1.totalValue, closeTo(2160, 1e-9));
      // 100×10 + 50×20 + 10×5
      expect(s1.totalCost, closeTo(2050, 1e-9));
      // Görünüm varlığı aynı sayıyı verir (satırdaki tutar == kâr tabanı).
      final a = s1.asDisplayAsset();
      expect(a.quantity * a.currentPrice, closeTo(2160, 1e-6));
      expect(a.quantity * a.purchasePrice, closeTo(2050, 1e-6));
    });

    test('başlık bilgileri: kurum, fon sayısı, devlet katkısı', () {
      final s1 = satirlar
          .whereType<BesSozlesmePozisyonu>()
          .firstWhere((s) => s.sozlesmeId == _s1);
      expect(s1.kurum, 'MetLife Emeklilik');
      expect(s1.fonSayisi, 2, reason: 'devlet katkısı fonu sayılmaz');
      expect(s1.devletKatkisiVar, isTrue);
      expect(s1.enBuyukFon.representative.ticker, 'TEFAS:AH5');
    });

    test('fon satırları: pay %100 eder, değere göre azalan, getiri', () {
      final s1 = satirlar
          .whereType<BesSozlesmePozisyonu>()
          .firstWhere((s) => s.sozlesmeId == _s1);
      final f = s1.fonSatirlari;
      expect(f.map((x) => x.kod), ['AH5', 'AEA', 'AEK']);
      expect(f.fold<double>(0, (s, x) => s + x.oran), closeTo(100, 1e-9));
      expect(f.first.oran, closeTo(1200 / 2160 * 100, 1e-9));
      expect(f.first.getiriYuzde, closeTo(20, 1e-9));
      expect(f.last.devlet, isTrue);
    });

    test('fiyatı bilinmeyen fon: birim 0, kâr uydurulmaz', () {
      final l = besSozlesmeleriniGrupla(aggregatePositions([
        _bes('a', kod: 'AH5', sozlesme: _s1, fiyat: 12),
        _bes('b', kod: 'AEA', sozlesme: _s1, fiyat: 0),
      ]));
      final s = l.single as BesSozlesmePozisyonu;
      expect(s.asDisplayAsset().currentPrice, 0);
      expect(s.fonSatirlari.last.getiriYuzde, isNull);
    });

    test('ortak satırı (BirlesikPozisyon) gruplanmaz', () {
      final ortak = BirlesikPozisyon.parcalardan(
          aggregatePositions([_hisse()]) +
              aggregatePositions([
                Asset.fromSupabase(
                    {..._hisse().toSupabase(), 'user_id': 'diger'}),
              ]));
      expect(besSozlesmeleriniGrupla([ortak]).single, same(ortak));
    });
  });

  group('Portföy listesi', () {
    Future<void> pump(WidgetTester tester, List<Asset> assets,
        {Map<String, Sozlesme> sozlesmeler = const {}}) async {
      tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
          partnersProvider.overrideWith(_FakePartners.new),
          sozlesmeProvider.overrideWith(() => _FakeSozlesme(sozlesmeler)),
        ],
        child:
            MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('sözleşme tek satır; ok fonları açar', (tester) async {
      await pump(tester, [
        _bes('a', kod: 'AH5', sozlesme: _s1, pay: 100, fiyat: 12),
        _bes('b', kod: 'AEA', sozlesme: _s1, pay: 50, fiyat: 18),
        _bes('c', kod: 'AH5', sozlesme: _s2, kurum: 'Anadolu Hayat',
            pay: 40),
      ]);
      expect(find.text('MetLife Emeklilik · BES'), findsOneWidget);
      expect(find.text('Anadolu Hayat · BES'), findsOneWidget);
      expect(find.text('2 fon'), findsOneWidget);
      // Fon kodları kapalı satırda yok.
      expect(find.text('AEA'), findsNothing);

      await tester.tap(find
          .descendant(
              of: find.ancestor(
                  of: find.text('MetLife Emeklilik · BES'),
                  matching: find.byType(Row)).first,
              matching: find.byIcon(Icons.keyboard_arrow_down_rounded))
          .first);
      await tester.pumpAndSettle();
      expect(find.text('AEA'), findsOneWidget);
      expect(find.text('AH5'), findsOneWidget,
          reason: 'yalnız açılan sözleşmenin fonları');
      // Pay: 1200 / 2100 → %57, 900 / 2100 → %43.
      expect(find.textContaining('57'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('eski biçimli lot adı: başlık sözleşmenin kurumunu yazar',
        (tester) async {
      // e2e 2026-10-29: lot adı "Kurum · " önekini taşımayan eski sözleşme
      // satırda yalnız "BES", kartta "BES · Anadolu Hayat" yazıyordu.
      await pump(tester, [
        _bes('a', kod: 'AH5', sozlesme: _s1, pay: 100, ad: 'AH5'),
      ], sozlesmeler: {
        _s1: Sozlesme(
          id: _s1,
          userId: _uid,
          tur: SozlesmeTuru.bes,
          kurum: 'Anadolu Hayat',
          baslangic: DateTime(2020, 1, 1),
        ),
      });
      expect(find.text('Anadolu Hayat · BES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('büyük yazıda (×2) taşma yok', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, [
        _bes('a', kod: 'AH5', sozlesme: _s1, pay: 100, fiyat: 12),
        _bes('b', kod: 'AEA', sozlesme: _s1, pay: 50, fiyat: 18),
      ]);
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakeSozlesme extends SozlesmeNotifier {
  _FakeSozlesme(this._s);
  final Map<String, Sozlesme> _s;

  @override
  Future<SozlesmeState> build() async => SozlesmeState(sozlesmeler: _s);
}
