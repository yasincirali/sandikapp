// Sattıkların (Premium, 2026-11-12): kapanmış pozisyonlar listesi.
//
// Kilitlenen: (1) kapanmış = satış var VE aktifLotlar boş; kısmi satış,
// yeniden açılan ve silinen pozisyon listede yok; (2) özet kapanış
// özetiyle aynı sayı, maliyet bilinmiyorsa yalnız süre; (3) satır yalnız
// kapanmış pozisyon varken ve Premium görünürken; kilitliyken KilitSatiri
// (kaynak `sattiklarin`); (4) satır sayfayı açar, sayfadaki satır kapanış
// özetini açar; (5) bakiye gizliyse tutar maskeli, yüzde görünür.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kapanis_ozeti.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show balanceHiddenProvider, premiumKilitliProvider;
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/kapanis_ozeti_sheet.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:portfoy_takip/widgets/sattiklarin.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'user-1';

Asset _lot(
  String id,
  String ticker,
  AssetKind kind,
  DateTime tarih, {
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  bool? maliyetYok,
  String userId = _uid,
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: userId,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      kind: kind,
      sellPrice: satis,
      currentPrice: fiyat,
      addedDate: tarih,
      createdAt: tarih,
      deletedAt: silindi,
    )..maliyetBilinmiyor = maliyetYok;

final _a1 = DateTime(2026, 2, 1);
final _s1 = DateTime(2026, 5, 1);

/// THYAO: 10 × 100 alındı, 10 × 130 satıldı (3 ay, +₺300, +%30).
List<Asset> _kapali({String t = 'THYAO', bool? maliyetYok}) => [
      _lot('${t}a', t, AssetKind.buy, _a1, maliyetYok: maliyetYok),
      _lot('${t}s', t, AssetKind.sell, _s1, satis: 130),
    ];

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

Future<void> _portfoyuAc(
  WidgetTester tester,
  List<Asset> varliklar, {
  bool gorunur = true,
  bool kilitli = false,
  bool gizli = false,
  double olcek = 1,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
      premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(olcek)),
          child: child!),
      home: const PortfolioScreen(),
    ),
  ));
  await tester.pump();
  if (gizli) {
    await ProviderScope.containerOf(
            tester.element(find.byType(PortfolioScreen)))
        .read(balanceHiddenProvider.notifier)
        .set(true);
  }
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  // Bakiye gizleme tercihi testler arasında sızmasın.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('kapanmisPozisyonlar (hesap)', () {
    test('tamamı satılan pozisyon listede; özet kapanış özetiyle aynı', () {
      final defter = _kapali();
      final liste = kapanmisPozisyonlar(defter);
      expect(liste, hasLength(1));
      expect(liste.single.satis.id, 'THYAOs');
      expect(
          liste.single.ozet, kapanisOzeti(defter: defter, satis: defter.last));
      expect(liste.single.ozet.karTry, closeTo(300, 1e-9));
      expect(liste.single.ozet.karPct, closeTo(30, 1e-9));
      expect(liste.single.ozet.ay, 3);
    });

    test('kısmi satış listede yok', () {
      final defter = [
        _lot('a', 'THYAO', AssetKind.buy, _a1),
        _lot('s', 'THYAO', AssetKind.sell, _s1, miktar: 4, satis: 130),
      ];
      expect(kapanmisPozisyonlar(defter), isEmpty);
    });

    test('kapanıp yeniden alınan (bugün açık) pozisyon listede yok', () {
      final defter = [
        ..._kapali(),
        _lot('b', 'THYAO', AssetKind.buy, DateTime(2026, 6, 1), miktar: 3),
      ];
      expect(kapanmisPozisyonlar(defter), isEmpty);
    });

    test('silinmiş pozisyon ve alışsız satış listede yok', () {
      final sil = DateTime(2026, 6, 1);
      expect(
          kapanmisPozisyonlar([
            _lot('a', 'THYAO', AssetKind.buy, _a1, silindi: sil),
            _lot('s', 'THYAO', AssetKind.sell, _s1, satis: 130, silindi: sil),
          ]),
          isEmpty);
      expect(
          kapanmisPozisyonlar(
              [_lot('s', 'THYAO', AssetKind.sell, _s1, satis: 130)]),
          isEmpty);
    });

    test('maliyet bilinmiyorsa yalnız süre (uydurma sayı yok)', () {
      final o = kapanmisPozisyonlar(_kapali(maliyetYok: true)).single.ozet;
      expect(o.karTry, isNull);
      expect(o.karPct, isNull);
      expect(o.ay, 3);
      expect(sattiginSonucu(o, tutarGizli: false), isNull);
    });

    test('iki tur: özet son kapanıştan; en son kapanan önde; sahip ayrı', () {
      final defter = [
        ..._kapali(),
        _lot('a2', 'THYAO', AssetKind.buy, DateTime(2026, 6, 1), fiyat: 200),
        _lot('s2', 'THYAO', AssetKind.sell, DateTime(2026, 6, 20),
            fiyat: 200, satis: 180),
        _lot('ga', 'GARAN', AssetKind.buy, _a1),
        _lot('gs', 'GARAN', AssetKind.sell, DateTime(2026, 3, 1), satis: 90),
        // Ortağın aynı sembollü lotları kullanıcının kapanışını bozmaz.
        _lot('pa', 'THYAO', AssetKind.buy, _a1, userId: 'ortak'),
      ];
      final liste = kapanmisPozisyonlar(defter);
      expect(liste.map((k) => k.satis.id), ['s2', 'gs']);
      expect(liste.first.ozet.gun, 19);
      expect(liste.first.ozet.karTry, closeTo(-200, 1e-9));
    });

    test('sonuç metni: tutar işaretli, gizliyken maskeli, yüzde görünür', () {
      final o = kapanmisPozisyonlar(_kapali()).single.ozet;
      final acik = sattiginSonucu(o, tutarGizli: false)!;
      expect(acik, startsWith('+'));
      expect(acik, contains('%30'));
      final gizli = sattiginSonucu(o, tutarGizli: true)!;
      expect(gizli, startsWith(const BazPara.lira().gizliTutar));
      expect(gizli, contains('%30'));
    });
  });

  group('Portföy › Sattıkların satırı', () {
    final acik = _lot('k', 'KCHOL', AssetKind.buy, _a1);

    testWidgets('kapanmış pozisyon yoksa satır yok', (tester) async {
      await _portfoyuAc(tester, [
        acik,
        _lot('a', 'THYAO', AssetKind.buy, _a1),
        _lot('s', 'THYAO', AssetKind.sell, _s1, miktar: 4, satis: 130),
      ]);
      expect(find.byKey(const ValueKey('sattiklarin_satiri')), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('paywall kapalı (Premium görünmüyor): satır yok',
        (tester) async {
      await _portfoyuAc(tester, [acik, ..._kapali()], gorunur: false);
      expect(find.byKey(const ValueKey('sattiklarin_satiri')), findsNothing);
      expect(find.text('Sattıkların (1)'), findsNothing);
    });

    testWidgets('kilitli: KilitSatiri, kaynak sattiklarin, ≥44 pt',
        (tester) async {
      await _portfoyuAc(tester, [acik, ..._kapali()], kilitli: true);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'sattiklarin');
      expect(kilit.ozellik, 'sattiklarin');
      expect(find.text('Sattıkların (1)'), findsNothing);
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('satır → liste sayfası → kapanış özeti', (tester) async {
      await _portfoyuAc(tester, [acik, ..._kapali()]);
      final satir = find.byKey(const ValueKey('sattiklarin_satiri'));
      expect(find.text('Sattıkların (1)'), findsOneWidget);
      expect(tester.getSize(satir).height, greaterThanOrEqualTo(44));

      await tester.tap(satir);
      await tester.pumpAndSettle();
      expect(find.byType(SattiklarinSayfasi), findsOneWidget);
      expect(find.text('3 ay tuttun'), findsOneWidget);
      final hedef =
          find.byKey(const ValueKey('sattigin_$_uid|hisse|THYAO|TRY'));
      expect(hedef, findsOneWidget);
      await tester.tap(hedef);
      await tester.pumpAndSettle();
      expect(find.byType(SattiklarinSayfasi), findsNothing);
      expect(find.byType(KapanisOzetiSayfasi), findsOneWidget);
      // Kazançta paylaş var (kural kapanış özetinde aynen).
      expect(find.byKey(const ValueKey('kapanis_paylas')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('her şey satılmışsa boş durumun altında da satır',
        (tester) async {
      await _portfoyuAc(tester, _kapali());
      expect(find.text('Sattıkların (1)'), findsOneWidget);
    });

    testWidgets('bakiye gizli: listede tutar maskeli', (tester) async {
      await _portfoyuAc(tester, [acik, ..._kapali()], gizli: true);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      expect(
          find.descendant(
              of: find.byType(SattiklarinSayfasi),
              matching: find.textContaining(const BazPara.lira().gizliTutar)),
          findsOneWidget);
      expect(find.textContaining('₺300'), findsNothing);
    });

    testWidgets('2× yazı: liste taşmaz, ekran okuyucu tek cümle',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _portfoyuAc(tester, [acik, ..._kapali()], olcek: 2);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^THYAO, 3 ay tuttun, Gerçekleşen kâr/zarar \+')),
          findsOneWidget);
      handle.dispose();
    });
  });
}
