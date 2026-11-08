import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Takip listesi "Eklediğimden beri" (müşteri raporu 2026-11-08 #1).
///
/// Kilitler: yüzde eklenme günü kapanışından ölçülür, kapanış/tarih yoksa
/// "—" (uydurma sayı yok, önceki dönemin yüzdesi kalmaz), kapanış oturumda
/// bir kez çekilir, Türkçe ek okunuşa uyar, seçici ortak dönemi bozmaz,
/// satır cümlesi tam cümledir.
WatchlistItem _kalem(String id, String ticker,
        {DateTime? eklenme, double? fiyat, double? pct}) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ticker,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: eklenme,
      currentPrice: fiyat,
      periodChangePct: pct,
    );

void main() {
  group('eklenmedenBeriYuzde (saf)', () {
    test('(güncel − kapanış) / kapanış', () {
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: 100, guncelFiyat: 112.5),
          closeTo(12.5, 1e-9));
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: 50, guncelFiyat: 40),
          closeTo(-20, 1e-9));
    });

    test('ölçülmemiş uç → null (uydurma sayı yok)', () {
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: null, guncelFiyat: 10),
          isNull);
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: 10, guncelFiyat: null),
          isNull);
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: 0, guncelFiyat: 10), isNull);
      expect(eklenmedenBeriYuzde(eklenmeKapanisi: 10, guncelFiyat: -1),
          isNull);
      expect(
          eklenmedenBeriYuzde(eklenmeKapanisi: double.nan, guncelFiyat: 10),
          isNull);
    });
  });

  group('eklenmedenBeriUygula', () {
    final eylul = DateTime(2026, 9, 12, 14, 30);
    final ekim = DateTime(2026, 10, 1, 9);

    test('yüzdeyi yeniden yazar, eksikte null, sonra sıralar', () {
      final items = [
        _kalem('a', 'AAA', eklenme: eylul, fiyat: 110, pct: -3),
        _kalem('b', 'BBB', eklenme: ekim, fiyat: 90, pct: 5),
        _kalem('c', 'CCC', eklenme: null, fiyat: 10, pct: 7),
        _kalem('d', 'DDD', eklenme: ekim, fiyat: 10, pct: 9),
      ];
      final kapanislar = {
        EklenmeKapanisiOnbellegi.anahtar('AAA', eylul): 100.0,
        EklenmeKapanisiOnbellegi.anahtar('BBB', ekim): 100.0,
        EklenmeKapanisiOnbellegi.anahtar('DDD', ekim): null,
      };
      final sonuc = eklenmedenBeriUygula(items, kapanislar);
      final byId = {for (final w in sonuc) w.id: w.periodChangePct};
      expect(byId['a'], closeTo(10, 1e-9));
      expect(byId['b'], closeTo(-10, 1e-9));
      expect(byId['c'], isNull,
          reason: 'Eklenme tarihi yoksa önceki dönemin %7\'si kalmamalı.');
      expect(byId['d'], isNull, reason: 'Kapanış bulunamadı → "—".');
      expect(sonuc.map((w) => w.id).take(2), ['a', 'b']);
    });

    test('anahtar takvim günüdür: saat farkı aynı kapanışı bulur', () {
      expect(EklenmeKapanisiOnbellegi.anahtar('aaa', DateTime(2026, 9, 12, 1)),
          EklenmeKapanisiOnbellegi.anahtar('AAA', DateTime(2026, 9, 12, 23)));
    });
  });

  group('EklenmeKapanisiOnbellegi', () {
    test('bulunan kapanış oturumda bir kez çekilir; eşzamanlı istek tek',
        () async {
      final o = EklenmeKapanisiOnbellegi();
      var cagri = 0;
      DateTime? istenenGun;
      Future<double?> cek(String t, DateTime g) async {
        cagri++;
        istenenGun = g;
        return 42.0;
      }

      final gun = DateTime(2026, 9, 12, 15, 45);
      final ikisi = await Future.wait(
          [o.getir('AAA', gun, cek), o.getir('AAA', gun, cek)]);
      expect(ikisi, [42.0, 42.0]);
      expect(await o.getir('AAA', gun, cek), 42.0);
      expect(cagri, 1);
      expect(istenenGun, DateTime(2026, 9, 12),
          reason: 'Kapanış takvim gününden istenir.');
    });

    test('null önbelleğe girmez: sonraki kuruluşta yeniden denenir', () async {
      final o = EklenmeKapanisiOnbellegi();
      var cagri = 0;
      Future<double?> cek(String t, DateTime g) async {
        cagri++;
        return cagri == 1 ? null : 7.0;
      }

      final gun = DateTime(2026, 9, 12);
      expect(await o.getir('AAA', gun, cek), isNull);
      expect(await o.getir('AAA', gun, cek), 7.0);
      expect(await o.getir('AAA', gun, cek), 7.0);
      expect(cagri, 2);
    });
  });

  group('tarihtenBeriParcasi — ek okunuşa uyar', () {
    final bugun = DateTime(2026, 11, 8);
    String tr(int ay, {int yil = 2026, bool kisa = true}) =>
        tarihtenBeriParcasi(DateTime(yil, ay, 12), bugun: bugun, kisa: kisa);

    test('12 ayın ayrılma eki', () {
      expect([for (var a = 1; a <= 12; a++) tr(a)], [
        "12 Oca'tan", "12 Şub'tan", "12 Mar'tan", "12 Nis'dan", //
        "12 May'tan", "12 Haz'dan", "12 Tem'dan", "12 Ağu'tan", //
        "12 Eyl'den", "12 Eki'den", "12 Kas'dan", "12 Ara'tan",
      ]);
      expect(tr(9, kisa: false), "12 Eylül'den");
      expect(tr(3, kisa: false), "12 Mart'tan");
    });

    test('başka yıl: ek yılın okunuşundan', () {
      expect(tr(9, yil: 2025), "12 Eyl 2025'ten");
      expect(tr(9, yil: 2024), "12 Eyl 2024'ten");
      expect(tr(9, yil: 2027), "12 Eyl 2027'den");
      expect(tr(9, yil: 2030), "12 Eyl 2030'dan");
      expect(tr(9, yil: 2040), "12 Eyl 2040'tan");
      expect(tr(9, yil: 2000), "12 Eyl 2000'den");
    });

    test('İngilizce ek yok', () {
      expect(
          tarihtenBeriParcasi(DateTime(2026, 9, 12),
              dil: 'en_US', bugun: bugun),
          'Sep 12');
      expect(
          tarihtenBeriParcasi(DateTime(2025, 9, 12),
              dil: 'en_US', bugun: bugun, kisa: false),
          'September 12, 2025');
    });
  });

  group('seçici', () {
    testWidgets('DonemSecici sonEk: son segment, indeksi donemler.length',
        (tester) async {
      int? secilen;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: DonemSecici(
              donemler: SummaryPeriod.values,
              secili: 2,
              sonEk: 'Eklediğimden beri',
              onSec: (i) => secilen = i,
            ),
          ),
        ),
      ));
      expect(find.text('Eklediğimden beri'), findsOneWidget);
      await tester.tap(find.text('Eklediğimden beri'));
      expect(secilen, SummaryPeriod.values.length);
      // 44 pt dokunma hedefi (SandikSegment sözleşmesi).
      expect(tester.getSize(find.byType(DonemSecici)).height,
          greaterThanOrEqualTo(44));
    });
  });

  group('takip ekranı', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ProviderContainer> pump(WidgetTester tester,
        {required List<WatchlistItem> Function(bool beri) liste}) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: [
        watchlistProvider.overrideWith(() => _Liste(liste)),
        watchlistChartProvider.overrideWith((ref) async => const {}),
        activePartnersProvider.overrideWithValue(const []),
        watchlistLimitProvider.overrideWithValue(1 << 30),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('tr'),
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const Scaffold(body: WatchlistBody()),
        ),
      ));
      await tester.pump();
      // Yükleme → içerik geçişi (240 ms) bitsin: test oturumsuz, yani
      // yeniden yüklemede "eski veri soluk" yolu yok, iskelet geri gelir.
      await tester.pump(const Duration(milliseconds: 500));
      return c;
    }

    final eklenme = DateTime(DateTime.now().year, 9, 12, 10);

    testWidgets(
        'seçilince satır "12 Eyl\'den beri" yazar, cümle tam; ortak dönem '
        'değişmez; döneme dokununca kip kapanır', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pump(tester,
          liste: (beri) => [
                _kalem('1', 'SISE.IS',
                    eklenme: eklenme, fiyat: 40, pct: beri ? 12.5 : -2.93),
                _kalem('2', 'THYAO.IS',
                    eklenme: eklenme, fiyat: 300, pct: beri ? null : 1.0),
              ]);
      c.read(seciliDonemProvider.notifier).state = SummaryPeriod.birAy;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Eklediğimden beri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(c.read(watchlistEklenmedenBeriProvider), isTrue);
      expect(c.read(seciliDonemProvider), SummaryPeriod.birAy,
          reason: 'Ortak dönem (grafik, varlık sayfası) yerinde kalmalı.');
      expect(find.text("12 Eyl'den beri"), findsNWidgets(2));
      expect(find.text('+%12,50'), findsOneWidget);
      expect(find.text('—'), findsOneWidget,
          reason: 'Kapanış bulunamayan satır yüzde yerine "—" yazar.');

      final sise = tester
          .getSemantics(find.bySemanticsLabel(RegExp(r'^SISE\.IS, ')))
          .label;
      expect(sise, contains("12 Eylül'den beri %12,50 arttı"));
      final thy = tester
          .getSemantics(find.bySemanticsLabel(RegExp(r'^THYAO\.IS, ')))
          .label;
      expect(thy, contains('eklendiği günün kapanışı bulunamadı'));

      await tester.tap(find.text('1 hf'));
      await tester.pump();
      expect(c.read(watchlistEklenmedenBeriProvider), isFalse);
      expect(c.read(seciliDonemProvider), SummaryPeriod.birHafta);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text("12 Eyl'den beri"), findsNothing);
      semantics.dispose();
    });
  });
}

/// Kipe göre yüzde veren sabit liste: sağlayıcının yaptığını (kapanıştan
/// yüzde) [eklenmedenBeriUygula] testleri kilitler; burada ekran.
class _Liste extends WatchlistNotifier {
  _Liste(this.liste);
  final List<WatchlistItem> Function(bool beri) liste;

  @override
  Future<List<WatchlistItem>> build() async =>
      liste(ref.watch(watchlistEklenmedenBeriProvider));
}
