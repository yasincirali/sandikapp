import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gorunum_kapsami.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/portfolio_cache.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Çoklu portföy (0133) — toplama değişmezi ve yazma kuralları.
///
/// Değişmezi kilitleyen testler formülü YENİDEN ÜRETMEZ (kırılım değişmezi
/// dersi): toplamlar `PortfolioState`'in gerçek getter'larından, kapsam
/// `gorunum_kapsami.dart`'tan, işlem satırının portföyü
/// `islemPortfoyu`/`yeniSatirPortfoyu`'dan gelir — notifier'ın kullandığı
/// fonksiyonların kendisi.

const _a = 'pf-a';
const _b = 'pf-b';
const _bilinen = {_a, _b};

var _sayac = 0;

Asset _lot(
  String ticker, {
  double qty = 10,
  double fiyat = 100,
  double guncel = 150,
  String? portfoy,
  AssetKind kind = AssetKind.buy,
  double? satis,
  double temettu = 0,
  String owner = 'me',
  String? sozlesme,
  DateTime? silindi,
  AssetType type = AssetType.hisse,
  DateTime? tarih,
}) =>
    Asset(
      id: 'l${_sayac++}',
      userId: owner,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: guncel,
      addedDate: tarih ?? DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      portfoyId: portfoy,
      sozlesmeId: sozlesme,
      deletedAt: silindi,
    );

PortfolioState _durum(List<Asset> lots) => PortfolioState(assets: lots);

List<Asset> _portfoy(List<Asset> defter, String secim) =>
    portfoyLotlari(defter, secim, _bilinen);

/// Notifier'ın `addSellTransaction`'ı ile AYNI kurallar: maliyet ve kur
/// pozisyon görünümünden, portföy `islemPortfoyu`'ndan.
Asset _sat(Asset pozisyon, double qty, double fiyat, List<Asset> defter) =>
    Asset(
      id: 'l${_sayac++}',
      userId: pozisyon.userId,
      name: pozisyon.name,
      ticker: pozisyon.ticker,
      type: pozisyon.type,
      quantity: qty,
      purchasePrice: pozisyon.purchasePrice,
      currency: pozisyon.currency,
      notes: '',
      isManualPrice: pozisyon.isManualPrice,
      purchaseFxRate: pozisyon.purchaseFxRate,
      currentPrice: pozisyon.currentPrice,
      kind: AssetKind.sell,
      sellPrice: fiyat,
      addedDate: DateTime(2026, 3, 1),
      refAssetId: null,
      portfoyId: islemPortfoyu(pozisyon, bayrak: true, defter: defter),
    );

Asset _pozisyon(List<Asset> lots, String ticker) => aggregatePositions(lots)
    .firstWhere((p) => p.representative.ticker == ticker)
    .asDisplayAsset();

void main() {
  setUp(() {
    RemoteConfigService.testAcik = {};
  });
  tearDown(() {
    RemoteConfigService.testAcik = {};
  });

  // Ana (NULL) + A + B; satış, temettü, silinmiş lot, mezar taşı, sözleşme.
  List<Asset> karisikDefter() => [
        _lot('THYAO', qty: 10, fiyat: 100, guncel: 300),
        _lot('THYAO', kind: AssetKind.sell, qty: 4, fiyat: 100, satis: 250),
        _lot('AKBNK', qty: 50, fiyat: 40, guncel: 60, portfoy: _a),
        _lot('AKBNK',
            kind: AssetKind.dividend,
            qty: 0,
            fiyat: 0,
            temettu: 120,
            portfoy: _a),
        _lot('SISE', qty: 5, fiyat: 30, guncel: 45, portfoy: _b),
        _lot('SISE',
            qty: 5, fiyat: 30, portfoy: _b, silindi: DateTime(2026, 2, 1)),
        _lot('KCHOL', qty: 7, fiyat: 150, guncel: 200, portfoy: _b),
        _lot('KCHOL',
            kind: AssetKind.sell, qty: 7, fiyat: 150, satis: 190, portfoy: _b),
        _lot('BES',
            qty: 100,
            fiyat: 1,
            guncel: 1.2,
            sozlesme: 's1',
            type: AssetType.bes),
        // Bilinmeyen portföy (başka cihazda silindi, defter tazelenmedi).
        _lot('EREGL', qty: 3, fiyat: 50, guncel: 55, portfoy: 'silinmis'),
      ];

  group('kapsam: portföy süzgeci', () {
    test('NULL ve bilinmeyen kimlik Ana\'da; her lot tam bir parçada', () {
      final d = karisikDefter();
      final ana = _portfoy(d, PortfoySecimi.ana);
      final a = _portfoy(d, _a);
      final b = _portfoy(d, _b);
      expect(ana.map((x) => x.ticker).toSet(), {'THYAO', 'BES', 'EREGL'});
      expect(a.map((x) => x.ticker).toSet(), {'AKBNK'});
      expect(b.map((x) => x.ticker).toSet(), {'SISE', 'KCHOL'});
      expect(ana.length + a.length + b.length, d.length,
          reason: 'her lot tam bir portföye düşer');
      final bol = portfoyeGoreBol(d, _bilinen);
      expect(bol.values.fold<int>(0, (t, l) => t + l.length), d.length);
    });

    test('Tümü: aynı liste nesnesi', () {
      final d = karisikDefter();
      expect(identical(_portfoy(d, PortfoySecimi.tumu), d), isTrue);
    });

    test('Σ portföy == Tümü: değer, temettü, gerçekleşen, maliyet', () {
      final d = karisikDefter();
      final tumu = _durum(d);
      final parcalar = [
        for (final s in [PortfoySecimi.ana, _a, _b]) _durum(_portfoy(d, s)),
      ];
      double topla(double Function(PortfolioState) f) =>
          parcalar.fold(0.0, (t, p) => t + f(p));
      expect(topla((p) => p.totalValue), closeTo(tumu.totalValue, 1e-6));
      expect(topla((p) => p.totalDividend), closeTo(tumu.totalDividend, 1e-6));
      expect(topla((p) => p.realizedGainLoss),
          closeTo(tumu.realizedGainLoss, 1e-6));
      // Aynı sembol iki portföyde DEĞİLKEN maliyet de birebir toplanır.
      expect(topla((p) => p.totalCost), closeTo(tumu.totalCost, 1e-6));
      expect(topla((p) => p.gainLoss), closeTo(tumu.gainLoss, 1e-6));
    });

    test('portföy yalnız Ben kapsamına uygulanır; ortak lotları girmez', () {
      final benim = karisikDefter();
      // Ortağın kendi portföyü olabilir (onun kimliği); bizim seçicide yok.
      final ortak = [
        _lot('THYAO', owner: 'p1', portfoy: _a),
        _lot('GARAN', owner: 'p1'),
      ];
      final ortaklar = {'p1': ortak};
      final benA = kapsamDefteri(
          kisi: '',
          benim: benim,
          ortaklar: ortaklar,
          portfoy: _a,
          bilinenPortfoyler: _bilinen);
      expect(benA.every((x) => x.userId == 'me'), isTrue);
      // Ortak görünümü ve Birlikte portföy seçiminden ETKİLENMEZ.
      for (final kisi in <String?>['p1', null]) {
        expect(
            kapsamDefteri(
                    kisi: kisi,
                    benim: benim,
                    ortaklar: ortaklar,
                    portfoy: _a,
                    bilinenPortfoyler: _bilinen)
                .map((x) => x.id),
            kapsamDefteri(kisi: kisi, benim: benim, ortaklar: ortaklar)
                .map((x) => x.id));
      }
    });
  });

  group('aynı sembol iki portföyde', () {
    // A: 10 @ 100, B: 10 @ 200, güncel 150. A'dan 10 @ 150 satılır.
    List<Asset> defter() => [
          _lot('ASELS', qty: 10, fiyat: 100, guncel: 150, portfoy: _a),
          _lot('ASELS', qty: 10, fiyat: 200, guncel: 150, portfoy: _b),
        ];

    test('her portföy kendi ağırlıklı maliyetini görür', () {
      final d = defter();
      expect(_pozisyon(_portfoy(d, _a), 'ASELS').purchasePrice, 100);
      expect(_pozisyon(_portfoy(d, _b), 'ASELS').purchasePrice, 200);
      // Tümü eski hesap: havuz ortalaması.
      expect(_pozisyon(d, 'ASELS').purchasePrice, 150);
    });

    test('Tümü görünümü karışık; A görünümü A\'nın portföyünü taşır', () {
      final d = defter();
      final tumu = _pozisyon(d, 'ASELS');
      expect(tumu.portfoyKarisik, isTrue);
      expect(tumu.portfoyId, isNull);
      expect(() => islemPortfoyu(tumu, bayrak: true, defter: d),
          throwsArgumentError,
          reason: 'karışık pozisyona satış Ana\'ya düşmemeli');
      final a = _pozisyon(_portfoy(d, _a), 'ASELS');
      expect(a.portfoyKarisik, isFalse);
      expect(a.portfoyId, _a);
    });

    test('A\'dan satış: B tabanı 2.000, A gerçekleşen kâr doğru, Σ korunur',
        () {
      var d = defter();
      final aPoz = _pozisyon(_portfoy(d, _a), 'ASELS');
      d = [...d, _sat(aPoz, 10, 150, d)];

      final a = _durum(_portfoy(d, _a));
      final b = _durum(_portfoy(d, _b));
      final tumu = _durum(d);

      // Satış A'da kaldı, A'nın maliyetiyle (100) yazıldı.
      expect(d.last.portfoyId, _a);
      expect(d.last.purchasePrice, 100);
      expect(a.totalValue, 0, reason: 'A kapandı');
      expect(a.realizedGainLoss, closeTo(500, 1e-9)); // (150-100)×10
      // Satış portföy dışına TAŞMAZ: B'nin miktarı ve tabanı aynen.
      expect(b.totalCost, closeTo(2000, 1e-9));
      expect(b.totalValue, closeTo(1500, 1e-9));
      expect(_portfoy(d, PortfoySecimi.ana), isEmpty);
      // Değer ve gerçekleşen kâr Tümü'ye birebir toplanır.
      expect(a.totalValue + b.totalValue, closeTo(tumu.totalValue, 1e-9));
      expect(a.realizedGainLoss + b.realizedGainLoss,
          closeTo(tumu.realizedGainLoss, 1e-9));
    });

    test('Tümü maliyeti bugünkü (havuz) hesaptır — bilinen v1 farkı', () {
      // Tümü BİREBİR eski kullanıcı toplamı (kullanıcı kuralı): havuzun
      // ağırlıklı ortalaması 150, elde 10 → taban 1.500. Portföylerin
      // toplamı ise 2.000 (B'nin gerçek tabanı). Değer/temettü/gerçekleşen
      // birebir toplanır; açık maliyet yalnız bu durumda (aynı sembol iki
      // portföyde VE birinden satış) ayrışır. TECHNICAL_DEBT.md'de.
      var d = defter();
      d = [...d, _sat(_pozisyon(_portfoy(d, _a), 'ASELS'), 10, 150, d)];
      expect(_durum(d).totalCost, closeTo(1500, 1e-9));
      expect(_durum(_portfoy(d, _b)).totalCost, closeTo(2000, 1e-9));
    });

    test('portfoyParcalari: portföy başına açık pozisyon', () {
      final d = defter();
      final p = portfoyParcalari(d, d.first, _bilinen);
      expect(p.keys.toSet(), {_a, _b});
      expect(p[_a]!.weightedPurchasePrice, 100);
      expect(p[_b]!.weightedPurchasePrice, 200);
      expect(p[_a]!.asDisplayAsset().portfoyId, _a);
    });
  });

  group('yazma kuralları', () {
    test('bayrak kapalı: hiçbir satır portföy almaz', () {
      expect(yeniSatirPortfoyu(bayrak: false, portfoyId: _a), isNull);
      final poz = _lot('X', portfoy: _a);
      expect(islemPortfoyu(poz, bayrak: false), isNull);
      // Karışık bile olsa bayrak kapalıyken eski yol (atmaz).
      final karisik = Asset(
          id: 'pos:x',
          userId: 'me',
          name: 'X',
          ticker: 'X',
          type: AssetType.hisse,
          quantity: 1,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          portfoyKarisik: true);
      expect(islemPortfoyu(karisik, bayrak: false), isNull);
    });

    test('sözleşmeli lot sözleşmesinin portföyünü izler', () {
      final d = [
        _lot('AH5', sozlesme: 's1', portfoy: _b, type: AssetType.bes),
      ];
      expect(
          yeniSatirPortfoyu(
              bayrak: true, portfoyId: _a, sozlesmeId: 's1', defter: d),
          _b,
          reason: 'BES katkısı formdaki seçime değil sözleşmeye gider');
      expect(
          yeniSatirPortfoyu(
              bayrak: true, portfoyId: _a, sozlesmeId: 's2', defter: d),
          _a,
          reason: 'yeni sözleşme formda seçilen portföye');
    });

    test('NULL lotlar Ana\'da kalır: Ana görünümünde satış Ana\'ya', () {
      final d = [_lot('TUPRS', qty: 5)];
      final poz = _pozisyon(_portfoy(d, PortfoySecimi.ana), 'TUPRS');
      expect(poz.portfoyId, isNull);
      expect(poz.portfoyKarisik, isFalse);
      expect(islemPortfoyu(poz, bayrak: true, defter: d), isNull);
    });
  });

  group('pozisyon taşıma (bütün pozisyon)', () {
    test('kaynaktaki bütün geçmiş taşınır, başka portföy/ortak taşınmaz', () {
      final d = [
        _lot('ASELS', portfoy: _a),
        _lot('ASELS', kind: AssetKind.sell, qty: 2, satis: 120, portfoy: _a),
        _lot('ASELS',
            kind: AssetKind.dividend, qty: 0, temettu: 10, portfoy: _a),
        _lot('ASELS', portfoy: _a, silindi: DateTime(2026, 2, 1)),
        _lot('ASELS', kind: AssetKind.deleteLog, portfoy: _a),
        _lot('ASELS', portfoy: _b), // başka portföy
        _lot('ASELS', owner: 'p1', portfoy: _a), // ortak
        _lot('GARAN', portfoy: _a), // başka sembol
      ];
      final t = tasinacakLotlar(d, d.first, _a, _bilinen);
      expect(t.map((x) => x.id), [for (final x in d.take(5)) x.id]);
    });

    test('sözleşmeli pozisyon: sözleşmenin bütün fonları birlikte', () {
      final d = [
        _lot('AH5', sozlesme: 's1', type: AssetType.bes),
        _lot('AH2', sozlesme: 's1', type: AssetType.bes),
        _lot('AH9', sozlesme: 's2', type: AssetType.bes),
      ];
      final t = tasinacakLotlar(d, d.first, null, _bilinen);
      expect(t.map((x) => x.ticker).toSet(), {'AH5', 'AH2'});
    });

    test('taşıma sonrası Tümü değişmez, Σ portföy == Tümü korunur', () {
      final d = karisikDefter();
      final once = _durum(d);
      final thy = d.firstWhere((x) => x.ticker == 'THYAO');
      final ids = {
        for (final x in tasinacakLotlar(d, thy, null, _bilinen)) x.id
      };
      final sonra = [
        for (final x in d) ids.contains(x.id) ? x.copyWithPortfoy(_a) : x,
      ];
      final tumu = _durum(sonra);
      expect(tumu.totalValue, closeTo(once.totalValue, 1e-9));
      expect(tumu.totalCost, closeTo(once.totalCost, 1e-9));
      expect(tumu.realizedGainLoss, closeTo(once.realizedGainLoss, 1e-9));
      final parcalar = [
        for (final s in [PortfoySecimi.ana, _a, _b]) _durum(_portfoy(sonra, s)),
      ];
      expect(parcalar.fold<double>(0, (t, p) => t + p.totalValue),
          closeTo(tumu.totalValue, 1e-9));
      // THYAO'nun satışı da taşındı: A'da açık 6 lot, Ana'da THYAO yok.
      expect(_portfoy(sonra, _a).where((x) => x.ticker == 'THYAO').length, 2);
      expect(_portfoy(sonra, PortfoySecimi.ana).any((x) => x.ticker == 'THYAO'),
          isFalse);
    });
  });

  group('model ve serileştirme', () {
    test('toSupabase: bayrak kapalıyken portfoy_id YAZILMAZ', () {
      final l = _lot('X', portfoy: _a);
      expect(l.toSupabase().containsKey('portfoy_id'), isFalse);
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      expect(l.toSupabase()['portfoy_id'], _a);
      // Ana (null) hiçbir zaman anahtar olarak gitmez: eski gövde.
      expect(_lot('Y').toSupabase().containsKey('portfoy_id'), isFalse);
    });

    test(
        'bayrak kapalı + Ana lot: gövde çoklu portföy öncesiyle aynı anahtarlar',
        () {
      final anahtarlar = _lot('Y').toSupabase().keys.toSet();
      expect(anahtarlar.contains('portfoy_id'), isFalse);
      expect(anahtarlar.length, 23);
    });

    test('fromSupabase okur; kopyacılar taşır', () {
      final m = (_lot('X')..notes = 'n').toSupabase()..['portfoy_id'] = _b;
      final a = Asset.fromSupabase(m);
      expect(a.portfoyId, _b);
      expect(a.copyWithDeletedAt(DateTime(2026)).portfoyId, _b);
      expect(a.copyWithNotes('x').portfoyId, _b);
      expect(a.copyWithPortfoy(null).portfoyId, isNull);
      expect(Asset.fromSupabase(_lot('Y').toSupabase()).portfoyId, isNull);
    });

    test('asDisplayAsset: tek portföy taşınır, bayrak öncesi defterde null',
        () {
      expect(_pozisyon([_lot('X', portfoy: _a)], 'X').portfoyId, _a);
      final eski = _pozisyon([_lot('X'), _lot('X')], 'X');
      expect(eski.portfoyId, isNull);
      expect(eski.portfoyKarisik, isFalse);
    });

    test('PortfolioCache bayraktan bağımsız portföyü saklar', () async {
      SharedPreferences.setMockInitialValues({});
      await PortfolioCache.write('u', [_lot('X', portfoy: _a), _lot('Y')]);
      final geri = await PortfolioCache.read('u');
      expect(geri!.map((x) => x.portfoyId), [_a, null]);
    });

    test('Portfoy ad kuralı sunucuyla aynı (1–40, kırpılmış)', () {
      expect(Portfoy.adGecerli('  '), isFalse);
      expect(Portfoy.adGecerli('Emeklilik'), isTrue);
      expect(Portfoy.adGecerli('x' * 40), isTrue);
      expect(Portfoy.adGecerli('x' * 41), isFalse);
    });
  });

  group('sağlayıcılar: görünürlük, kapsam, sınır', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    ProviderContainer kap({
      required bool paywall,
      bool premium = false,
      bool admin = false,
      List<Portfoy> liste = const [],
    }) {
      final c = ProviderContainer(overrides: [
        paywallVisibleProvider.overrideWithValue(paywall),
        gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
        magazaPremiumProvider.overrideWith((_) => premium),
        gecerliPremiumHakkiProvider.overrideWithValue(null),
        isPushAdminProvider.overrideWith((_) async => admin),
        portfoylerProvider.overrideWith(() => _SabitPortfoyler(liste)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    final iki = [
      const Portfoy(id: _a, userId: 'me', ad: 'Emeklilik', sira: 1),
      const Portfoy(id: _b, userId: 'me', ad: 'Çocuk', sira: 2),
    ];

    test('bayrak kapalı: görünmez, kapsam HEP Tümü (seçim kayıtlı olsa da)',
        () async {
      final c = kap(paywall: true, liste: iki);
      await c.read(seciliPortfoyProvider.notifier).set(_a);
      await c.read(portfoylerProvider.future);
      expect(c.read(cokluPortfoyGorunurProvider), isFalse);
      expect(c.read(portfoyKapsamiProvider).secim, PortfoySecimi.tumu);
      expect(c.read(varsayilanYeniPortfoyProvider), isNull);
    });

    test('bayrak açık, paywall kapalı, admin değil: görünmez', () async {
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      final c = kap(paywall: false, liste: iki);
      await c.read(seciliPortfoyProvider.notifier).set(_a);
      await c.read(portfoylerProvider.future);
      expect(c.read(cokluPortfoyGorunurProvider), isFalse);
      expect(c.read(portfoyKapsamiProvider).secim, PortfoySecimi.tumu);
    });

    test('bayrak + paywall: seçim uygulanır; silinmiş seçim Tümü\'ye düşer',
        () async {
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      final c = kap(paywall: true, liste: iki);
      await c.read(portfoylerProvider.future);
      await c.read(seciliPortfoyProvider.notifier).set(_b);
      expect(c.read(cokluPortfoyGorunurProvider), isTrue);
      expect(c.read(portfoyKapsamiProvider).secim, _b);
      expect(c.read(varsayilanYeniPortfoyProvider), _b);
      await c.read(seciliPortfoyProvider.notifier).set(PortfoySecimi.ana);
      expect(c.read(portfoyKapsamiProvider).secim, PortfoySecimi.ana);
      expect(c.read(varsayilanYeniPortfoyProvider), isNull);
      await c.read(seciliPortfoyProvider.notifier).set('yok');
      expect(c.read(portfoyKapsamiProvider).secim, PortfoySecimi.tumu);
    });

    test('admin paywall kapalıyken de görür', () async {
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      final c = kap(paywall: false, admin: true, liste: iki);
      await c.read(isPushAdminProvider.future);
      expect(c.read(cokluPortfoyGorunurProvider), isTrue);
    });

    test('adlandırılmış portföy yokken Ana == Tümü (tek önbellek anahtarı)',
        () async {
      RemoteConfigService.testAcik = {'coklu_portfoy'};
      final c = kap(paywall: true);
      await c.read(portfoylerProvider.future);
      await c.read(seciliPortfoyProvider.notifier).set(PortfoySecimi.ana);
      expect(c.read(portfoyKapsamiProvider).secim, PortfoySecimi.tumu);
    });

    test('sınır: ücretsiz 1 (Ana), Premium ve paywall kapalı sınırsız',
        () async {
      final ucretsiz = kap(paywall: true);
      await ucretsiz.read(portfoylerProvider.future);
      expect(ucretsiz.read(portfoyLimitProvider), 1);
      expect(ucretsiz.read(portfoySiniriDoluProvider), isTrue,
          reason: 'ücretsizde ikinci portföy paywall açar');
      final prem = kap(paywall: true, premium: true, liste: iki);
      await prem.read(portfoylerProvider.future);
      expect(prem.read(portfoySiniriDoluProvider), isFalse);
      final kapali = kap(paywall: false);
      expect(kapali.read(portfoyLimitProvider), greaterThan(1000));
    });

    test('seçili portföy kullanıcıya özel ve listede', () {
      expect(kullaniciyaOzelTercihler, contains(seciliPortfoyProvider));
    });
  });
}

class _SabitPortfoyler extends PortfoylerNotifier {
  _SabitPortfoyler(this.liste);
  final List<Portfoy> liste;
  @override
  Future<List<Portfoy>> build() async => liste;
}
