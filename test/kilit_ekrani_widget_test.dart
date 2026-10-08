import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

/// iOS kilit ekranı widget'ı (karar 4.1 / 4.3 / 4.4 / 4.5, 2026-09-30).
///
/// Swift bu makinede derlenmiyor; iki taraf arasındaki SÖZLEŞME (anahtar
/// adları, widget türü, paket kaydı) kaynak metinden kilitlenir — tek harf
/// farkı widget'ı sessizce "veri yok" hâline düşürür. Dart tarafının
/// yazdığı değerler kanal taklidiyle doğrulanır.
String _oku(String yol) =>
    File(yol).readAsStringSync().replaceAll('\r\n', '\n');

class _Kanal {
  final Map<String, Object?> yazilan = {};
  final List<Map<String, Object?>> yenilemeler = [];

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
      }
      return null;
    });
  }

  void kaldir() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
}

PortfolioState _durum() => PortfolioState(
      assets: [
        Asset(
          id: 'a1',
          userId: 'u1',
          name: 'Türk Hava Yolları',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 100,
          purchasePrice: 200,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 300,
          addedDate: DateTime(2026, 1, 1),
          kind: AssetKind.buy,
        ),
      ],
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Kanal kanal;

  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() => kanal = _Kanal()..kur());
  tearDown(() {
    kanal.kaldir();
    HomeWidgetService.instance.lockScreenAmounts = false;
    HomeWidgetService.instance.canliEtkinligiIzle = false;
  });

  group('Dart tarafı yazımı', () {
    test('bakiye gizliyken kilit ekranı yüzdeyi de göstermez (4.5)', () async {
      await HomeWidgetService.instance.update(_durum(), hideBalance: true);
      expect(kanal.yazilan['sandik_hidden'], isTrue);
      expect(kanal.yazilan['sandik_lock_pct'], '');
    });

    test('görünürken: gizli değil; ölçüm yoksa yüzde uydurulmaz ("—")',
        () async {
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_hidden'], isFalse);
      expect(kanal.yazilan['sandik_lock_pct'], '—');
    });

    test('tutar izni Canlı Etkinlik tercihinden taşınır (4.4)', () async {
      HomeWidgetService.instance.lockScreenAmounts = false;
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_lock_amounts'], isFalse);
      HomeWidgetService.instance.lockScreenAmounts = true;
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_lock_amounts'], isTrue);
    });
  });

  // 2026-10-03 (yasin): "Canlı aktivite, dinamik ada, kilit ekranı widget,
  // performans günlük aynı değeri göstermeli ve senkron olmalı."
  group('Canlı Etkinlik ile eşitleme', () {
    final swift = _oku('ios/SandikWidget/SandikHomeWidget.swift');

    test('bayrak (canli_etkinlik_dakikalik) widget deposuna taşınır', () async {
      HomeWidgetService.instance.canliEtkinligiIzle = false;
      await HomeWidgetService.instance.update(_durum(), hideBalance: false);
      expect(kanal.yazilan['sandik_lock_follow_la'], isFalse);
      HomeWidgetService.instance.canliEtkinligiIzle = true;
      await HomeWidgetService.instance.update(_durum(), hideBalance: true);
      expect(kanal.yazilan['sandik_lock_follow_la'], isTrue,
          reason: 'gizliyken de yazılır; widget gizliliği ayrıca bilir');
      final main = _oku('lib/main.dart');
      expect(
          main,
          contains('HomeWidgetService.instance.canliEtkinligiIzle =\n'
              '        RemoteConfigService.instance.canliEtkinlikDakikalik;'));
    });

    test('Swift: bayrak açıksa rakam açık etkinliğin içeriğinden', () {
      expect(swift, contains('"sandik_lock_follow_la"'));
      expect(swift, contains('import ActivityKit'));
      expect(swift, contains('Activity<SandikActivityAttributes>.activities'));
      // Bayatlamış ya da maskeli içerik rakam sayılmaz.
      expect(swift, contains('bayat <= simdi'));
      expect(swift, contains('if d.isHidden { return nil }'));
      // Kendi gizlilik bayrağı önce gelir.
      expect(swift,
          contains('if !gizli, defaults.bool(forKey: KilitKeys.canliEtkinligiIzle)'));
    });

    test('Swift: işaretli yüzde Dart fmtPctIsaretli kuralıyla', () {
      // Sıfıra işaret yok, eksi U+2212, ölçüm yoksa "—".
      expect(swift, contains('let sifir = pct == "%0,00"'));
      expect(swift, contains(r'(isPositive ? "+" : "\u{2212}") + pct'));
      expect(swift, contains('isaretli = "—"'));
    });

    test('Swift: izlerken zaman çizelgesi kendini tazeler, 18:00 girdisi kalır',
        () {
      expect(swift, contains('entries: girdiler,\n'
          '                policy: .after(Date().addingTimeInterval(5 * 60))'));
    });

    // 2026-10-08 (yasin, kart kararı "Yalnız saat damgası"): widget
    // uygulamanın kaydını gösteriyorsa hangi anın rakamı olduğu yazar;
    // Canlı Etkinlik'ten okununca saat yok (rakam zaten dakikalık).
    test('Swift: uygulama kaydından okununca saat damgası', () {
      expect(swift,
          contains('asOfText: gizli ? "" : (defaults.string(forKey: WidgetKeys.updatedAt) ?? "")'));
      expect(swift, contains('itibarıyla'));
      expect(swift, contains('sparkline: sparkline, asOfText: asOfText)'),
          reason: '18:00 girdisi saati kaybetmemeli');
      final dart = _oku('lib/services/home_widget_service.dart');
      expect(dart, contains("_kUpdatedAt, DateFormat('HH:mm', 'tr_TR')"),
          reason: 'Swift "HH:mm" bekler');
    });
  });

  group('Swift sözleşmesi', () {
    final dart = _oku('lib/services/home_widget_service.dart');
    final swift = _oku('ios/SandikWidget/SandikHomeWidget.swift');
    final paket = _oku('ios/SandikWidget/SandikWidgetBundle.swift');

    test('kilit ekranı anahtarları iki tarafta BİREBİR', () {
      for (final anahtar in const [
        'sandik_lock_amounts',
        'sandik_lock_pct',
        'sandik_hidden',
      ]) {
        expect(dart, contains("'$anahtar'"), reason: 'Dart: $anahtar');
        expect(swift, contains('"$anahtar"'), reason: 'Swift: $anahtar');
      }
    });

    test('widget türü Dart yenileme adıyla aynı ve pakette kayıtlı', () {
      expect(dart, contains("_iOSKilitWidgetName = 'SandikKilitWidget'"));
      expect(swift, contains('let kind = "SandikKilitWidget"'));
      expect(paket, contains('SandikKilitWidget()'));
    });

    // Üçüncü tur (2026-09-30): "canlı seans kartı" — Apple'ın kilit ekranı
    // teknolojileri. Biri sessizce silinirse kart eski düz hâline döner.
    test('canlı seans kartı: geri sayım, 18:00 girdisi, gizlilik', () {
      expect(swift, contains('Text(timerInterval:'));
      expect(swift, contains('girdiler.append(simdi.kapali(at: bitis))'),
          reason: 'Seans bitince kart kendiliğinden kapalıya dönmeli');
      expect(swift, contains('.privacySensitive()'),
          reason: 'Tutar kilitliyken sistemce örtülmeli');
      expect(swift, contains('.contentTransition(.numericText('));
      expect(swift, contains('AccessoryWidgetBackground()'));
    });

    // Kullanıcı kararı 2026-10-01: "seans çizgisini kaldıralım" — kilit
    // ekranı widget'ında da, Canlı Etkinlik'te (kilit kartı + Dinamik Ada)
    // de seans ilerleme çubuğu YOK. Geri sayım metni kalır.
    test('seans çubuğu yok: kilit widget\'ı ve Canlı Etkinlik', () {
      final ada = _oku('ios/SandikWidget/SandikLiveActivity.swift');
      for (final kaynak in [swift, ada]) {
        expect(kaynak, isNot(contains('ProgressView(')));
        expect(kaynak, isNot(contains('SandikSeansCubugu')));
      }
    });

    // Kullanıcı bildirimi 2026-10-01: yazı ile grafik üst üste biniyordu.
    // Eğri kendi bandında; görünüm ZStack ile katmanlanmaz.
    test('kilit kartı: metin ve eğri üst üste binmez', () {
      final bas = swift.indexOf('struct SandikKilitView');
      final son = swift.indexOf('struct SandikKilitWidget');
      final gorunum = swift.substring(bas, son);
      expect(gorunum, isNot(contains('ZStack')));
      expect(gorunum, contains('egriSeridi'));
      expect(gorunum, contains('.layoutPriority(2)'),
          reason: 'Yer daralınca önce eğri incelmeli, yüzde değil');
    });

    test('TEK kart: yalnız dikdörtgen; yuvarlak ve tek satır YOK', () {
      expect(swift, contains('.supportedFamilies([.accessoryRectangular])'));
      expect(swift, isNot(contains('.accessoryCircular')),
          reason: 'İkinci tur: kilit ekranı iki parçalı olmasın');
      expect(swift, isNot(contains('.accessoryInline')),
          reason: 'Karar 4.2: tek satırlık widget yapılmadı');
    });

    test('Dinamik Ada: renkli yön halkası; gizli/ölçümsüz → logo (4.3)', () {
      final ada = _oku('ios/SandikWidget/SandikLiveActivity.swift');
      final bas = ada.indexOf('} compactLeading: {');
      final son = ada.indexOf('} compactTrailing: {');
      final kompakt = ada.substring(bas, son);
      expect(kompakt, contains('SandikYonHalkasi('));
      expect(kompakt, contains('SandikLogoMark('));
      final minimal = ada.substring(ada.indexOf('} minimal: {'));
      expect(minimal.substring(0, 1500), contains('SandikYonHalkasi('));
      // Sayı METİNDEN okunur (sunucu push'u yeni alan taşımaz) ve gizliyken
      // yok sayılır.
      expect(ada, contains('static func yuzde(state:'));
      expect(ada, contains('if state.isHidden { return nil }'));
    });
  });
}
