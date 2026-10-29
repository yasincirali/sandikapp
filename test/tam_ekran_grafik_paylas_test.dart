import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/magaza.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/tam_ekran/grafik_paylasimi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Tam ekran grafiği çizimleriyle paylaş (Ar-Ge 25 Eki §2, rapor 13:15 §1).
///
/// Kilitlenenler:
///  · Üst çubukta "Grafiği paylaş" düğmesi, ≥44 pt, etiketli.
///  · Paylaşılan metin: "THYAO · (dönem) · sandık ile çizildi" + mağaza
///    bağlantısı; tavsiye dili (sinyal/hedef/al/sat) yok.
///  · Görsel paylaşım kipinde üretilir: imleç/seçim/sil düğmesi yok; altta
///    marka şeridi (logo + "sandık" + sembol · dönem · zaman + okunur kısa
///    bağlantı, yasin 2026-10-29) grafiğin DIŞINDA; kip paylaşım
///    sayfasından önce kapanır.
///  · Kişisel katman yok: ekran maliyet, lot, alarm, tutar verisine hiç
///    erişmez — eklenirse bu test kırılır ve paylaşım kipinde gizlenmesi
///    istenir. Tek bilinçli istisna (0170, 2026-10-29): seçili çizimin
///    "Alarm kur" düğmesi ([CizimAlarmDugmesi]) ve çizim değişince alarmı
///    eşitleyen çağrı. Düğme yalnız seçim çubuğunda yaşar, seçim çubuğu
///    paylaşım kipinde çizilmez; grafiğe alarm çizgisi/sayısı çizilmez.
///    Bu adlar taramadan önce çıkarılır, kapı ayrıca kilitlenir.
///  · Hata dost metinle gösterilir, ölçüm yalnız başarıda.
const _gun = 86400000;

List<OhlcBar> _barlar(int n, int bas) => [
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

Asset _thy() => Asset(
      id: 'thy-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 37,
      purchasePrice: 88.5,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 101,
      addedDate: DateTime(2025, 3, 14),
    );

final _tavsiye = RegExp(
    r'\b(sinyal|hedef|al|sat|öneri|signal|target|buy|sell|advice)\b',
    caseSensitive: false);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('metin', () {
    for (final (ad, AppLocalizations l) in [
      ('tr', AppLocalizationsTr()),
      ('en', AppLocalizationsEn()),
    ]) {
      test('$ad: sembol · dönem · imza + mağaza bağlantısı, tavsiye yok', () {
        final m = grafikPaylasimMetni(l, ad: 'THYAO', donem: l.period6M);
        final satirlar = m.split('\n');
        expect(satirlar.first, startsWith('THYAO · ${l.period6M} · '));
        expect(satirlar.first, contains('sandık'));
        expect(satirlar.last, startsWith(Magaza.indirKapisi));
        expect(satirlar.last, contains('utm_source=grafik_paylas'));
        expect(_tavsiye.hasMatch(satirlar.first), isFalse, reason: m);
        expect(_tavsiye.hasMatch(l.tegPaylasimZamani('1 Eki 2026 10:00')),
            isFalse);
        expect(_tavsiye.hasMatch(l.tegPaylas), isFalse);
      });
    }

    test('TR metni karardaki gibi', () {
      expect(AppLocalizationsTr().tegPaylasimMetni('THYAO', '6A'),
          'THYAO · 6A · sandık ile çizildi');
      expect(AppLocalizationsTr().tegPaylas, 'Grafiği paylaş');
    });

    test('görseldeki kısa bağlantı: indirme kapısı, şemasız, UTM yok', () {
      final k = grafikPaylasimKisaBaglanti();
      expect(k, 'yasincirali.github.io/sandikapp/indir');
      expect(Magaza.indirKapisi, contains(k));
      expect(k, isNot(contains('utm_')));
      expect(k, isNot(startsWith('http')));
    });

    test('dönem: görünen pencerenin en yakın uygulama dönemi', () {
      int g(num n) => (n * _gun).round();
      expect(gorunurDonemKimligi(0, g(1)), 'GÜNLÜK');
      expect(gorunurDonemKimligi(0, g(8)), '1H');
      expect(gorunurDonemKimligi(0, g(28)), '1A');
      expect(gorunurDonemKimligi(0, g(100)), '3A');
      expect(gorunurDonemKimligi(0, g(180)), '6A');
      expect(gorunurDonemKimligi(0, g(400)), '1Y');
      expect(gorunurDonemKimligi(0, g(3000)), '5Y');
    });
  });

  // Uçtan uca test 2026-10-29: metin günlük mumlarda "3 ay" diyordu
  // (yuvarlanmış dönem, aralık yok); dosya her paylaşımda "sandik-ozet.png".
  group('paylaşım dönemi ve dosya adı', () {
    int t(int y, int a, int g, [int s = 0, int d = 0]) =>
        DateTime(y, a, g, s, d).millisecondsSinceEpoch;

    test('günlük: gerçek tarih aralığı, yuvarlanmaz', () {
      expect(gorunurTarihAraligi(t(2026, 8, 22), t(2026, 10, 29), 'tr',
              gunIci: false),
          '22 Ağu \u2013 29 Eki 2026');
      expect(gorunurTarihAraligi(t(2025, 11, 3), t(2026, 2, 6), 'en',
              gunIci: false),
          '3 Nov 2025 \u2013 6 Feb 2026');
    });

    test('gün içi: saatle; aynı gün tek tarih', () {
      expect(gorunurTarihAraligi(t(2026, 10, 29, 10, 0),
              t(2026, 10, 29, 17, 30), 'tr', gunIci: true),
          '29 Eki 2026 10:00\u201317:30');
      expect(gorunurTarihAraligi(t(2026, 10, 27, 10, 0),
              t(2026, 10, 29, 17, 30), 'tr', gunIci: true),
          '27 Eki 10:00 \u2013 29 Eki 17:30');
    });

    test('dönem metni mum aralığını söyler (TR/EN)', () {
      final tr = grafikPaylasimDonemi(AppLocalizationsTr(),
          aralikAdi: 'günlük',
          basMs: t(2026, 8, 22),
          sonMs: t(2026, 10, 29),
          dil: 'tr',
          gunIci: false);
      expect(tr, 'günlük mumlar, 22 Ağu \u2013 29 Eki 2026');
      final en = grafikPaylasimDonemi(AppLocalizationsEn(),
          aralikAdi: 'daily',
          basMs: t(2026, 8, 22),
          sonMs: t(2026, 10, 29),
          dil: 'en',
          gunIci: false);
      expect(en, startsWith('daily candles, '));
      expect(_tavsiye.hasMatch(tr), isFalse);
    });

    test('dosya adı sembolden, ASCII', () {
      expect(grafikPaylasimDosyaAdi('THYAO'), 'sandik-thyao-grafik.png');
      expect(grafikPaylasimDosyaAdi('Gram Altın'),
          'sandik-gram-altin-grafik.png');
      expect(grafikPaylasimDosyaAdi('İŞ BANKASI (C)'),
          'sandik-is-bankasi-c-grafik.png');
      expect(grafikPaylasimDosyaAdi('—'), 'sandik-grafik.png');
    });

    test('ekran dosya adını ve dönemi geçirir', () {
      final k = ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart');
      expect(k, contains('dosyaAdi: grafikPaylasimDosyaAdi(widget.ad)'));
      expect(k, contains('grafikPaylasimDonemi('));
    });
  });

  group('kişisel katman yok', () {
    test('ekran kişisel veriye erişmez (maliyet, lot, alarm, tutar)', () {
      final satirlar =
          ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart')
              .split('\n')
              .where((s) => !s.trimLeft().startsWith('//'))
              .join('\n')
              // İzinli (0170): seçim çubuğundaki zil ve eşitleme çağrısı;
              // ikisi de alarm VERİSİNİ grafiğe çizmez (aşağıdaki kapı testi).
              .replaceAll('CizimAlarmDugmesi', '')
              .replaceAll('cizimAlarmlariniEsitle', '')
              .replaceAll('cizim_alarm_dugmesi', '');
      for (final yasak in [
        'purchasePrice',
        '.quantity',
        'aktifLotlar',
        'portfolioProvider',
        'positions',
        'maliyet',
        'Maliyet',
        'alarm',
        'Alarm',
        'fmtTRY',
        'avgCost',
      ]) {
        expect(satirlar.contains(yasak), isFalse,
            reason: '"$yasak" tam ekran grafikte: kişisel katman paylaşım '
                'görseline sızabilir. Katmanı `paylasim` kipinde çizme '
                've bu testi bilinçli güncelle.');
      }
    });

    test('boyacı paylaşım kipini ekrandan alır, imleç/seçim kapıda', () {
      final k = ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart');
      expect(k, contains('paylasim: _paylasimKipi'));
      expect(k, contains('final im = paylasim ? null : imlec;'));
      expect(k, contains('final b = paylasim ? null : bekleyen;'));
      expect(k, contains('!paylasim && k == secili'));
    });

    test('alarm düğmesi yalnız seçim çubuğunda, o da paylaşımda yok (0170)',
        () {
      final k = ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart');
      expect(k, contains('if (secili != null && !_paylasimKipi) _seciliCubugu('));
      expect('CizimAlarmDugmesi('.allMatches(k).length, 1);
      final cubuk = k.substring(k.indexOf('Widget _seciliCubugu('));
      expect(cubuk, contains('CizimAlarmDugmesi('));
    });
  });

  group('ekran', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MumVerisi.instance.onbellegiTemizle();
      final simdi = DateTime.now();
      final bas = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 199))
          .millisecondsSinceEpoch;
      MumVerisi.testCekici = (a, ar, b, s) async => _barlar(200, bas);
    });
    tearDown(() {
      MumVerisi.testCekici = null;
      TamEkranGrafikEkraniState.paylasimTesti = null;
    });

    Future<TamEkranGrafikEkraniState> ac(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TamEkranGrafikEkrani(
              varlik: _thy(), ad: 'THYAO', canliBirim: 101),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return tester
          .state<TamEkranGrafikEkraniState>(find.byType(TamEkranGrafikEkrani));
    }

    Future<void> bitir(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 5));

    testWidgets('düğme üst çubukta, 44 pt, etiketli', (tester) async {
      final anlam = tester.ensureSemantics();
      await ac(tester);
      final f = find.byTooltip('Grafiği paylaş');
      expect(f, findsOneWidget);
      final r = tester.getSize(f);
      expect(r.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(r.height, greaterThanOrEqualTo(SandikTouch.min));
      final dugum =
          tester.getSemantics(find.byKey(const ValueKey('tamEkranPaylas')));
      expect(dugum.label, 'Grafiği paylaş');
      expect(dugum.tooltip, isEmpty, reason: 'etiket iki kez okunmasın');
      expect(dugum.flagsCollection.isButton, isTrue);
      anlam.dispose();
      await bitir(tester);
    });

    testWidgets('görsel paylaşım kipinde: imza var, seçim/sil yok; metin',
        (tester) async {
      final s = await ac(tester);
      // Bir çizim yap: seçili kalır, sil düğmesi ekranda.
      await tester.tap(find.byTooltip('Trend çizgisi'));
      await tester.pump();
      final alan = tester.getRect(find.byWidgetPredicate((w) =>
          w is Listener &&
          w.onPointerSignal != null &&
          w.onPointerDown != null));
      await tester.dragFrom(
          alan.topLeft + const Offset(200, 150), const Offset(180, -70));
      await tester.pump();
      expect(s.secili, 0);
      expect(find.byKey(const ValueKey('tamEkranCizimiSil')), findsOneWidget);
      expect(find.byKey(const ValueKey('tamEkranImza')), findsNothing);

      String? giden;
      var kipteydi = false;
      TamEkranGrafikEkraniState.paylasimTesti = (sinir, metin, kaynak) async {
        giden = metin;
        kipteydi = s.paylasimKipi;
        // Görselin sınırı içinde imza ve başlık var; seçim düğmesi yok.
        expect(
            find.descendant(
                of: find.byKey(sinir),
                matching: find.byKey(const ValueKey('tamEkranImza'))),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(sinir),
                matching: find.textContaining('sandık ile çizildi')),
            findsOneWidget);
        expect(find.textContaining('itibarıyla'), findsOneWidget);
        expect(find.byKey(const ValueKey('tamEkranCizimiSil')), findsNothing);
        // Marka şeridi: logo, "sandık" ve görselde okunan bağlantı.
        final serit = find.byKey(const ValueKey('tamEkranImza'));
        expect(find.descendant(of: serit, matching: find.byType(SandikLogo)),
            findsOneWidget);
        expect(find.descendant(of: serit, matching: find.text('sandık')),
            findsOneWidget);
        final baglanti = find.descendant(
            of: find.byKey(sinir),
            matching: find.byKey(const ValueKey('tamEkranBaglanti')));
        expect(baglanti, findsOneWidget);
        expect(tester.widget<Text>(baglanti).data,
            grafikPaylasimKisaBaglanti());
        // Şerit çizim alanının ALTINDA: eksen ve mumların üstüne binmez.
        final alan = tester.getRect(find.byWidgetPredicate((w) =>
            w is Listener &&
            w.onPointerSignal != null &&
            w.onPointerDown != null));
        final seritKutusu = tester.getRect(serit);
        expect(seritKutusu.top, greaterThanOrEqualTo(alan.bottom - 0.5));
        expect(seritKutusu.height, greaterThanOrEqualTo(36));
        expect(
            tester.getRect(find.byKey(sinir)).contains(seritKutusu.center),
            isTrue);
      };

      await tester.tap(find.byTooltip('Grafiği paylaş'));
      await tester.pump();
      await tester.pump();

      expect(kipteydi, isTrue);
      expect(giden, isNotNull);
      final ilk = giden!.split('\n').first;
      expect(ilk, startsWith('THYAO · '));
      expect(ilk, endsWith(' · sandık ile çizildi'));
      // Mum aralığı adıyla; yuvarlanmış "N ay" yok.
      expect(ilk, contains('günlük mumlar, '));
      expect(ilk, isNot(matches(RegExp(r'· \d+ ay ·'))));
      expect(giden, contains(Magaza.indirKapisi));
      expect(_tavsiye.hasMatch(ilk), isFalse);
      // Tutar/miktar/maliyet metne girmez.
      expect(giden, isNot(contains('88')));
      expect(giden, isNot(contains('37')));
      // Kip kapandı, ekran eski hâline döndü; ölçüm sayıldı.
      expect(s.paylasimKipi, isFalse);
      expect(find.byKey(const ValueKey('tamEkranImza')), findsNothing);
      expect(find.byKey(const ValueKey('tamEkranCizimiSil')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('${PrefKeys.ozellikOlcumuPrefix}grafik_paylas'),
          isNotNull);
      await bitir(tester);
    });

    testWidgets('hata dost metinle gösterilir, kip kapanır', (tester) async {
      final s = await ac(tester);
      TamEkranGrafikEkraniState.paylasimTesti =
          (sinir, metin, kaynak) async => throw StateError('PNG üretilemedi');
      await tester.tap(find.byTooltip('Grafiği paylaş'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(s.paylasimKipi, isFalse);
      expect(find.text('Hata'), findsOneWidget);
      expect(find.textContaining('StateError'), findsNothing);
      await bitir(tester);
    });
  });
}
