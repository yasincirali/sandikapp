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
///    istenir.
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

  group('kişisel katman yok', () {
    test('ekran kişisel veriye erişmez (maliyet, lot, alarm, tutar)', () {
      final satirlar =
          ekranKaynagiSync('lib/screens/tam_ekran_grafik_screen.dart')
              .split('\n')
              .where((s) => !s.trimLeft().startsWith('//'))
              .join('\n');
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
