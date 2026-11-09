import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/sunucu_secimi.dart';
import 'package:portfoy_takip/services/varlik_widget_service.dart';

import 'helpers/kaynak.dart';

/// Tek varlık widget'ının uygulama açılmadan tazelenmesi (yasin onayı
/// 2026-10-26): sunucu kapsamı kararı, widget sözleşmesine yazılan sunucu
/// bilgisi ve iki native okuyucunun / edge function'ın sözleşmesi.
///
/// Swift ve Kotlin burada derlenmiyor (CI derler); sözleşme kaynak metinden
/// kilitlenir, Dart'ın yazdığı değerler kanal taklidiyle doğrulanır.

class _Kanal {
  final Map<String, Object?> yazilan = {};

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
        case 'setAppGroupId':
          return true;
        case 'getInstalledWidgets':
          return const <Map<String, Object?>>[];
      }
      return null;
    });
  }

  void kaldir() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
}

Asset _lot(String ticker, AssetType type) => Asset(
      id: 'lot-$ticker',
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: 3,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
    );

const _sunucu = SunucuYapilandirmasi(
    url: 'https://ornek-proje.supabase.co', anonKey: 'ornek-anon-anahtari');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('tr_TR'));

  group('sunucu kapsamı kararı fiyat_kaynagi.dart\'ta', () {
    test('altın ayarları, TL dövizler, kripto ve fon kapsamda', () {
      for (final s in [
        'ALTIN_GRAM',
        'ALTIN_GRAM24',
        'ALTIN_CEYREK',
        'USDTRY=X',
        'EURTRY=X',
        'GBPTRY=X',
        'KRIPTO:BTC',
        'KRIPTO:1INCH',
        'TEFAS:AFT',
      ]) {
        expect(FiyatKaynagi.widgetSunucuKapsamindaMi(s), isTrue, reason: s);
      }
    });

    test('BIST, endeks, emtia ve bozuk sembol kapsam DIŞI', () {
      for (final s in [
        'THYAO.IS',
        'TEFAS:',
        'TEFAS:AFTX',
        'tefas:aft',
        'XU100.IS',
        'GC=F',
        'GUMUS_GRAM',
        'ALTIN_UYDURMA',
        'KRIPTO:',
        'kripto:btc',
        '',
      ]) {
        expect(FiyatKaynagi.widgetSunucuKapsamindaMi(s), isFalse, reason: s);
      }
    });

    test('öğe: kapsamda `sunucu` + `hane`, dışında hiçbiri yazılmaz', () {
      final altin = varlikWidgetOgesi(
          const VarlikWidgetAdayi(
              sembol: 'ALTIN_GRAM24', ad: 'Gram altın', type: AssetType.altin),
          fiyat: 6123.45,
          gunlukPct: 0.4);
      expect(altin.toJson()['sunucu'], isTrue);
      // `hane` RC `goz_alici`'ya bağlı (kapalıyken eski kural → alan yok);
      // varsa türün azami ondalığıdır.
      final hane = altin.toJson()['hane'];
      expect(hane == null || hane == AssetType.altin.fiyatAzamiOndalik, isTrue);

      final hisse = varlikWidgetOgesi(
          const VarlikWidgetAdayi(
              sembol: 'THYAO.IS',
              ad: 'THYAO',
              type: AssetType.hisse,
              borsaTakviminde: true),
          fiyat: 300);
      expect(hisse.toJson().containsKey('sunucu'), isFalse);
      expect(hisse.toJson().containsKey('hane'), isFalse);
    });
  });

  group('servis: sunucu bilgisi widget sözleşmesine', () {
    late _Kanal kanal;
    final svc = VarlikWidgetService.instance;

    setUp(() {
      HomeWidgetService.instance.kiyasBelleginiSifirla();
      kanal = _Kanal()..kur();
      svc.sifirla();
      VarlikWidgetService.platformKontrolu = () => true;
      svc.kuruluMu = () async => true;
      svc.saat = () => DateTime(2026, 10, 26, 14, 5);
      svc.sunucu = () => _sunucu;
      svc.kotasyonYukleyici = (semboller) async => {
            for (final s in semboller)
              s: YahooQuote(symbol: s, regularMarketPrice: 100),
          };
      svc.navYukleyici = (_) async => const [];
    });

    tearDown(() {
      kanal.kaldir();
      VarlikWidgetService.platformKontrolu = () => false;
      svc.sunucu = () => SunucuSecimi.instance.aktifOrNull;
    });

    test('kapsamda varlık varsa AKTİF sunucunun URL + anon anahtarı yazılır',
        () async {
      await svc.guncelle(
          lotlar: [_lot('ALTIN_GRAM24', AssetType.altin)], takip: const []);
      expect(kanal.yazilan[HomeWidgetService.kWidgetApiUrl], _sunucu.url);
      expect(
          kanal.yazilan[HomeWidgetService.kWidgetApiAnahtar], _sunucu.anonKey);
      final paket = jsonDecode(
          kanal.yazilan[HomeWidgetService.kVarliklar] as String) as Map;
      expect((paket['ogeler'] as List).single['sunucu'], isTrue);
      // Oturum jetonu ya da kullanıcı kimliği hiçbir anahtara yazılmaz.
      for (final d in kanal.yazilan.values) {
        expect('$d', isNot(contains('u1')));
        expect('$d', isNot(contains('lot-')));
      }
      // Yeni anahtarlar eski sözleşmeyi değiştirmez.
      expect(kanal.yazilan.containsKey('sandik_total'), isFalse);
    });

    test('yalnız kapsam dışı varlık varsa sunucu bilgisi yazılmaz', () async {
      await svc.guncelle(
          lotlar: [_lot('THYAO.IS', AssetType.hisse)], takip: const []);
      expect(kanal.yazilan.containsKey(HomeWidgetService.kWidgetApiUrl),
          isFalse);
      expect(kanal.yazilan.containsKey(HomeWidgetService.kVarliklar), isTrue);
    });

    test('sunucu bilinmiyorsa (yapılandırma yok) yazılmaz, liste yine yazılır',
        () async {
      svc.sunucu = () => null;
      await svc.guncelle(
          lotlar: [_lot('USDTRY=X', AssetType.doviz)], takip: const []);
      expect(kanal.yazilan.containsKey(HomeWidgetService.kWidgetApiUrl),
          isFalse);
      expect(kanal.yazilan.containsKey(HomeWidgetService.kVarliklar), isTrue);
    });

    test('oturum kapanınca widget\'ın çektiği fiyatlar da boşaltılır',
        () async {
      await HomeWidgetService.instance.clear();
      expect(kanal.yazilan[HomeWidgetService.kVarlikCanli], '');
      expect(kanal.yazilan[HomeWidgetService.kVarliklar], '');
    });
  });

  group('sunucu ve native sözleşme (kaynak kilidi)', () {
    final ts = ekranKaynagiSync('supabase/functions/_shared/widget_fiyat.ts');
    final fn = ekranKaynagiSync('supabase/functions/widget-fiyat/index.ts');
    final live = ekranKaynagiSync('supabase/functions/_shared/live_prices.ts');
    final swift = ekranKaynagiSync('ios/SandikWidget/SandikVarlikWidget.swift');
    final kt = ekranKaynagiSync(
        'android/app/src/main/kotlin/com/sandik/app/SandikVarlikWidgetProvider.kt');
    final ritimKt = ekranKaynagiSync(
        'android/app/src/main/kotlin/com/sandik/app/WidgetRitmi.kt');

    test('sunucunun yurt içi kümesi Dart\'ınkiyle birebir', () {
      // Altın anahtarları `altin_anahtar_paritesi_test`'te birebir; burada
      // döviz kümesi ve fonksiyonun aynı kümeyi kullandığı kilitlenir.
      final fx = RegExp(r"const FX_SYMBOLS = new Set\(\[([^\]]*)\]\)")
          .firstMatch(live)!
          .group(1)!;
      final tsFx = RegExp(r"'([A-Z=]+)'")
          .allMatches(fx)
          .map((m) => m.group(1)!)
          .toSet();
      final dartFx = PriceService.yurtIciSembolleri
          .where((s) => !s.startsWith('ALTIN_'))
          .toSet();
      expect(dartFx, tsFx);
      expect(ts, contains('isGoldSymbol(sembol) || isFxSymbol(sembol)'));
      expect(ts, contains('kriptoKodu(sembol)'));
      // Fon kimliği iki tarafta aynı biçim: `TEFAS:` + 3 harf/rakam.
      expect(ts, contains(r'/^TEFAS:[A-Z0-9]{3}$/'));
    });

    test('fonksiyon: oturum sormaz, yazmaz, hata metni dönmez, kısa önbellek',
        () {
      expect(fn, isNot(contains('auth.getUser')));
      expect(fn, contains("'Cache-Control': `public, max-age=\${WIDGET_ONBELLEK_SN}`"));
      expect(ts, contains('WIDGET_ONBELLEK_SN = 60'));
      expect(ts, contains('WIDGET_AZAMI_SEMBOL = 5'));
      expect(RegExp(r'json\([^)]*\.message').hasMatch(fn), isFalse);
      expect(fn, contains('SUPABASE_SERVICE_ROLE_KEY'));
      expect(fn, isNot(contains('.rpc(')));
    });

    test('iOS: aynı anahtarlar, aynı uç, yarım saatlik zaman çizelgesi', () {
      expect(swift, contains('"${HomeWidgetService.kWidgetApiUrl}"'));
      expect(swift, contains('"${HomeWidgetService.kWidgetApiAnahtar}"'));
      expect(swift, contains('"${HomeWidgetService.kVarlikCanli}"'));
      expect(swift, contains('"functions/v1/widget-fiyat"'));
      expect(swift, contains('var sunucu: Bool? = nil'));
      expect(swift, contains('var hane: Int? = nil'));
      expect(swift, contains('policy: .after(yenileme)'));
      expect(swift, contains('tazelemeAraligi: TimeInterval = 30 * 60'));
      // Kapsam dışı varlıkta eski davranış: `.never`.
      expect(swift, contains('policy: .never'));
      // Kısa zaman aşımı; düz HTTP'ye anahtar gönderilmez.
      expect(swift, contains('zamanAsimi: TimeInterval = 8'));
      expect(swift, contains('kok.scheme == "https"'));
    });

    test('Android: aynı anahtarlar, aynı uç, ağ ana iş parçacığında değil', () {
      expect(kt,
          contains('KEY_API_URL = "${HomeWidgetService.kWidgetApiUrl}"'));
      expect(kt,
          contains('KEY_API_ANAHTAR = "${HomeWidgetService.kWidgetApiAnahtar}"'));
      expect(kt, contains('KEY_CANLI = "${HomeWidgetService.kVarlikCanli}"'));
      expect(kt, contains('"/functions/v1/widget-fiyat"'));
      expect(kt, contains('"sunucu"'));
      expect(kt, contains('"hane"'));
      expect(kt, contains('goAsync()'));
      expect(kt, contains('Thread {'));
      expect(kt, contains('TAZELEME_ARALIGI_MS = 30L * 60 * 1000'));
      expect(kt, contains('startsWith("https://")'));
      // Desen: kesin olmayan, cihazı uyandırmayan alarm (WorkManager yok).
      expect(kt, contains('AlarmManager.RTC'));
    });

    // Müşteri raporu 2026-10-26 21:15 #2/#3: gece, hafta sonu ve fon için
    // seyrek ritim (Edge Function kotası). İki platform aynı kuralı taşır.
    test('ritim: iki platformda aynı saatler ve aynı fon kuralı', () {
      for (final k in [swift, ritimKt]) {
        expect(k, contains('"Europe/Istanbul"'));
        expect(k, contains('"TEFAS:"'));
        expect(k, contains('"KRIPTO:"'));
      }
      expect(swift, contains('gece: TimeInterval = 2 * 60 * 60'));
      expect(ritimKt, contains('GECE_MS = 2L * 60 * 60 * 1000'));
      expect(swift, contains('haftaSonu: TimeInterval = 60 * 60'));
      expect(ritimKt, contains('HAFTA_SONU_MS = 60L * 60 * 1000'));
      expect(swift, contains('fonDeneme: TimeInterval = 60 * 60'));
      expect(ritimKt, contains('FON_DENEME_MS = 60L * 60 * 1000'));
      expect(swift, contains('static let geceSonu = 7'));
      expect(ritimKt, contains('GECE_SONU = 7'));
      expect(swift, contains('static let fonPencereSonu = 22'));
      expect(ritimKt, contains('FON_PENCERE_SONU = 22'));
      // Zaman çizelgesi ve alarm ritimden; fiyat çekimi de ona sorar.
      expect(swift, contains('SandikWidgetRitmi.sonraki('));
      expect(swift, contains('SandikWidgetRitmi.cekilmeli('));
      expect(kt, contains('WidgetRitmi.sonraki('));
      expect(kt, contains('WidgetRitmi.cekilmeli('));
    });

    test('native biçim Dart kuralını taklit eder (aynı ondalık eşikleri)', () {
      // `fiyatOndaligi`: 1 ₺ altı en az 4 anlamlı hane, 2…8.
      expect(swift, contains('min(max(Int(floor(-log10(a))) + 4, 2), 8)'));
      expect(kt, contains('(floor(-log10(a)).toInt() + 4).coerceIn(2, 8)'));
      // İşaret U+2212, sıfır işaretsiz.
      expect(swift, contains(r'"\u{2212}"'));
      expect(kt, contains(r'"−$mutlak"'));
    });
  });
}
