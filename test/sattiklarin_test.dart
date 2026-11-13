// Sattıkların (Premium, 2026-11-12): kapanmış pozisyonlar listesi.
//
// Kilitlenen: (1) kapanmış = satış var VE aktifLotlar boş; kısmi satış,
// yeniden açılan ve silinen pozisyon listede yok; (2) özet kapanış
// özetiyle aynı sayı, maliyet bilinmiyorsa yalnız süre; (3) satır yalnız
// kapanmış pozisyon varken ve Premium görünürken; kilitliyken KilitSatiri
// (kaynak `sattiklarin`); (4) satır sayfayı açar, sayfadaki satır kapanış
// özetini açar; (5) bakiye gizliyse tutar maskeli, yüzde görünür;
// (6) sayfanın başında gerçekleşen toplam: maliyeti bilinmeyen toplama
// girmez, dipnotla söylenir, hepsi bilinmiyorsa yalnız dipnot (2026-11-13).
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
  double genislik = 390,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 1400 * 3);
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

  group('sattiklarinToplami (hesap)', () {
    KapanmisPozisyon k(String ad, double? kar) => KapanmisPozisyon(
          anahtar: ad,
          satis: _lot('${ad}s', ad, AssetKind.sell, _s1, satis: 1),
          ozet: KapanisOzeti(
              ad: ad, yil: 0, ay: 3, gun: 0, karTry: kar, karPct: kar),
        );

    test('karışık: bilinenler toplanır, bilinmeyen sayılır', () {
      final t = sattiklarinToplami(
          [k('A', 300), k('B', null), k('C', -50), k('D', null)]);
      expect(t.karTry, closeTo(250, 1e-9));
      expect(t.bilinen, 2);
      expect(t.bilinmeyen, 2);
    });

    test('hepsi bilinmiyor: toplam null (₺0 yazılmaz)', () {
      final t = sattiklarinToplami([k('A', null), k('B', null)]);
      expect(t.karTry, isNull);
      expect(t.bilinen, 0);
      expect(t.bilinmeyen, 2);
      expect(sattiklarinToplamTutari(t, tutarGizli: false), isNull);
    });

    test('zararlı toplam: eksi işaretli, artı yok', () {
      final t = sattiklarinToplami([k('A', 100), k('B', -400)]);
      expect(t.karTry, closeTo(-300, 1e-9));
      final metin = sattiklarinToplamTutari(t, tutarGizli: false)!;
      expect(metin, isNot(startsWith('+')));
      expect(metin, contains('300'));
      expect(sattiklarinToplamTutari(t, tutarGizli: true),
          const BazPara.lira().gizliTutar);
    });

    test('boş liste: toplam yok, sayılar 0', () {
      expect(sattiklarinToplami(const []),
          const SattiklarinToplami(karTry: null, bilinen: 0, bilinmeyen: 0));
    });

    test('defterden: satırların karTry toplamıyla aynı sayı', () {
      final liste = kapanmisPozisyonlar([
        ..._kapali(),
        _lot('ga', 'GARAN', AssetKind.buy, _a1),
        _lot('gs', 'GARAN', AssetKind.sell, _s1, satis: 80),
        ..._kapali(t: 'ASELS', maliyetYok: true),
      ]);
      final t = sattiklarinToplami(liste);
      expect(t.karTry, closeTo(300 - 200, 1e-9));
      expect(t.bilinen, 2);
      expect(t.bilinmeyen, 1);
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

    testWidgets('özet satırı: toplam, dipnot; satırda "Maliyet bilinmiyor" yok',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _portfoyuAc(tester, [
        acik,
        ..._kapali(),
        _lot('ga', 'GARAN', AssetKind.buy, _a1),
        _lot('gs', 'GARAN', AssetKind.sell, _s1, satis: 80),
        ..._kapali(t: 'ASELS', maliyetYok: true),
      ]);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      expect(
          find.text('Gerçekleşen toplam +₺100 · 2 pozisyon'), findsOneWidget);
      expect(find.text('1 pozisyonun maliyeti bilinmiyor, toplama girmedi'),
          findsOneWidget);
      // Satır listede durur, görünür yazısı yok; okuyucu cümlesi söyler.
      expect(find.byKey(const ValueKey('sattigin_$_uid|hisse|ASELS|TRY')),
          findsOneWidget);
      expect(find.text('Maliyet bilinmiyor'), findsNothing);
      expect(
          find.bySemanticsLabel(
              RegExp(r'^ASELS, 3 ay tuttun, Maliyet bilinmiyor$')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              'Maliyeti bilinen 2 kapanmış pozisyonun gerçekleşen toplam kâr '
              'ya da zararı +₺100.'),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('hepsinin maliyeti bilinmiyor: toplam yok, yalnız dipnot',
        (tester) async {
      await _portfoyuAc(tester, [
        acik,
        ..._kapali(maliyetYok: true),
        ..._kapali(t: 'GARAN', maliyetYok: true),
      ]);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Gerçekleşen toplam'), findsNothing);
      expect(find.text('2 pozisyonun maliyeti bilinmiyor, toplama girmedi'),
          findsOneWidget);
    });

    testWidgets('3.1× yazı, 320 pt: özet, dipnot ve kilit satırı taşmaz',
        (tester) async {
      final defter = [
        acik,
        ..._kapali(),
        ..._kapali(t: 'ASELS', maliyetYok: true),
      ];
      await _portfoyuAc(tester, defter, olcek: 3.1, genislik: 320);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('sattiklarin_satiri')), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sattiklarin_ozet')), findsOneWidget);
      expect(find.byKey(const ValueKey('sattiklarin_dipnot')), findsOneWidget);
      expect(tester.takeException(), isNull);
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
          // Özet satırı + pozisyon satırı.
          findsNWidgets(2));
      expect(find.textContaining('₺300'), findsNothing);
    });

    testWidgets('bakiye gizli: özet satırı da maskeli, okuyucu "gizli" der',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _portfoyuAc(tester, [acik, ..._kapali()], gizli: true);
      await tester.tap(find.byKey(const ValueKey('sattiklarin_satiri')));
      await tester.pumpAndSettle();
      final ozet = find.byKey(const ValueKey('sattiklarin_ozet'));
      expect(
          find.descendant(
              of: ozet,
              matching: find.text(
                  'Gerçekleşen toplam ${const BazPara.lira().gizliTutar} · 1 pozisyon')),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('bakiye gizli olduğu için okunmuyor')),
          findsOneWidget);
      handle.dispose();
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
