import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/varlik_widget_service.dart';

import 'helpers/kaynak.dart';

/// Tek varlık widget'ı: iOS (Ar-Ge kararı 2026-10-24 §1) ve Android
/// (yasin onayı 2026-10-25).
///
/// Swift bu ortamda derlenmiyor ve iOS derlemesi yalnız `main` birleşmesinde
/// TestFlight hattında oluyor; Android SDK da yok (APK'yı PR'da CI derler).
/// Kotlin/XML tarafı da aynı yolla kilitlenir: manifest kaydı, seçim ekranı,
/// okunan anahtarlar ve Kotlin'in andığı kaynakların varlığı. İki taraf arasındaki SÖZLEŞME (anahtar, JSON
/// alanları, widget türü, paket ve pbxproj kaydı, dokunuş URI'si) kaynak
/// metinden kilitlenir; Dart tarafının yazdığı değerler kanal taklidiyle
/// doğrulanır.

class _Kanal {
  final Map<String, Object?> yazilan = {};
  final List<Map<String, Object?>> yenilemeler = [];
  List<Map<String, Object?>> kurulu = const [];

  void kur() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'),
            (call) async {
      switch (call.method) {
        case 'saveWidgetData':
          final a = (call.arguments as Map).cast<String, Object?>();
          yazilan[a['id'] as String] = a['data'];
          return true;
        case 'updateWidget':
          yenilemeler
              .add((call.arguments as Map? ?? {}).cast<String, Object?>());
          return true;
        case 'setAppGroupId':
          return true;
        case 'getInstalledWidgets':
          return kurulu;
      }
      return null;
    });
  }

  void kaldir() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
}

Asset _lot({
  required String id,
  required String ticker,
  required AssetType type,
  String name = '',
  String? sub,
  double qty = 10,
  AssetKind kind = AssetKind.buy,
  bool elle = false,
  String userId = 'u1',
  String currency = 'TRY',
}) =>
    Asset(
      id: id,
      userId: userId,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: currency,
      notes: '',
      subCategory: sub,
      isManualPrice: elle,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
    );

WatchlistItem _takip(String ticker, AssetType type,
        {String name = '', String? sub}) =>
    WatchlistItem(
      id: 'w-$ticker',
      userId: 'u1',
      ticker: ticker,
      name: name,
      type: type,
      subCategory: sub,
      currency: 'TRY',
      addedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  group('sembol kararı fiyat_kaynagi.dart\'ta (sözleşme madde 1)', () {
    String? s(AssetType t, String ticker, {bool elle = false}) =>
        FiyatKaynagi.widgetKotasyonSembolu(
            type: t, ticker: ticker, isManualPrice: elle);

    test('altın, döviz, BIST, fon, kripto, endeks girer', () {
      expect(s(AssetType.altin, 'ALTIN_GRAM24'), 'ALTIN_GRAM24');
      expect(s(AssetType.doviz, 'USDTRY=X'), 'USDTRY=X');
      expect(s(AssetType.hisse, 'thyao.is'), 'THYAO.IS');
      // Öneksiz eski fon kodu TEFAS'a gider — portföy fiyat turuyla aynı.
      expect(s(AssetType.fon, 'AFT'), 'TEFAS:AFT');
      expect(s(AssetType.fon, 'TEFAS:AFT'), 'TEFAS:AFT');
      expect(s(AssetType.kripto, 'KRIPTO:BTC'), 'KRIPTO:BTC');
      expect(s(AssetType.hisse, 'XU100.IS'), 'XU100.IS');
    });

    test('elle fiyatlı, mevduat, diğer ve USD kote GİRMEZ', () {
      expect(s(AssetType.fon, 'AFT', elle: true), isNull);
      expect(s(AssetType.mevduat, 'MEVDUAT:abc'), isNull);
      expect(s(AssetType.diger, 'ARSA'), isNull);
      expect(s(AssetType.eurobond, 'EUROBOND:US900123'), isNull);
      // Sayısı dolar: widget TL gösteren uygulamayla ayrışırdı.
      expect(s(AssetType.hisse, 'AAPL'), isNull);
      expect(s(AssetType.emtia, 'GC=F'), isNull);
      expect(s(AssetType.hisse, ''), isNull);
    });
  });

  group('seçim listesi = portföy + takip listesi', () {
    test('önce portföy, sonra takip; aynı sembol bir kez', () {
      final adaylar = varlikWidgetAdaylari(
        lotlar: [
          _lot(
              id: 'a1',
              ticker: 'ALTIN_GRAM24',
              type: AssetType.altin,
              name: 'Gram Altın (24 Ayar)',
              sub: 'Gram Altın (24 Ayar)'),
          // Aynı pozisyonun ikinci lot'u — listede tek satır.
          _lot(
              id: 'a2',
              ticker: 'ALTIN_GRAM24',
              type: AssetType.altin,
              name: 'Gram Altın (24 Ayar)',
              sub: 'Gram Altın (24 Ayar)'),
          _lot(
              id: 'a3',
              ticker: 'TEFAS:AFT',
              type: AssetType.fon,
              name: 'AK PORTFÖY YENİ TEKNOLOJİLER FONU'),
        ],
        takip: [
          _takip('TEFAS:AFT', AssetType.fon, name: 'AK PORTFÖY'),
          _takip('USDTRY=X', AssetType.doviz,
              name: 'Amerikan Doları', sub: 'USD'),
        ],
      );
      expect([for (final a in adaylar) a.sembol],
          ['ALTIN_GRAM24', 'TEFAS:AFT', 'USDTRY=X']);
      // Kısa ad takip satırıyla aynı kural; uzun ad ikinci satır.
      expect(adaylar[1].ad, 'AFT');
      expect(adaylar[1].alt, 'AK PORTFÖY YENİ TEKNOLOJİLER FONU');
      expect(adaylar[2].ad, 'USD');
      expect(adaylar[2].alt, 'Amerikan Doları');
      // Ad ile uzun ad aynıysa ikinci satır yok.
      expect(adaylar[0].alt, isNull);
    });

    test('kapanmış pozisyon ve satış lot\'u listeye girmez', () {
      final adaylar = varlikWidgetAdaylari(
        lotlar: [
          _lot(id: 'b1', ticker: 'THYAO.IS', type: AssetType.hisse, qty: 10),
          _lot(
              id: 's1',
              ticker: 'THYAO.IS',
              type: AssetType.hisse,
              qty: 10,
              kind: AssetKind.sell),
        ],
        takip: const [],
      );
      expect(adaylar, isEmpty,
          reason: 'Bugünkü mülkiyet `aktifLotlar` ile sorulur');
    });

    test('liste üst sınırı uygulanır', () {
      final adaylar = varlikWidgetAdaylari(
        lotlar: const [],
        takip: [
          for (var i = 0; i < 60; i++)
            _takip('K${i.toString().padLeft(2, '0')}X.IS', AssetType.hisse),
        ],
      );
      expect(adaylar.length, 40);
    });
  });

  group('öğe biçimi (uydurma sayı yok, yön yalnız renkle değil)', () {
    const altin = VarlikWidgetAdayi(
        sembol: 'ALTIN_GRAM24', ad: 'Gram Altın', type: AssetType.altin);

    test('fiyat ve işaretli yüzde biçimli yazılır', () {
      final o = varlikWidgetOgesi(altin, fiyat: 6123.45, gunlukPct: 0.42);
      expect(o.fiyat, contains('₺'));
      expect(o.fiyat, contains('6.123,45'));
      expect(o.degisim, '+%0,42');
      expect(o.yon, 1);
      final d = varlikWidgetOgesi(altin, fiyat: 6123.45, gunlukPct: -1.5);
      expect(d.degisim, '−%1,50');
      expect(d.yon, -1);
    });

    test('sıfıra yuvarlanan yüzde yön taşımaz', () {
      final o = varlikWidgetOgesi(altin, fiyat: 10, gunlukPct: 0.001);
      expect(o.degisim, '%0,00');
      expect(o.yon, 0);
    });

    test('fiyat yoksa ya da geçersizse alan YAZILMAZ', () {
      for (final f in [null, 0.0, -1.0, double.nan]) {
        final o = varlikWidgetOgesi(altin, fiyat: f, gunlukPct: 0.4);
        expect(o.toJson().containsKey('fiyat'), isFalse);
        expect(o.toJson().containsKey('degisim'), isFalse,
            reason: 'fiyatsız yüzde anlamsız');
      }
      final y = varlikWidgetOgesi(altin, fiyat: 10);
      expect(y.toJson().containsKey('degisim'), isFalse);
      expect(y.toJson().containsKey('yon'), isFalse);
    });

    test('endeks puandır: simge ve kuruş yok', () {
      const xu = VarlikWidgetAdayi(
          sembol: 'XU100.IS', ad: 'BIST 100', type: AssetType.hisse);
      final o = varlikWidgetOgesi(xu, fiyat: 10245.67);
      expect(o.fiyat, '10.246');
    });

    test('fonun günlük yüzdesi son iki NAV\'dan, yalnız aynı günse', () {
      final nav = [(1, 2.0), (2, 2.02)];
      expect(fonGunlukYuzdesi(nav, 2.02), closeTo(1.0, 1e-9));
      // Kotasyon seriden bir gün ileride: farklı günler birleştirilmez.
      expect(fonGunlukYuzdesi(nav, 2.05), isNull);
      expect(fonGunlukYuzdesi([(1, 2.0)], 2.0), isNull);
    });
  });

  group('servis — App Group yazımı', () {
    late _Kanal kanal;
    final svc = VarlikWidgetService.instance;
    var kotasyonCagrisi = 0;

    setUp(() {
      HomeWidgetService.instance.kiyasBelleginiSifirla();
      kanal = _Kanal()..kur();
      svc.sifirla();
      kotasyonCagrisi = 0;
      VarlikWidgetService.platformKontrolu = () => true;
      svc.kuruluMu = () async => true;
      svc.saat = () => DateTime(2026, 10, 24, 14, 5);
      svc.kotasyonYukleyici = (semboller) async {
        kotasyonCagrisi++;
        return {
          'ALTIN_GRAM24': const YahooQuote(
              symbol: 'ALTIN_GRAM24',
              regularMarketPrice: 6123.45,
              regularMarketChangePercent: 0.42),
          'TEFAS:AFT':
              const YahooQuote(symbol: 'TEFAS:AFT', regularMarketPrice: 2.02),
        };
      };
      svc.navYukleyici = (_) async => [(1, 2.0), (2, 2.02)];
    });

    tearDown(() {
      kanal.kaldir();
      VarlikWidgetService.platformKontrolu = () => false;
    });

    Map<String, Object?> paket() =>
        jsonDecode(kanal.yazilan[HomeWidgetService.kVarliklar] as String)
            as Map<String, Object?>;

    test('YENİ anahtara sürümlü JSON yazar ve yalnız kendi türünü yeniler',
        () async {
      await svc.guncelle(
        lotlar: [
          _lot(
              id: 'a1',
              ticker: 'ALTIN_GRAM24',
              type: AssetType.altin,
              name: 'Gram Altın (24 Ayar)',
              sub: 'Gram Altın (24 Ayar)',
              qty: 37),
        ],
        takip: [_takip('TEFAS:AFT', AssetType.fon, name: 'AK PORTFÖY')],
      );
      final p = paket();
      expect(p['v'], 1);
      expect(p['saat'], '14:05');
      final ogeler = (p['ogeler'] as List).cast<Map<String, Object?>>();
      expect(ogeler.map((o) => o['id']), ['ALTIN_GRAM24', 'TEFAS:AFT']);
      expect(ogeler[0]['degisim'], '+%0,42');
      expect(ogeler[0]['yon'], 1);
      // TEFAS kotasyonu yüzde taşımaz: son iki NAV'dan.
      expect(ogeler[1]['degisim'], '+%1,00');

      // Yalnız yeni anahtar: portföy widget'ının anahtarlarına dokunulmaz.
      expect(kanal.yazilan.keys, [HomeWidgetService.kVarliklar]);
      expect(kanal.yenilemeler.single['ios'],
          HomeWidgetService.iOSVarlikWidgetName);
      // Aynı çağrı Android sağlayıcısını da yeniler (iOS'ta yok sayılır).
      expect(kanal.yenilemeler.single['android'],
          HomeWidgetService.androidVarlikWidgetName);
    });

    test('miktar, tutar, lot ve kullanıcı kimliği YAZILMAZ', () async {
      await svc.guncelle(
        lotlar: [
          _lot(
              id: 'lot-uuid-1',
              ticker: 'ALTIN_GRAM24',
              type: AssetType.altin,
              name: 'Gram Altın',
              qty: 37),
        ],
        takip: const [],
      );
      final ham = kanal.yazilan[HomeWidgetService.kVarliklar] as String;
      expect(ham, isNot(contains('lot-uuid-1')));
      expect(ham, isNot(contains('u1')));
      // `zaman` bir epoch sayısıdır; içinde rastlantıyla "37" geçebilir.
      // Miktar araması onun dışında kalan her şeyde yapılır.
      final zamansiz = Map.of(paket())..remove('zaman');
      expect(jsonEncode(zamansiz), isNot(contains('37')),
          reason: 'Miktar kilitsiz yüzeyin deposuna girmez');
      for (final o
          in (paket()['ogeler'] as List).cast<Map<String, Object?>>()) {
        expect(
            o.keys.toSet().difference({
              'id', 'ad', 'alt', 'fiyat', 'degisim', 'yon', //
              'kisa', 'kapanis', 'seansSonu',
              // 2026-10-26: sunucu tazelemesi — kapsam bayrağı ve ondalık
              // kuralı; kişisel değil.
              'sunucu', 'hane',
            }),
            isEmpty);
      }
    });

    test('widget kurulu değilken ağa çıkılmaz, takip listesi yüklenmez',
        () async {
      svc.kuruluMu = () async => false;
      var takipYuklendi = false;
      await svc.guncelle(
        lotlar: [
          _lot(id: 'a1', ticker: 'ALTIN_GRAM24', type: AssetType.altin),
        ],
        takipYukle: () async {
          takipYuklendi = true;
          return const [];
        },
      );
      expect(kotasyonCagrisi, 0);
      expect(takipYuklendi, isFalse);
      // Liste yine yazılır: düzenleme ekranı boş açılmasın.
      expect((paket()['ogeler'] as List).length, 1);
    });

    test('kuruluyken takip listesi yüklenmemişse istenir', () async {
      await svc.guncelle(
        lotlar: const [],
        takipYukle: () async =>
            [_takip('USDTRY=X', AssetType.doviz, sub: 'USD')],
      );
      final ogeler = (paket()['ogeler'] as List).cast<Map<String, Object?>>();
      expect(ogeler.single['id'], 'USDTRY=X');
      // Kotasyonda yok, oturum belleğinde yok → fiyat uydurulmaz.
      expect(ogeler.single.containsKey('fiyat'), isFalse);
    });

    test('aynı liste dakikada bir kereden sık yazılmaz', () async {
      final lot = _lot(id: 'a1', ticker: 'ALTIN_GRAM24', type: AssetType.altin);
      await svc.guncelle(lotlar: [lot], takip: const []);
      await svc.guncelle(lotlar: [lot], takip: const []);
      expect(kotasyonCagrisi, 1);
      // Liste değişince beklemeden yazılır.
      await svc.guncelle(
          lotlar: [lot],
          takip: [_takip('USDTRY=X', AssetType.doviz, sub: 'USD')]);
      expect(kotasyonCagrisi, 2);
    });

    test('desteklenmeyen platformda (masaüstü/web) hiçbir şey yazılmaz',
        () async {
      VarlikWidgetService.platformKontrolu = () => false;
      await svc.guncelle(
        lotlar: [
          _lot(id: 'a1', ticker: 'ALTIN_GRAM24', type: AssetType.altin),
        ],
        takip: const [],
      );
      expect(kanal.yazilan, isEmpty);
      expect(kotasyonCagrisi, 0);
    });

    test('Android\'de kurulu widget sınıf adından tanınır', () async {
      // `ComponentName.shortClassName`: aynı paketteki sınıf "." ile başlar.
      kanal.kurulu = [
        {'widgetId': 7, 'androidClassName': '.SandikWidgetProvider'},
      ];
      expect(await HomeWidgetService.instance.varlikWidgetiKuruluMu(), isFalse,
          reason: 'portföy widget\'ı tek varlık widget\'ı sayılmaz');
      kanal.kurulu = [
        {'widgetId': 7, 'androidClassName': '.SandikWidgetProvider'},
        {'widgetId': 8, 'androidClassName': '.SandikVarlikWidgetProvider'},
      ];
      expect(await HomeWidgetService.instance.varlikWidgetiKuruluMu(), isTrue);
      kanal.kurulu = [
        {
          'widgetId': 9,
          'androidClassName': 'com.sandik.app.SandikVarlikWidgetProvider'
        },
      ];
      expect(await HomeWidgetService.instance.varlikWidgetiKuruluMu(), isTrue);
      kanal.kurulu = [
        {
          'kind': HomeWidgetService.iOSVarlikWidgetName,
          'family': 'systemSmall'
        },
      ];
      expect(await HomeWidgetService.instance.varlikWidgetiKuruluMu(), isTrue);
    });

    test('oturum kapanınca seçim listesi boşaltılır', () async {
      await svc.guncelle(
        lotlar: [
          _lot(id: 'a1', ticker: 'ALTIN_GRAM24', type: AssetType.altin),
        ],
        takip: const [],
      );
      await HomeWidgetService.instance.clear();
      expect(kanal.yazilan[HomeWidgetService.kVarliklar], '');
    });

    test('portföy özeti yazımı yeni anahtara dokunmaz', () async {
      await HomeWidgetService.instance.update(
        PortfolioState(
          assets: [
            _lot(id: 'a1', ticker: 'THYAO.IS', type: AssetType.hisse),
          ],
          usdTry: 42.0,
          eurTry: 46.0,
          gbpTry: 54.0,
        ),
        hideBalance: false,
      );
      expect(kanal.yazilan.containsKey(HomeWidgetService.kVarliklar), isFalse);
      expect(kanal.yazilan['sandik_total'], isNotNull,
          reason: 'eski anahtarlar eskisi gibi yazılıyor');
    });
  });

  group('kilit ekranı: kapanış etiketi, kısa ad, tazelik (Ar-Ge 2026-10-25 §2)',
      () {
    // 24 Ekim 2026 cumartesi; 26 Ekim pazartesi (seans açık).
    final cumartesi = DateTime(2026, 10, 24, 14, 5);
    final pazartesi = DateTime(2026, 10, 26, 14, 5);

    VarlikWidgetAdayi aday(String ticker, AssetType type,
            {String name = '', String? sub}) =>
        varlikWidgetAdaylari(
          lotlar: const [],
          takip: [_takip(ticker, type, name: name, sub: sub)],
        ).single;

    test('kripto 7/24: kapanış etiketi HİÇBİR ZAMAN yazılmaz', () {
      final btc = aday('KRIPTO:BTC', AssetType.kripto, name: 'Bitcoin');
      expect(btc.borsaTakviminde, isFalse);
      for (final an in [cumartesi, pazartesi, DateTime(2026, 10, 26, 23)]) {
        final j = varlikWidgetOgesi(btc, fiyat: 3500000, simdi: an).toJson();
        expect(j.containsKey('kapanis'), isFalse, reason: '$an');
        expect(j.containsKey('seansSonu'), isFalse, reason: '$an');
      }
    });

    test('altın ve döviz hafta sonu da işler: kapanış yok', () {
      for (final a in [
        aday('ALTIN_GRAM24', AssetType.altin, name: 'Gram Altın'),
        aday('USDTRY=X', AssetType.doviz, sub: 'USD'),
      ]) {
        final j = varlikWidgetOgesi(a, fiyat: 42, simdi: cumartesi).toJson();
        expect(j.containsKey('kapanis'), isFalse, reason: a.sembol);
      }
    });

    test('BIST ve fon: seans kapalıyken kapanış, açıkken seans sonu', () {
      final thy = aday('THYAO.IS', AssetType.hisse);
      final fon = aday('TEFAS:AFT', AssetType.fon);
      expect(
          varlikWidgetOgesi(thy, fiyat: 300, simdi: cumartesi).kapanis, isTrue);
      expect(
          varlikWidgetOgesi(fon, fiyat: 2, simdi: cumartesi).kapanis, isTrue);
      // Pazartesi 20:00: seans bitti.
      expect(
          varlikWidgetOgesi(thy, fiyat: 300, simdi: DateTime(2026, 10, 26, 20))
              .kapanis,
          isTrue);
      final acik = varlikWidgetOgesi(thy, fiyat: 300, simdi: pazartesi);
      expect(acik.kapanis, isNull);
      expect(acik.seansSonu, DateTime(2026, 10, 26, 18).millisecondsSinceEpoch,
          reason: 'BugunService.seansAcikMi ile aynı eşik');
      // Fiyat bilinmiyorsa etiket de yok.
      final fiyatsiz = varlikWidgetOgesi(thy, simdi: cumartesi).toJson();
      expect(fiyatsiz.containsKey('kapanis'), isFalse);
      // An verilmezse (eski çağrı) etiket yok.
      expect(varlikWidgetOgesi(thy, fiyat: 300).toJson().containsKey('kapanis'),
          isFalse);
    });

    test('tek satır için kısa ad: "Gram" → "Gr"; aynıysa yazılmaz', () {
      expect(kilitEkraniKisaAd('Gram altın'), 'Gr altın');
      expect(kilitEkraniKisaAd('Gram Altın (24 Ayar)'), 'Gr Altın (24 Ayar)');
      expect(kilitEkraniKisaAd('USD'), 'USD');
      final altin = aday('ALTIN_GRAM24', AssetType.altin, name: 'Gram altın');
      expect(varlikWidgetOgesi(altin, fiyat: 4215).kisa, 'Gr altın');
      final usd = aday('USDTRY=X', AssetType.doviz, sub: 'USD');
      expect(varlikWidgetOgesi(usd, fiyat: 42).toJson().containsKey('kisa'),
          isFalse);
    });

    test('paket yazım anını taşır (1 günden eski fiyatta tarih görünür)', () {
      final p = jsonDecode(
              varlikWidgetPaketi(const [], saat: '14:05', zaman: cumartesi))
          as Map<String, Object?>;
      expect(p['v'], 1,
          reason: 'eski okuyucu: sürüm aynı, alanlar isteğe bağlı');
      expect(p['zaman'], cumartesi.millisecondsSinceEpoch);
      expect(p['tarih'], '24 Eki 14:05');
      final eski = jsonDecode(varlikWidgetPaketi(const [], saat: '14:05'))
          as Map<String, Object?>;
      expect(eski.containsKey('zaman'), isFalse);
    });
  });

  test('servis iOS ve Android\'de çalışır (Android widget\'ı 2026-10-25)', () {
    final kaynak = ekranKaynagiSync('lib/services/varlik_widget_service.dart');
    expect(kaynak, contains('Platform.isIOS || Platform.isAndroid'));
  });

  group('Swift sözleşmesi (kaynak kilidi — derleme burada yok)', () {
    final swift = ekranKaynagiSync('ios/SandikWidget/SandikVarlikWidget.swift');
    final bundle =
        ekranKaynagiSync('ios/SandikWidget/SandikWidgetBundle.swift');
    final pbx = ekranKaynagiSync('ios/Runner.xcodeproj/project.pbxproj');

    test('anahtar, App Group ve tür Dart ile birebir', () {
      expect(swift, contains('"${HomeWidgetService.kVarliklar}"'));
      expect(swift, contains('"group.com.sandik.app"'));
      expect(swift,
          contains('let kind = "${HomeWidgetService.iOSVarlikWidgetName}"'));
      expect(swift, contains('"sandik_is_light_theme"'));
    });

    test('JSON alanları Dart toJson ile aynı adlar', () {
      for (final alan in ['id', 'ad', 'alt', 'fiyat', 'degisim', 'yon']) {
        expect(swift, contains('let $alan: '),
            reason: '`$alan` Swift Codable modelinde yok');
      }
      for (final alan in ['v', 'saat', 'ogeler']) {
        expect(swift, contains('let $alan: '));
      }
      // Kilit ekranı alanları isteğe bağlı (`var … = nil`): eski paket de
      // çözülür.
      for (final alan in ['kisa', 'kapanis', 'seansSonu', 'zaman', 'tarih']) {
        expect(swift, contains('var $alan: '),
            reason: '`$alan` Swift Codable modelinde yok');
      }
    });

    test('desteklenen aileler: ana ekran küçük + kilit ekranı iki boyut', () {
      final m = RegExp(r'\.supportedFamilies\(\[([^\]]*)\]\)')
          .allMatches(swift)
          .toList();
      expect(m, hasLength(1));
      final aileler = m.single.group(1)!;
      for (final aile in [
        '.systemSmall',
        '.accessoryRectangular',
        '.accessoryInline',
      ]) {
        expect(aileler, contains(aile));
      }
      // Kilit ekranında zemin sistemin; tema rengi tek renkte lekeye döner.
      expect(swift, contains('AccessoryWidgetBackground()'));
      expect(swift, contains('Color.clear'));
    });

    test('kapanış kararı Swift\'te verilmez (tek kaynak Dart)', () {
      // Seans/tatil takvimi Dart'ta (`BugunService`, `BistTakvimi`); Swift
      // yalnız yazılan `kapanis` / `seansSonu` alanını okur. Swift'te
      // takvime bakmak kriptoya ya da tatile yanlış "Kapanış" yazdırırdı.
      expect(swift, isNot(contains('BistSeans')));
      expect(swift, contains('oge.kapanis == true'));
    });

    test('varlık App Intents ile seçilir; liste yalnız uygulamanın paketi', () {
      expect(swift, contains('AppIntentConfiguration('));
      expect(swift, contains('WidgetConfigurationIntent'));
      expect(swift, contains('struct SandikVarlikQuery: EntityQuery'));
      // Katalog araması yok: `EntityStringQuery` arama kutusu açardı.
      expect(swift, isNot(contains('EntityStringQuery')));
    });

    test('yön ok + sayıyla, yalnız renkle değil', () {
      expect(swift, contains('"▲"'));
      expect(swift, contains('"▼"'));
      expect(swift, contains('accessibilityLabel'));
      // Üç boyut da aynı erişilebilirlik cümlesini okur.
      expect('accessibilityLabel(erisimMetni(oge))'.allMatches(swift).length,
          greaterThanOrEqualTo(3));
    });

    test('paket kaydı ve pbxproj (Sources fazı) yerinde', () {
      expect(bundle, contains('SandikVarlikWidget()'));
      final ref = RegExp(
              r'(\w+) /\* SandikVarlikWidget\.swift \*/ = \{isa = PBXFileReference;')
          .firstMatch(pbx);
      expect(ref, isNotNull, reason: 'dosya referansı yok');
      final build = RegExp(
              r'(\w+) /\* SandikVarlikWidget\.swift in Sources \*/ = \{isa = PBXBuildFile; fileRef = '
              '${ref!.group(1)}')
          .firstMatch(pbx);
      expect(build, isNotNull, reason: 'derleme dosyası yok');
      // Uzantı hedefinin Sources fazı (5A0D1K…22) bu dosyayı listeliyor.
      final faz = RegExp(r'5A0D1K0000000000000022 /\* Sources \*/ = \{[^}]*\}',
              dotAll: true)
          .firstMatch(pbx)!
          .group(0)!;
      expect(
          faz,
          contains(
              '${build!.group(1)} /* SandikVarlikWidget.swift in Sources */'));
      // Grup üyeliği.
      final grup = RegExp(
              r'5A0D1K0000000000000020 /\* SandikWidget \*/ = \{[^}]*\}',
              dotAll: true)
          .firstMatch(pbx)!
          .group(0)!;
      expect(grup, contains('${ref.group(1)} /* SandikVarlikWidget.swift */'));
    });

    test(
        'uzantı hedefi iOS 17+: AppIntentConfiguration koşulsuz kullanılabilir',
        () {
      final hedefler = RegExp(
              r'INFOPLIST_FILE = SandikWidget/Info\.plist;[\s\S]*?IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
          .allMatches(pbx)
          .map((m) => double.parse(m.group(1)!))
          .toList();
      expect(hedefler, hasLength(3));
      expect(hedefler.every((v) => v >= 17.0), isTrue,
          reason: 'Hedef 17 altına inerse `@available` gerekir');
    });

    test('dokunuş URI\'si Dart eşlemesiyle uyuşuyor → Portföy sekmesi', () {
      final m = RegExp(r'varlikWidgetClickURL = URL\(string: "([^"]+)"\)')
          .firstMatch(swift);
      expect(m, isNotNull);
      final uri = m!.group(1)!;
      expect(uri, contains('homeWidget'),
          reason: 'Parametresiz URL iOS eklentisinin süzgecinde düşer');
      expect(DeepLinkRouter.hedefSekmeMetin(uri),
          MainNavigationScreen.portfoySekmesi);
      expect(DeepLinkRouter.gunlukGorunumIster(Uri.parse(uri)), isFalse,
          reason: 'Tek varlık portföy toplamını anlatmaz');
    });
  });

  group('Android sözleşmesi (kaynak kilidi — APK burada derlenmiyor)', () {
    const kotlinDizini = 'android/app/src/main/kotlin/com/sandik/app';
    const resDizini = 'android/app/src/main/res';
    final provider =
        ekranKaynagiSync('$kotlinDizini/SandikVarlikWidgetProvider.kt');
    final secim =
        ekranKaynagiSync('$kotlinDizini/SandikVarlikSecimActivity.kt');
    final manifest =
        ekranKaynagiSync('android/app/src/main/AndroidManifest.xml');
    final info =
        ekranKaynagiSync('$resDizini/xml/sandik_varlik_widget_info.xml');
    final swift = ekranKaynagiSync('ios/SandikWidget/SandikVarlikWidget.swift');

    /// `<receiver …>…</receiver>` / `<activity …>…</activity>` bloğu.
    String? blok(String etiket, String ad) => RegExp(
          '<$etiket\\s+android:name="${RegExp.escape(ad)}"[\\s\\S]*?</$etiket>',
        ).firstMatch(manifest)?.group(0);

    test('receiver manifest\'te kayıtlı: sınıf adı Dart ile birebir', () {
      final r =
          blok('receiver', '.${HomeWidgetService.androidVarlikWidgetName}');
      expect(r, isNotNull, reason: 'receiver yok — widget listede görünmez');
      expect(r, contains('android:exported="true"'),
          reason: 'launcher başka uygulama; portföy widget\'ıyla aynı');
      expect(r, contains('android.appwidget.action.APPWIDGET_UPDATE'));
      expect(r, contains('android:resource="@xml/sandik_varlik_widget_info"'));
      expect(
          provider,
          contains('class ${HomeWidgetService.androidVarlikWidgetName} '
              ': AppWidgetProvider()'));
      // Portföy widget'ının kaydı yerinde (dokunulmadı).
      expect(blok('receiver', '.SandikWidgetProvider'),
          contains('@xml/sandik_widget_info'));
    });

    test('seçim ekranı tanımlı ve widget info onu gösteriyor', () {
      final a = blok('activity', '.SandikVarlikSecimActivity');
      expect(a, isNotNull, reason: 'configure Activity manifest\'te yok');
      expect(a, contains('android.appwidget.action.APPWIDGET_CONFIGURE'));
      expect(a, contains('android:exported="true"'));
      expect(a, isNot(contains('android:taskAffinity')),
          reason: 'ayrı görevde sonuç launcher\'a İPTAL döner');
      expect(
          info,
          contains(
              'android:configure="com.sandik.app.SandikVarlikSecimActivity"'));
      expect(secim, contains('class SandikVarlikSecimActivity : Activity()'));
      expect(info, contains('reconfigurable'));
      expect(info, contains('android:updatePeriodMillis="0"'),
          reason: 'sistem zamanlayıcısı pil yer; veriyi uygulama yazar');
      // Seçim ekranı gelen kimliğin bu sağlayıcıya ait olduğunu doğrular
      // (exported Activity'ye başka uygulama da kimlik gönderebilir).
      expect(secim, contains('getAppWidgetInfo(widgetId)?.provider'));
      expect(secim, contains('setResult(RESULT_CANCELED'));
      expect(secim, contains('setResult(RESULT_OK'));
    });

    test('Android\'in okuduğu anahtarlar Dart\'ta yazılanlarla aynı', () {
      expect(provider,
          contains('KEY_VARLIKLAR = "${HomeWidgetService.kVarliklar}"'));
      expect(provider, contains('KEY_ACIK_TEMA = "sandik_is_light_theme"'));
      // Tema bayrağını Dart bu adla yazıyor.
      expect(ekranKaynagiSync('lib/services/home_widget_service.dart'),
          contains("'sandik_is_light_theme'"));
      // Paket alanları: Dart `toJson` / `varlikWidgetPaketi` adları.
      final dart = ekranKaynagiSync('lib/services/varlik_widget_service.dart');
      for (final alan in [
        'v', 'saat', 'zaman', 'tarih', 'ogeler', //
        'id', 'ad', 'alt', 'fiyat', 'degisim', 'yon', 'kapanis',
      ]) {
        expect(provider, contains('"$alan"'),
            reason: '`$alan` Kotlin okuyucusunda yok');
        expect(dart, contains("'$alan'"),
            reason: '`$alan` Dart paketinde yazılmıyor');
      }
      // Sürüm iOS ile aynı: tanınmayan sürüm okunmaz.
      expect(provider, contains('const val SURUM = 1'));
      expect(
          (jsonDecode(varlikWidgetPaketi(const [], saat: ''))
              as Map<String, Object?>)['v'],
          1);
      // Seçim Dart'ın deposuna yazılmaz (oturum kapanışında silinmesin).
      expect(provider, contains('SECIM_DOSYASI = "SandikVarlikWidgetSecim"'));
      expect(secim, isNot(contains('HomeWidgetPreferences')));
    });

    test('dokunuş URI\'si iOS ile birebir → Portföy sekmesi, aynı yüzey', () {
      final m =
          RegExp(r'VARLIK_WIDGET_CLICK_URI = "([^"]+)"').firstMatch(provider);
      expect(m, isNotNull);
      final uri = m!.group(1)!;
      final iosUri = RegExp(r'varlikWidgetClickURL = URL\(string: "([^"]+)"\)')
          .firstMatch(swift)!
          .group(1)!;
      expect(uri, iosUri, reason: 'iki platform aynı URI\'yi taşımalı');
      expect(DeepLinkRouter.hedefSekmeMetin(uri),
          MainNavigationScreen.portfoySekmesi);
      // Atıf: `widget_tapped.surface` iOS ile aynı yoldan `varlik_widget`.
      expect(DeepLinkRouter.widgetYuzeyi(Uri.parse(uri)), 'varlik_widget');
      // `HomeWidgetLaunchIntent` URI'yi Dart'a (`widgetClicked` /
      // `initiallyLaunchedFromHomeWidget`) taşır; düz launch intent atfı
      // kaybederdi.
      expect(provider, contains('HomeWidgetLaunchIntent.getActivity('));
      expect(provider, contains('Uri.parse(VARLIK_WIDGET_CLICK_URI)'));
    });

    test('yön ok + işaretli yüzdeyle; tek erişilebilirlik cümlesi', () {
      expect(provider, contains('"▲"'));
      expect(provider, contains('"▼"'));
      expect(provider, contains('setContentDescription('));
      // Kapanış kararı Dart'ta: Kotlin takvime bakmaz, alanı okur.
      expect(provider, contains('oge.kapanis == true'));
      expect(provider, isNot(contains('Calendar')));
      // Fiyat bilinmiyorsa "—"; sayı uydurulmaz ya da yeniden biçimlenmez.
      expect(provider, contains('oge.fiyat ?: "—"'));
      expect(provider, isNot(contains('String.format')));
    });

    test('Kotlin\'in andığı kaynaklar var (derleme kırılmasın)', () {
      String birlestir(String dizin) => Directory(dizin)
          .listSync()
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      final layoutlar = birlestir('$resDizini/layout');
      final degerler = birlestir('$resDizini/values');
      bool drawableVar(String ad) => Directory(resDizini)
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('drawable'))
          .any((d) => d
              .listSync()
              .any((f) => f.uri.pathSegments.last.startsWith('$ad.')));

      for (final m in RegExp(r'R\.(id|string|layout|color|drawable)\.(\w+)')
          .allMatches('$provider\n$secim')) {
        final tur = m.group(1)!;
        final ad = m.group(2)!;
        final tanimli = switch (tur) {
          'id' => layoutlar.contains('@+id/$ad"'),
          'string' => degerler.contains('<string name="$ad">'),
          'color' => degerler.contains('<color name="$ad">'),
          'layout' => File('$resDizini/layout/$ad.xml').existsSync(),
          _ => drawableVar(ad),
        };
        expect(tanimli, isTrue, reason: 'R.$tur.$ad tanımlı değil');
      }
      // Manifest, widget info ve yeni layout'ların andığı kaynaklar.
      final xml = [
        manifest,
        info,
        File('$resDizini/layout/sandik_varlik_widget.xml').readAsStringSync(),
        File('$resDizini/layout/sandik_varlik_secim.xml').readAsStringSync(),
        File('$resDizini/layout/sandik_varlik_secim_satir.xml')
            .readAsStringSync(),
      ].join('\n');
      for (final m
          in RegExp(r'@(string|style|xml|layout|color|drawable|font)/(\w+)')
              .allMatches(xml)) {
        final tur = m.group(1)!;
        final ad = m.group(2)!;
        final tanimli = switch (tur) {
          'string' => degerler.contains('<string name="$ad">'),
          'style' => degerler.contains('<style name="$ad"'),
          'color' => degerler.contains('<color name="$ad">'),
          'xml' => File('$resDizini/xml/$ad.xml').existsSync(),
          'font' => File('$resDizini/font/$ad.ttf').existsSync(),
          'drawable' => drawableVar(ad),
          _ => File('$resDizini/layout/$ad.xml').existsSync(),
        };
        expect(tanimli, isTrue, reason: '@$tur/$ad tanımlı değil');
      }
    });

    test('strings.xml: kaçışsız kesme işareti yok (aapt derlemeyi kırar)', () {
      final strings = File('$resDizini/values/strings.xml').readAsStringSync();
      for (final m in RegExp(r'<string name="([^"]+)">([^<]*)</string>')
          .allMatches(strings)) {
        expect(RegExp(r"(?<!\\)'").hasMatch(m.group(2)!), isFalse,
            reason: '${m.group(1)}: kesme işareti \\\' ile yazılmalı');
        expect(m.group(1), matches(RegExp(r'^[a-z0-9_]+$')),
            reason: 'kaynak adı yalnız ASCII');
      }
    });

    test('seçim ekranı tema stili iki modda da tanımlı', () {
      for (final d in ['values', 'values-night']) {
        expect(File('$resDizini/$d/styles.xml').readAsStringSync(),
            contains('<style name="SandikVarlikSecimTheme"'),
            reason: '$d/styles.xml');
      }
    });
  });
}
