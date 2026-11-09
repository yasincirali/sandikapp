import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/tefas_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/fon_fiyat_gunu.dart';
import 'package:portfoy_takip/widgets/fon_fiyat_gunu_etiketi.dart';
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';

import 'helpers/kaynak.dart';

/// Fonun fiyat günü (müşteri raporu 30 Eki 21:15 #2, yasin "yap"): fiyat
/// bugünün değilse ekran hangi günün fiyatı olduğunu söyler; bugününse
/// ya da gün bilinmiyorsa hiçbir şey yazmaz.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // 2 Kasım 2026 Pazartesi, 10:00.
  final pazartesi = DateTime(2026, 11, 2, 10);

  group('fonFiyatGunFarki', () {
    test('bugünün fiyatı → null', () {
      expect(fonFiyatGunFarki(DateTime(2026, 11, 2), pazartesi), isNull);
    });
    test('gün bilinmiyor → null (uydurma tarih yok)', () {
      expect(fonFiyatGunFarki(null, pazartesi), isNull);
    });
    test('gelecek tarih (saat dilimi kayması) bugün sayılır', () {
      expect(fonFiyatGunFarki(DateTime(2026, 11, 3), pazartesi), isNull);
    });
    test('takvim günü sayılır, saat değil', () {
      // Dün 23:59 → 1 gün (10 saat önce olsa da).
      expect(fonFiyatGunFarki(DateTime(2026, 11, 1, 23, 59), pazartesi), 1);
      expect(fonFiyatGunFarki(DateTime(2026, 10, 30), pazartesi), 3);
    });
    test('yaz saati geçişi günü kaydırmaz', () {
      expect(
          fonFiyatGunFarki(DateTime(2026, 3, 28), DateTime(2026, 3, 30, 1)), 2);
    });
  });

  group('fonKoduAnahtardan', () {
    test('önekli ve öneksiz kod', () {
      expect(fonKoduAnahtardan('fon|TEFAS:AFT'), 'AFT');
      expect(fonKoduAnahtardan('fon|dly'), 'DLY');
    });
    test('sembol çekirdeği değilse null', () {
      expect(fonKoduAnahtardan('fon|name:Benim fonum'), isNull);
      expect(fonKoduAnahtardan('fon|sub:bankFund'), isNull);
    });
  });

  group('tefasTarihi', () {
    test('ISO ve epoch ms', () {
      expect(tefasTarihi('2026-10-30'), DateTime(2026, 10, 30));
      final ms = DateTime(2026, 10, 30).millisecondsSinceEpoch;
      expect(tefasTarihi('$ms'), DateTime(2026, 10, 30));
    });
    test('çözülemezse null', () {
      expect(tefasTarihi(''), isNull);
      expect(tefasTarihi('dün'), isNull);
    });
  });

  test('TefasService.fiyatTarihi kodu öneksiz ve büyük harfle arar', () {
    TefasService.instance.fiyatTarihiYaz('AFT', 1.5, DateTime(2026, 10, 30));
    expect(
        TefasService.instance.fiyatTarihi('tefas:aft'), DateTime(2026, 10, 30));
    expect(TefasService.instance.fiyatTarihi('YOK'), isNull);
  });

  Future<BuildContext> kur(WidgetTester tester,
      {Locale dil = const Locale('tr')}) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      locale: dil,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    return ctx;
  }

  testWidgets('uzun biçim: dün tarihle, iki gün ve üstü gün adıyla',
      (tester) async {
    final c = await kur(tester);
    expect(
        fonFiyatGunuUzun(c, DateTime(2026, 11, 2), simdi: pazartesi), isNull);
    expect(fonFiyatGunuUzun(c, DateTime(2026, 11, 1), simdi: pazartesi),
        'Fiyat 1 Kas');
    expect(fonFiyatGunuUzun(c, DateTime(2026, 10, 30), simdi: pazartesi),
        'Fiyat 30 Eki (Cuma)');
  });

  testWidgets('kısa biçim: dünkü / gün adı / tarih', (tester) async {
    final c = await kur(tester);
    expect(
        fonFiyatGunuKisa(c, DateTime(2026, 11, 2), simdi: pazartesi), isNull);
    expect(fonFiyatGunuKisa(c, DateTime(2026, 11, 1), simdi: pazartesi),
        'Dünkü fiyat');
    expect(fonFiyatGunuKisa(c, DateTime(2026, 10, 30), simdi: pazartesi),
        'Cuma fiyatı');
    expect(fonFiyatGunuKisa(c, DateTime(2026, 10, 23), simdi: pazartesi),
        '23 Eki fiyatı');
  });

  testWidgets('İngilizce', (tester) async {
    final c = await kur(tester, dil: const Locale('en'));
    expect(fonFiyatGunuUzun(c, DateTime(2026, 10, 30), simdi: pazartesi),
        'Price 30 Oct (Friday)');
    expect(fonFiyatGunuKisa(c, DateTime(2026, 11, 1), simdi: pazartesi),
        "Yesterday's price");
  });

  testWidgets('etiket: bugünün fiyatında yer kaplamaz, değilse okunur',
      (tester) async {
    await kur(tester);
    Future<void> bas(DateTime? t) => tester.pumpWidget(MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: FonFiyatGunuEtiketi(tarih: t, simdi: pazartesi)),
        ));
    await bas(DateTime(2026, 11, 2));
    expect(find.byKey(const ValueKey('fonFiyatGunu')), findsNothing);
    await bas(null);
    expect(find.byKey(const ValueKey('fonFiyatGunu')), findsNothing);
    await bas(DateTime(2026, 10, 30));
    expect(find.text('· Fiyat 30 Eki (Cuma)'), findsOneWidget);
    // Ekran okuyucu ayraç noktasını okumaz.
    expect(find.bySemanticsLabel('Fiyat 30 Eki (Cuma)'), findsOneWidget);
  });

  testWidgets('3.1× yazı, 320 pt: fiyat başlığı notla taşmaz', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(
            size: Size(320, 900), textScaler: TextScaler.linear(3.1)),
        child: Scaffold(
          body: Builder(
            builder: (context) => VarlikFiyatBlogu(
              etiket: 'GÜNCEL FİYAT',
              etiketYani: FonFiyatGunuEtiketi(
                  tarih: DateTime(2026, 10, 30), simdi: pazartesi),
              fiyat: '₺2,154318',
              fiyatRengi: context.c.gold,
              degisim: (metin: '+%0,42', renk: context.c.gain),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fonFiyatGunu')), findsOneWidget);
  });

  test('üç yüzey de aynı yardımcıdan okur (kendi tarih kuralı yok)', () {
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(detay, contains('FonFiyatGunuEtiketi(tarih: fonFiyatGunu('));
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    expect(sayfa, contains('FonFiyatGunuEtiketi('));
    final kart = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    expect(kart, contains('fonFiyatGunuKisa(context, fonFiyatGunu('));
    final portfoy = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect(portfoy, contains('fonFiyatGunuKisa(context, fonFiyatGunu('));
  });

  test('Yahoo toplu v7 isteği yok (her turda 401 dönüyordu)', () {
    final s = ekranKaynagiSync('lib/services/price_service.dart');
    expect(s.contains("'/v7/finance/quote'"), isFalse);
  });
}
