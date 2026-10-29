import 'dart:convert';
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
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show initPreferencesCache;
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/cizim_deposu.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/tam_ekran/grafik_olcegi.dart';
import 'package:portfoy_takip/widgets/tam_ekran/yan_cevirince_tam_ekran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Yatay tam ekran grafik ve çizim araçları (yasin, 2026-10-23; benchmark
/// kararı: yatay grafik + çizim + telefonda saklama ücretsiz).
///
/// Kilitlenenler:
///  · Çizim ZAMAN + fiyatla saklanır; indeks ↔ zaman dönüşümü gidip gelir.
///  · İsabet: uç noktası gövdeden önce, üst üste binende en son çizilen.
///  · Mıknatıs yakın OHLC'ye yapışır, uzaktaysa serbest kalır.
///  · Depo: sembol başına, bozuk kayıt grafiği açılmaz hâle getirmez.
///  · Giriş yalnız dik → yatay geçişte; tablette ve üstte sayfa varken yok.
///  · Ekranda çiz → seç → sil → geri al çalışır ve telefona yazılır.
const _gun = 86400000;

final _t0 = DateTime(2026, 1, 5).millisecondsSinceEpoch;

List<OhlcBar> _barlar(int n, {int? bas}) => [
      for (var i = 0; i < n; i++)
        OhlcBar(
          t: (bas ?? _t0) + i * _gun,
          acilis: 100 + 10 * math.sin(i / 9),
          enYuksek: 104 + 10 * math.sin(i / 9),
          enDusuk: 96 + 10 * math.sin(i / 9),
          kapanis: 101 + 10 * math.sin(i / 9),
          hacim: 1000 + i.toDouble(),
        ),
    ];

GrafikOlcegi _olcek(List<int> zamanlar) => GrafikOlcegi(
      zamanlar: zamanlar,
      aralikMs: _gun,
      gorunum: (bas: -0.5, son: 99.5),
      genislik: 1000,
      fiyatAlani: 500,
      dusuk: 0,
      yuksek: 200,
    );

Asset _thy() => Asset(
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
      currentPrice: 101,
      addedDate: DateTime(2025, 3, 14),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('ölçek', () {
    // Hafta sonu boşluklu zamanlar: indeks 5'ten sonra 3 günlük sıçrama.
    final z = [
      for (var i = 0; i < 100; i++) _t0 + (i < 5 ? i : i + 2) * _gun,
    ];
    final o = _olcek(z);

    test('zaman ↔ indeks gidip gelir (boşluk dahil)', () {
      for (final i in [0, 4, 5, 6, 50, 99]) {
        expect(o.zamanIndeksi(z[i]), i.toDouble());
        expect(o.indeksZamani(i.toDouble()), z[i]);
      }
      // Mum arası kesirli nokta.
      expect(o.zamanIndeksi(z[10] + _gun ~/ 2), closeTo(10.5, 1e-9));
    });

    test('son mumdan sonrası aralık adımıyla uzar', () {
      expect(o.indeksZamani(102), z.last + 3 * _gun);
      expect(o.zamanIndeksi(z.last + 3 * _gun), closeTo(102, 1e-9));
      expect(o.indeksZamani(-2), z.first - 2 * _gun);
    });

    test('ekran ↔ veri dönüşümü tutarlı', () {
      final n = CizimNoktasi(z[40], 120);
      final e = o.ekranda(n);
      final geri = o.veride(e);
      expect(geri.t, n.t);
      expect(geri.p, closeTo(120, 1e-9));
    });
  });

  group('isabet', () {
    final z = [for (var i = 0; i < 100; i++) _t0 + i * _gun];
    final o = _olcek(z);
    const alan = Size(1000, 500);

    test('uç noktası tutamak olarak seçilir', () {
      final c = GrafikCizimi(
          tur: CizimTuru.trend,
          a: CizimNoktasi(z[10], 100),
          b: CizimNoktasi(z[50], 150));
      final a = o.ekranda(c.a);
      final h = cizimIsabeti([c], o, a + const Offset(4, 3), alan);
      expect(h, isNotNull);
      expect(h!.tutamak, 'a');
      final orta = (a + o.ekranda(c.b!)) / 2;
      expect(cizimIsabeti([c], o, orta, alan)!.tutamak, isNull);
      expect(cizimIsabeti([c], o, orta + const Offset(0, 60), alan), isNull);
    });

    test('üst üste binen yatay çizgilerde en son çizilen kazanır', () {
      final eski = GrafikCizimi(
          tur: CizimTuru.yatay, a: CizimNoktasi(z[10], 100));
      final yeni = GrafikCizimi(
          tur: CizimTuru.yatay, a: CizimNoktasi(z[60], 100));
      final y = o.y(100);
      expect(cizimIsabeti([eski, yeni], o, Offset(500, y), alan)!.indeks, 1);
    });

    test('kutu içine dokunmak kutuyu seçer', () {
      final k = GrafikCizimi(
          tur: CizimTuru.kutu,
          a: CizimNoktasi(z[20], 160),
          b: CizimNoktasi(z[40], 120));
      final merkez = (o.ekranda(k.a) + o.ekranda(k.b!)) / 2;
      expect(cizimIsabeti([k], o, merkez, alan)?.indeks, 0);
    });
  });

  group('mıknatıs', () {
    final m = _barlar(100);
    final o = _olcek([for (final b in m) b.t]);

    test('yakın yükseğe yapışır', () {
      final b = m[30];
      final e = Offset(o.x(30), o.y(b.enYuksek) - 5); // yükseğin hemen üstü
      final n = miknatisla(m, o, e);
      expect(n.t, b.t);
      expect(n.p, b.enYuksek);
    });

    test('uzaktaysa serbest nokta', () {
      final e = Offset(o.x(30), o.y(m[30].enYuksek) - 120);
      final n = miknatisla(m, o, e);
      expect(n.p, isNot(m[30].enYuksek));
      expect(n.p, closeTo(o.p(e.dy), 1e-9));
    });
  });

  group('depo', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('sembol başına yazılır ve okunur', () async {
      final c = GrafikCizimi(
          tur: CizimTuru.trend,
          a: CizimNoktasi(_t0, 10),
          b: CizimNoktasi(_t0 + _gun, 12));
      await CizimDeposu.instance.yaz('thyao.is', [c]);
      final okunan = await CizimDeposu.instance.oku('THYAO.IS');
      expect(okunan, hasLength(1));
      expect(okunan.single.tur, CizimTuru.trend);
      expect(okunan.single.b!.p, 12);
      expect(await CizimDeposu.instance.oku('ASELS.IS'), isEmpty);
    });

    test('boş liste sembolü siler', () async {
      final c =
          GrafikCizimi(tur: CizimTuru.yatay, a: CizimNoktasi(_t0, 10));
      await CizimDeposu.instance.yaz('X', [c]);
      await CizimDeposu.instance.yaz('X', const []);
      final sp = await SharedPreferences.getInstance();
      expect(jsonDecode(sp.getString(PrefKeys.grafikCizimleri)!), isEmpty);
    });

    test('bozuk kayıt atlanır, sağlamlar okunur', () async {
      SharedPreferences.setMockInitialValues({
        PrefKeys.grafikCizimleri: jsonEncode({
          'X': [
            {'tur': 'yok', 'a': {'t': 1, 'p': 2}},
            {
              'tur': 'yatay',
              'a': {'t': _t0, 'p': 5},
            },
          ],
        }),
      });
      final okunan = await CizimDeposu.instance.oku('X');
      expect(okunan, hasLength(1));
      expect(okunan.single.tur, CizimTuru.yatay);
    });

    test('sembol başına üst sınır', () async {
      await CizimDeposu.instance.yaz('X', [
        for (var i = 0; i < CizimDeposu.enCokCizim + 7; i++)
          GrafikCizimi(tur: CizimTuru.yatay, a: CizimNoktasi(_t0, i * 1.0)),
      ]);
      final okunan = await CizimDeposu.instance.oku('X');
      expect(okunan, hasLength(CizimDeposu.enCokCizim));
      // En yeniler kalır.
      expect(okunan.last.a.p, CizimDeposu.enCokCizim + 6.0);
    });
  });

  group('yan çevirince açılış', () {
    Future<int> dondur(WidgetTester tester,
        {required Size dik, bool etkin = true}) async {
      var acilis = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = dik;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: YanCevirinceTamEkran(
              etkin: etkin,
              ac: (_) async => acilis++,
              child: const SizedBox(height: 200),
            ),
          ),
        ),
      ));
      tester.view.physicalSize = Size(dik.height, dik.width);
      await tester.pump();
      await tester.pump();
      return acilis;
    }

    testWidgets('telefonda dik → yatay bir kez açar', (tester) async {
      expect(await dondur(tester, dik: const Size(390, 844)), 1);
      // Yatayda kalıp yeniden çizim tetiklenmez; dik → yatay yine açar.
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
    });

    testWidgets('tablette açmaz', (tester) async {
      expect(await dondur(tester, dik: const Size(820, 1180)), 0);
    });

    testWidgets('mum kaynağı yoksa açmaz', (tester) async {
      expect(
          await dondur(tester, dik: const Size(390, 844), etkin: false), 0);
    });

    testWidgets('sayfa zaten yatay açıldıysa açmaz', (tester) async {
      var acilis = 0;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: YanCevirinceTamEkran(
            etkin: true,
            ac: (_) async => acilis++,
            child: const SizedBox.expand(),
          ),
        ),
      ));
      await tester.pump();
      expect(acilis, 0);
    });
  });

  // yasin 2026-10-29: "Detaylı varlık detayı ekranında yan çevirmeyle ilgili
  // bir bilgi içermeli mi?" — çip geri gelmez; düğme olmayan tek seferlik
  // satır, yatay bir kez açılınca kaybolur.
  group('yan çevirme ipucu', () {
    const ipucu = 'Detaylı grafik için telefonu yan çevir';
    // Tercih önbelleği süreç geneli: her testte taze diskten kurulur.
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    Future<void> kur(WidgetTester tester,
        {Size boyut = const Size(390, 844),
        bool etkin = true,
        Future<void> Function(BuildContext)? ac}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = boyut;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: YanCevirinceTamEkran(
              etkin: etkin,
              ac: ac ?? (_) async {},
              child: const SizedBox(height: 200),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('telefonda dik: grafiğin altında, düğme değil',
        (tester) async {
      final anlam = tester.ensureSemantics();
      await kur(tester);
      expect(find.text(ipucu), findsOneWidget);
      expect(find.byIcon(Icons.screen_rotation_rounded), findsOneWidget);
      final kok = find.byKey(const ValueKey('yanCevirIpucu'));
      expect(
          find.descendant(of: kok, matching: find.byType(InkWell)), findsNothing);
      expect(find.descendant(of: kok, matching: find.byType(GestureDetector)),
          findsNothing);
      expect(tester.getSemantics(find.text(ipucu)).flagsCollection.isButton,
          isFalse);
      // Grafiğin ALTINDA.
      expect(tester.getTopLeft(kok).dy, greaterThanOrEqualTo(200));
      anlam.dispose();
    });

    testWidgets('mum kaynağı yoksa ve tablette yok', (tester) async {
      await kur(tester, etkin: false);
      expect(find.text(ipucu), findsNothing);
      await kur(tester, boyut: const Size(820, 1180));
      expect(find.text(ipucu), findsNothing);
    });

    testWidgets('yatay bir kez açılınca kalıcı olarak kaybolur',
        (tester) async {
      var acilis = 0;
      await kur(tester, ac: (_) async => acilis++);
      expect(find.text(ipucu), findsOneWidget);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump();
      expect(acilis, 1);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.text(ipucu), findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(PrefKeys.yatayGrafikIpucu), isTrue);
    });

    testWidgets('daha önce açıldıysa hiç görünmez', (tester) async {
      SharedPreferences.setMockInitialValues({PrefKeys.yatayGrafikIpucu: true});
      await initPreferencesCache();
      await kur(tester);
      expect(find.text(ipucu), findsNothing);
    });

    testWidgets('İngilizce metin', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: YanCevirinceTamEkran(
              etkin: true,
              ac: (_) async {},
              child: const SizedBox(height: 200),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('Turn your phone sideways for the detailed chart'),
          findsOneWidget);
    });

    test('varlık detayı ipucunu sabit yükseklikli kartın altına koyar', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(k, contains('ipucu: false'));
      expect(k, contains('YanCevirIpucu('));
      final v = ekranKaynagiSync('lib/widgets/katmanli_fiyat_grafigi.dart');
      expect(v, isNot(contains('ipucu: false')),
          reason: 'varlık sayfasında ipucu sarmalayıcının içinde');
    });

    test('eski "düğme" metni kalmadı (giriş yalnız yan çevirmek)', () {
      expect(
          ekranKaynagiSync('lib/services/ozellik_olcumu.dart')
              .contains('düğmeyle ya da yan çevirerek'),
          isFalse);
      expect(
          ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart')
              .contains('Düğme ve yan çevirme aynı ekranı açar'),
          isFalse);
    });
  });

  group('tam ekran ekranı', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MumVerisi.instance.onbellegiTemizle();
      final simdi = DateTime.now();
      final bas = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 199))
          .millisecondsSinceEpoch;
      MumVerisi.testCekici = (a, ar, b, s) async => _barlar(200, bas: bas);
    });
    tearDown(() => MumVerisi.testCekici = null);

    Future<TamEkranGrafikEkraniState> ac(WidgetTester tester,
        {Size boyut = const Size(844, 390)}) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = boyut;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TamEkranGrafikEkrani(
            varlik: _thy(),
            ad: 'THYAO',
            canliBirim: 101,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return tester.state<TamEkranGrafikEkraniState>(
          find.byType(TamEkranGrafikEkrani));
    }

    Rect grafikAlani(WidgetTester tester) => tester.getRect(find.byWidgetPredicate(
        (w) =>
            w is Listener &&
            w.onPointerSignal != null &&
            w.onPointerDown != null));

    Future<void> bitir(WidgetTester tester) async {
      // Bildirim zamanlayıcısı bitsin.
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('mumlar yüklenir, araçlar 44 pt ve etiketli', (tester) async {
      final s = await ac(tester);
      expect(s.olcek, isNotNull);
      expect(s.aralik.name, 'gun1');
      for (final ad in ['İmleç', 'Trend çizgisi', 'Işın', 'Yatay çizgi',
          'Yatay ışın', 'Dikdörtgen', 'Geri al']) {
        final f = find.byTooltip(ad);
        expect(f, findsOneWidget, reason: ad);
        final r = tester.getSize(f);
        expect(r.width, greaterThanOrEqualTo(SandikTouch.min), reason: ad);
        expect(r.height, greaterThanOrEqualTo(SandikTouch.min), reason: ad);
      }
      await bitir(tester);
    });

    testWidgets('trend çiz → sil → geri al, telefona yazılır', (tester) async {
      final s = await ac(tester);
      await tester.tap(find.byTooltip('Trend çizgisi'));
      await tester.pump();
      expect(s.arac, CizimTuru.trend);

      final r = grafikAlani(tester);
      await tester.dragFrom(
          r.topLeft + const Offset(200, 150), const Offset(180, -70));
      await tester.pump();
      expect(s.cizimler, hasLength(1));
      expect(s.cizimler.single.tur, CizimTuru.trend);
      // Çizimden sonra imlece dönülür, çizim seçili kalır.
      expect(s.arac, isNull);
      expect(s.secili, 0);

      await tester.pump(const Duration(milliseconds: 50));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(PrefKeys.grafikCizimleri), contains('THYAO.IS'));

      await tester.tap(find.byKey(const ValueKey('tamEkranCizimiSil')));
      await tester.pump();
      expect(s.cizimler, isEmpty);

      await tester.tap(find.byTooltip('Geri al'));
      await tester.pump();
      expect(s.cizimler, hasLength(1));
      await bitir(tester);
    });

    testWidgets('yatay çizgi tek dokunuşla çizilir ve taşınır',
        (tester) async {
      final s = await ac(tester);
      await tester.tap(find.byTooltip('Yatay çizgi'));
      await tester.pump();
      final r = grafikAlani(tester);
      await tester.tapAt(r.topLeft + const Offset(300, 120));
      await tester.pump();
      expect(s.cizimler, hasLength(1));
      final once = s.cizimler.single.a.p;

      // Gövdeden tutup aşağı sürükle: fiyat düşer.
      await tester.dragFrom(
          r.topLeft + const Offset(400, 120), const Offset(0, 60));
      await tester.pump();
      expect(s.cizimler.single.a.p, lessThan(once));
      await bitir(tester);
    });

    testWidgets('boş alanda sürüklemek kaydırır, çizim eklemez',
        (tester) async {
      final s = await ac(tester);
      final g0 = s.gorunum!;
      final r = grafikAlani(tester);
      await tester.dragFrom(
          r.topLeft + const Offset(300, 200), const Offset(120, 0));
      await tester.pump();
      expect(s.cizimler, isEmpty);
      expect(s.gorunum!.bas, lessThan(g0.bas));
      await bitir(tester);
    });

    testWidgets('kayıtlı çizimler açılışta okunur', (tester) async {
      final simdi = DateTime.now();
      final t = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 20))
          .millisecondsSinceEpoch;
      await CizimDeposu.instance.yaz('THYAO.IS',
          [GrafikCizimi(tur: CizimTuru.yatay, a: CizimNoktasi(t, 100))]);
      final s = await ac(tester);
      expect(s.cizimler, hasLength(1));
      await bitir(tester);
    });

    testWidgets('telefon dik dönünce sayfa kapanır', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => TamEkranGrafikEkrani.ac(context,
                  varlik: _thy(), ad: 'THYAO', canliBirim: 101),
              child: const Text('aç'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.byType(TamEkranGrafikEkrani), findsOneWidget);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(TamEkranGrafikEkrani), findsNothing);
      await bitir(tester);
    });
  });
}
