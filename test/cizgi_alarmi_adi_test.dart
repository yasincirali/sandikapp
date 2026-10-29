import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_cizimi.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/cizim_alarmi.dart';
import 'package:portfoy_takip/services/cizim_deposu.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart';
import 'package:portfoy_takip/widgets/cizgi_adi_sayfasi.dart';
import 'package:portfoy_takip/widgets/tam_ekran/grafik_olcegi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Çizgi alarmına ad ve "bildirime / alarma dokununca çizgiyi izle"
/// (yasin 2026-10-29: "Çizgi alarmında isim verebilelim. Ve bildirime ve
/// alarma tıkladığımızda çizgiyi izleyebilelim").
///
/// Kilitlenenler:
/// - Ad `label`'a "varlık · ad" girer; adsız alarm birebir eskisi; bölme
///   ilk ayraçtan, 80 karakter sınırı aşılmaz.
/// - Yatay çizgi alarmı bağdan çizime geri bulunur; varlık portföyden, yoksa
///   takip listesinden; fiyat bilinmiyorsa grafik açılmaz (uydurma ölçek yok).
/// - Ad sayfası ve alarm sayfasındaki ad alanı; Alarmlarım'da yeniden
///   adlandırma yalnız ad kısmını değiştirir.
/// - Push, çan ve Alarmlarım aynı açıcıya ([NotificationService.openCizgi])
///   gider; tam ekran odak çizimini seçili açar ve görünümü çizginin başına
///   kadar genişletir.
const _gun = 86400000;

List<OhlcBar> _barlar(int n, {required int bas}) => [
      for (var i = 0; i < n; i++)
        OhlcBar(
          t: bas + i * _gun,
          acilis: 100 + 10 * math.sin(i / 9),
          enYuksek: 104 + 10 * math.sin(i / 9),
          enDusuk: 96 + 10 * math.sin(i / 9),
          kapanis: 101 + 10 * math.sin(i / 9),
          hacim: 1000 + i.toDouble(),
        ),
    ];

Asset _thy({double fiyat = 101}) => Asset(
      id: 'thy-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 1,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2025, 3, 14),
    );

CizimAlarmi _cizgi(String id, String label, {String cizimId = 'z1'}) =>
    CizimAlarmi(
      id: id,
      userId: 'u1',
      symbol: 'THYAO.IS',
      label: label,
      cizimId: cizimId,
      t1: 1,
      p1: 100,
      t2: 2,
      p2: 101,
      uzanir: true,
      yon: SeviyeYon.yukari,
      createdAt: DateTime(2026, 10, 29),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('ad → label', () {
    test('adsız: yalnız varlık (eski biçim birebir)', () {
      expect(cizgiAlarmEtiketi('THYAO', null), 'THYAO');
      expect(cizgiAlarmEtiketi('THYAO', '   '), 'THYAO');
    });

    test('adlı: "varlık · ad", boşluklar toplanır', () {
      expect(cizgiAlarmEtiketi('THYAO', '  Destek   245 '), 'THYAO · Destek 245');
    });

    test('ad en çok kCizgiAdiAzami, label en çok 80', () {
      final uzun = 'x' * 200;
      final l = cizgiAlarmEtiketi('THYAO', uzun);
      expect(l.length, lessThanOrEqualTo(kAlarmEtiketiAzami));
      expect(cizgiEtiketiniAyir(l).isim!.length, kCizgiAdiAzami);
      expect(cizgiAlarmEtiketi('A' * 70, 'Destek').length,
          lessThanOrEqualTo(kAlarmEtiketiAzami));
    });

    test('geri bölme: ilk ayraç, adsızda null', () {
      expect(cizgiEtiketiniAyir('THYAO'), (varlik: 'THYAO', isim: null));
      expect(cizgiEtiketiniAyir('THYAO · Destek 245'),
          (varlik: 'THYAO', isim: 'Destek 245'));
      expect(cizgiEtiketiniAyir('THYAO · Kırılım · üst'),
          (varlik: 'THYAO', isim: 'Kırılım · üst'));
      // Yeniden adlandırma varlık adını korur.
      final p = cizgiEtiketiniAyir('THYAO · Eski');
      expect(cizgiAlarmEtiketi(p.varlik, 'Yeni'), 'THYAO · Yeni');
      expect(cizgiAlarmEtiketi(p.varlik, ''), 'THYAO');
    });
  });

  group('alarmdan çizgiye', () {
    test('yatay çizgi bağı tersten bulunur', () {
      final baglar = {
        'z1': (alarmId: 'a1', fiyat: 100.0),
        'z2': (alarmId: 'a2', fiyat: 90.0),
      };
      expect(yatayAlarmCizimi(baglar, 'a2'), 'z2');
      expect(yatayAlarmCizimi(baglar, 'yok'), isNull);
      expect(yatayAlarmCizimi(baglar, null), isNull);
      expect(yatayAlarmCizimi(baglar, ''), isNull);
    });

    test('varlık portföyden; kısa ad ve canlı birim', () {
      final g = cizgiGrafigi('THYAO.IS', varliklar: [_thy()])!;
      expect(g.varlik.id, 'thy-1');
      expect(g.ad, 'THYAO');
      expect(g.canliBirim, 101);
    });

    test('portföyde yoksa takip listesinden gözlem varlığı', () {
      final w = WatchlistItem(
        id: 'w1',
        userId: 'u1',
        ticker: 'ASELS.IS',
        name: 'Aselsan',
        type: AssetType.hisse,
        currency: 'TRY',
        addedAt: DateTime(2026, 1, 1),
        currentPrice: 150,
      );
      final g = cizgiGrafigi('ASELS.IS', varliklar: [_thy()], takip: [w])!;
      expect(g.varlik.ticker, 'ASELS.IS');
      expect(g.ad, 'ASELS');
      expect(g.canliBirim, 150);
    });

    test('fiyat bilinmiyorsa ya da varlık yoksa null (uydurma ölçek yok)', () {
      expect(cizgiGrafigi('THYAO.IS', varliklar: [_thy(fiyat: 0)]), isNull);
      expect(cizgiGrafigi('GARAN.IS', varliklar: [_thy()]), isNull);
    });
  });

  group('açılış görünümü', () {
    test('zamanIndeksiBul ölçekle aynı', () {
      final z = [for (var i = 0; i < 10; i++) i * _gun];
      final o = GrafikOlcegi(
          zamanlar: z,
          aralikMs: _gun,
          gorunum: (bas: 0, son: 10),
          genislik: 100,
          fiyatAlani: 100,
          dusuk: 0,
          yuksek: 1);
      for (final t in [-3 * _gun, 0, _gun ~/ 2, 5 * _gun, 12 * _gun]) {
        expect(zamanIndeksiBul(z, _gun, t), o.zamanIndeksi(t));
      }
    });

    test('çizgi pencerede ise varsayılan; solda ise oraya genişler', () {
      const v = (bas: 100.0, son: 204.0);
      expect(odakliGorunum(v, 150), v);
      expect(odakliGorunum(v, 40), (bas: 37.0, son: 204.0));
      expect(odakliGorunum(v, double.nan), v);
    });
  });

  group('ad sayfası', () {
    Future<List<String>> ac(WidgetTester tester,
        {String baslangic = '', Object? hata}) async {
      final yazilan = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCizgiAdiSayfasi(
                context,
                baslik: 'Çizgi alarmı',
                dugme: 'Alarmı kur',
                baslangic: baslangic,
                kaydet: (isim) async {
                  if (hata != null) throw hata;
                  yazilan.add(isim);
                },
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return yazilan;
    }

    testWidgets('ad isteğe bağlı: boşla da kurulur', (tester) async {
      final y = await ac(tester);
      expect(find.text('Çizginin adı (isteğe bağlı)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cizgiAdiKaydet')));
      await tester.pumpAndSettle();
      expect(y, ['']);
      expect(find.byType(CizgiAdiSayfasi), findsNothing);
    });

    testWidgets('yazılan ad kırpılıp gider; düğme 44 pt', (tester) async {
      final y = await ac(tester, baslangic: 'Eski');
      expect(find.text('Eski'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('cizgiAdiAlani')), '  Destek 245 ');
      final dugme = find.byKey(const ValueKey('cizgiAdiKaydet'));
      expect(tester.getSize(dugme).height,
          greaterThanOrEqualTo(SandikTouch.min));
      await tester.tap(dugme);
      await tester.pumpAndSettle();
      expect(y, ['Destek 245']);
    });

    testWidgets('hata sayfayı kapatmaz, ham metin göstermez', (tester) async {
      await ac(tester, hata: StateError('row-level security'));
      await tester.tap(find.byKey(const ValueKey('cizgiAdiKaydet')));
      await tester.pumpAndSettle();
      expect(find.byType(CizgiAdiSayfasi), findsOneWidget);
      expect(find.textContaining('row-level'), findsNothing);
    });
  });

  group('alarm sayfası (yatay çizgi)', () {
    const aday = AlarmAdayi('THYAO.IS', 'THYAO', 300);

    Future<List<AlarmKurulumu?>> ac(WidgetTester tester,
        {required bool cizgiAdi}) async {
      final sonuclar = <AlarmKurulumu?>[];
      tester.view.physicalSize = const Size(390 * 3, 1200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                sonuclar.add(await showModalBottomSheet<AlarmKurulumu>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => AlarmKurSheet(
                      adaylar: const [aday],
                      sabit: true,
                      baslangicHedef: 310,
                      odakla: false,
                      cizgiAdi: cizgiAdi),
                ));
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return sonuclar;
    }

    testWidgets('çizgiden: ad alanı var, ad kuruluma girer', (tester) async {
      final s = await ac(tester, cizgiAdi: true);
      final alan = find.byKey(const ValueKey('cizgiAdiAlani'));
      expect(alan, findsOneWidget);
      await tester.enterText(alan, ' Direnç ');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(s.single?.isim, 'Direnç');
      expect(s.single?.hedef, 310);
    });

    testWidgets('diğer yollarda alan yok (sayfa birebir eski)', (tester) async {
      final s = await ac(tester, cizgiAdi: false);
      expect(find.byKey(const ValueKey('cizgiAdiAlani')), findsNothing);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(s.single?.isim, isNull);
    });

    test('akış: label yalnız çizgiden adla kurulur', () {
      final k = ekranKaynagiSync('lib/widgets/alarm_kur_sheet.dart');
      expect(k, contains(
          'label: cizgiAdi ? cizgiAlarmEtiketi(k.aday.ad, k.isim) : k.aday.ad,'));
      final d = ekranKaynagiSync('lib/widgets/tam_ekran/cizim_alarm_dugmesi.dart');
      expect(d, contains('cizgiAdi: true,'));
      expect(d, contains('label: cizgiAlarmEtiketi(ad, isim),'));
      expect(d, contains('showCizgiAdiSayfasi('));
    });
  });

  group('Alarmlarım', () {
    final yazilan = <String, String>{};
    List<CizimAlarmi> cizgiler = const [];
    List<PriceAlert> fiyatlar = const [];

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          priceAlertsProvider.overrideWith(() => _F(fiyatlar, yazilan)),
          yuzdeAlarmlariProvider.overrideWith(_Y.new),
          gostergeAlarmlariProvider.overrideWith(_G.new),
          cizimAlarmlariProvider.overrideWith(() => _C(cizgiler, yazilan)),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PriceAlertsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      yazilan.clear();
      cizgiler = const [];
      fiyatlar = const [];
    });

    testWidgets('çizgi alarmı: adıyla görünür, kalemle yeniden adlandırılır',
        (tester) async {
      cizgiler = [_cizgi('c1', 'THYAO · Destek 245')];
      await pump(tester);
      expect(find.text('THYAO · Destek 245'), findsOneWidget);
      expect(find.text('Grafikte aç'), findsOneWidget);
      final kalem = find.byKey(const ValueKey('cizgiAlarmiAdlandir'));
      expect(tester.getSize(kalem).height, greaterThanOrEqualTo(44));
      await tester.tap(kalem);
      await tester.pumpAndSettle();
      // Yalnız ad kısmı düzenlenir; varlık adı korunur.
      expect(find.widgetWithText(TextField, 'Destek 245'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('cizgiAdiAlani')), 'Kırılım');
      await tester.tap(find.byKey(const ValueKey('cizgiAdiKaydet')));
      await tester.pumpAndSettle();
      expect(yazilan, {'c1': 'THYAO · Kırılım'});
      expect(find.text('THYAO · Kırılım'), findsOneWidget);
    });

    testWidgets('bağsız fiyat alarmı birebir eski: kalem ve ipucu yok',
        (tester) async {
      fiyatlar = [
        PriceAlert(
          id: 'p1',
          userId: 'u1',
          symbol: 'THYAO.IS',
          label: 'THYAO',
          targetPrice: 300,
          direction: 'above',
          enabled: true,
          createdAt: DateTime(2026, 10, 1),
        ),
      ];
      await pump(tester);
      expect(find.byKey(const ValueKey('cizgiAlarmiAdlandir')), findsNothing);
      expect(find.text('Grafikte aç'), findsNothing);
    });

    testWidgets('yatay çizgiye bağlı fiyat alarmı da açılır ve adlandırılır',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        PrefKeys.grafikCizimAlarmBaglari:
            '{"z9":{"a":"p1","p":300.0}}',
      });
      fiyatlar = [
        PriceAlert(
          id: 'p1',
          userId: 'u1',
          symbol: 'THYAO.IS',
          label: 'THYAO',
          targetPrice: 300,
          direction: 'above',
          enabled: true,
          createdAt: DateTime(2026, 10, 1),
        ),
      ];
      await pump(tester);
      expect(find.text('Grafikte aç'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cizgiAlarmiAdlandir')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('cizgiAdiAlani')), 'Direnç');
      await tester.tap(find.byKey(const ValueKey('cizgiAdiKaydet')));
      await tester.pumpAndSettle();
      expect(yazilan, {'p1': 'THYAO · Direnç'});
    });

    test('satır dokunuşu push ile aynı açıcıya gider', () {
      final k = ekranKaynagiSync('lib/screens/price_alerts_screen.dart');
      expect(k, contains(
          'NotificationService.instance.openCizgi(sembol, cizimId: cizimId)'));
      expect(k, contains('onAc: cz == null ? null : () => _cizgiyiAc(cz.symbol, cz.cizimId)'));
      expect(k, contains('onAc: cizim == null ? null : () => _cizgiyiAc(alarm.symbol, cizim)'));
    });
  });

  group('bildirimden çizgiye (kaynak)', () {
    test('push: çizgi anahtarları openCizgi\'ye, yoksa eski yol', () {
      final k = ekranKaynagiSync('lib/services/notification_service.dart');
      final dal = k.substring(k.indexOf('if (type == priceAlertType) {'));
      expect(dal, contains("data['cizim_id']"));
      expect(dal, contains("data['cizim_alarm_id']"));
      expect(dal, contains("data['alert_id']"));
      expect(dal, contains('openCizgi(symbol,'));
      expect(dal.indexOf('openPriceAlertAsset(symbol);'), greaterThan(0));
      // Çizgi bulunamazsa varlığa düşülür (eski davranış).
      final ac = k.substring(k.indexOf('Future<void> openCizgi('));
      expect(ac, contains('varligaDus()'));
      expect(ac, contains('yatayaZorla: true'));
      expect(ac, contains('odakCizim: id'));
    });

    test('çan: fiyat alarmı alertId, çizgi alarmı cizim_id ile', () {
      final k = ekranKaynagiSync('lib/screens/home_screen.dart');
      expect(k, contains('alertId: bildirim.alertId,'));
      expect(k, contains("cizimId: b.data['cizim_id']?.toString(),"));
      expect(k, contains("cizimAlarmId: b.data['cizim_alarm_id']?.toString()"));
    });

    test('tam ekran: yataya alınır, kapanınca sistem ayarına bırakılır', () {
      final k = ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart');
      expect(k, contains('DeviceOrientation.landscapeLeft'));
      expect(k, contains('SystemChrome.setPreferredOrientations(const [])'));
      expect(k, contains('dikteKapan: !yatayaZorla,'));
    });
  });

  group('tam ekran odak', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MumVerisi.instance.onbellegiTemizle();
    });
    tearDown(() => MumVerisi.testCekici = null);

    testWidgets('odak çizimi seçili açılır, görünüm çizginin başını kapsar',
        (tester) async {
      final simdi = DateTime.now();
      final bas = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 199))
          .millisecondsSinceEpoch;
      MumVerisi.testCekici = (a, ar, b, s) async => _barlar(200, bas: bas);
      // Çizgi mum 20'de başlıyor: varsayılan pencere (son ~90 mum) dışında.
      await CizimDeposu.instance.yaz('THYAO.IS', [
        GrafikCizimi(
            tur: CizimTuru.yatay,
            a: CizimNoktasi(bas + 150 * _gun, 100),
            id: 'baska'),
        GrafikCizimi(
            tur: CizimTuru.trend,
            a: CizimNoktasi(bas + 20 * _gun, 95),
            b: CizimNoktasi(bas + 190 * _gun, 100),
            id: 'hedef'),
      ]);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          priceAlertsProvider.overrideWith(() => _F(const [], {})),
          cizimAlarmlariProvider.overrideWith(() => _C(
              [_cizgi('c1', 'THYAO · Destek 245', cizimId: 'hedef')], {})),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TamEkranGrafikEkrani(
            varlik: _thy(),
            ad: 'THYAO',
            canliBirim: 101,
            odakCizim: 'hedef',
            yatayaZorla: true,
            dikteKapan: false,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final s = tester.state<TamEkranGrafikEkraniState>(
          find.byType(TamEkranGrafikEkrani));
      expect(s.cizimler[s.secili].id, 'hedef');
      final g = s.gorunum!;
      expect(g.bas, lessThanOrEqualTo(20));
      expect(g.son, greaterThanOrEqualTo(199), reason: 'bugün de görünür');
      // Alarmlı çizginin adı çizginin ucunda (yalnız ad, varlık değil).
      await tester.pump();
      expect(find.text('Destek 245'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

class _F extends PriceAlertsNotifier {
  _F(this._liste, this._yazilan);
  final List<PriceAlert> _liste;
  final Map<String, String> _yazilan;

  @override
  Future<List<PriceAlert>> build() async => _liste;

  @override
  Future<void> etiketiGuncelle(String id, String label) async {
    _yazilan[id] = label;
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        a.id == id
            ? PriceAlert(
                id: a.id,
                userId: a.userId,
                symbol: a.symbol,
                label: label,
                targetPrice: a.targetPrice,
                direction: a.direction,
                enabled: a.enabled,
                createdAt: a.createdAt)
            : a,
    ]);
  }
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => const [];
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => const [];
}

class _C extends CizimAlarmlariNotifier {
  _C(this._liste, this._yazilan);
  final List<CizimAlarmi> _liste;
  final Map<String, String> _yazilan;

  @override
  Future<List<CizimAlarmi>> build() async => _liste;

  @override
  Future<CizimAlarmi> etiketiGuncelle(String id, String label) async {
    _yazilan[id] = label;
    final eski = liste.firstWhere((a) => a.id == id);
    final yeni = _cizgi(id, label, cizimId: eski.cizimId);
    state = AsyncData([
      for (final a in liste) a.id == id ? yeni : a,
    ]);
    return yeni;
  }
}
