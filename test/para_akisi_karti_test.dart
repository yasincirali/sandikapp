import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/fon_akisi_provider.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

import 'helpers/kaynak.dart';

/// Para akışı kartı (Balina B1). Özet ve bayrak provider override'larıyla
/// verilir — testte ağ yok.
///
/// ## Kilitlenen davranışlar
/// 1. Bayrak kapalıyken hiçbir şey çizilmez VE veri sorgusu hiç başlamaz.
/// 2. Veri yoksa / fon değilse kart yer kaplamaz (boşluk dahil).
/// 3. Yön dili: giriş "+" ve "net giriş", çıkış "−" ve "net çıkış".
/// 4. Bilinmeyen yatırımcı sayısı satırı çizilmez (uydurma yok).
/// 5. Kart "balina" demez, "kimin aldığı bilinemez" der.
/// 6. Dar ekranda ve büyük yazıda taşma yok.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

FonAkisOzeti _ozet({
  double net = 412e6,
  int? yatirimci = 48210,
  int? yatirimciDegisimi = 38,
  List<FonBalinaOlayi> olaylar = const [],
}) =>
    FonAkisOzeti(
      haftalar: [
        for (var i = 7; i >= 1; i--)
          HaftaAkisi(
              baslangic: DateTime.utc(2026, 9, 28 - 7 * i),
              net: i == 4 ? null : (i.isEven ? 120e6 : -80e6)),
        HaftaAkisi(baslangic: _g(9, 28), net: net),
      ],
      sonHaftaNet: net,
      sonHaftaIlkGun: _g(9, 28),
      veriTarihi: _g(10, 2),
      buyukluk: 13.4e9,
      yatirimci: yatirimci,
      yatirimciDegisimi: yatirimciDegisimi,
      olaylar: olaylar,
    );

int _sorguSayisi = 0;

Future<void> _kur(
  WidgetTester t, {
  Widget kart = const ParaAkisiKarti(tur: AssetType.fon, ticker: 'TEFAS:TTE'),
  bool acik = true,
  FonAkisOzeti? ozet,
  bool veriYok = false,
  double genislik = 390,
  double olcek = 1,
}) async {
  _sorguSayisi = 0;
  t.view.physicalSize = Size(genislik, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      balinaRadariAcikProvider.overrideWithValue(acik),
      fonAkisiProvider.overrideWith((ref, kod) async {
        _sorguSayisi++;
        return veriYok ? null : (ozet ?? _ozet());
      }),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(genislik, 1600), textScaler: TextScaler.linear(olcek)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
            child: kart,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('giriş: başlık, tutar, aralık, büyüklük ve yatırımcı', (t) async {
    await _kur(t);
    expect(find.byType(SandikCard), findsOneWidget);
    expect(find.text('PARA AKIŞI'), findsOneWidget);
    expect(find.text('Son hafta net giriş'), findsOneWidget);
    expect(find.text('+₺412,00M'), findsOneWidget);
    expect(find.text('28 Eyl - 2 Eki'), findsOneWidget);
    expect(find.text('Fon büyüklüğü'), findsOneWidget);
    expect(find.text('₺13,40Mr'), findsOneWidget);
    expect(find.text('Yatırımcı sayısı'), findsOneWidget);
    expect(find.text('48.210 (+38)'), findsOneWidget);
    expect(find.textContaining('fiyat değişimi dahil değildir'),
        findsOneWidget);
  });

  testWidgets('çıkış: eksi işaret (U+2212) ve "net çıkış"', (t) async {
    await _kur(t, ozet: _ozet(net: -10.85e6, yatirimciDegisimi: -5));
    expect(find.text('Son hafta net çıkış'), findsOneWidget);
    expect(find.text('−₺10,85M'), findsOneWidget);
    expect(find.text('Son hafta net giriş'), findsNothing);
    expect(find.text('48.210 (−5)'), findsOneWidget);
  });

  testWidgets('yatırımcı sayısı bilinmiyorsa satır çizilmez', (t) async {
    await _kur(t, ozet: _ozet(yatirimci: null, yatirimciDegisimi: null));
    expect(find.text('Yatırımcı sayısı'), findsNothing);
    expect(find.text('Fon büyüklüğü'), findsOneWidget);
  });

  testWidgets('yatırımcı farkı bilinmiyorsa yalnız sayı yazılır', (t) async {
    await _kur(t, ozet: _ozet(yatirimciDegisimi: null));
    expect(find.text('48.210'), findsOneWidget);
  });

  testWidgets('olay yoksa bunu söyler', (t) async {
    await _kur(t);
    expect(find.text('Büyük hareketler · son 30 gün'), findsOneWidget);
    expect(
        find.text(
            'Son 30 günde olağandışı büyüklükte bir giriş ya da çıkış yok.'),
        findsOneWidget);
  });

  testWidgets('olay varsa kanıtıyla listeler', (t) async {
    await _kur(
      t,
      ozet: _ozet(olaylar: [
        FonBalinaOlayi(
            tarih: _g(9, 29),
            tutar: 398e6,
            buyuklukOrani: 0.031,
            sapmaKati: 4.2,
            yatirimciDegisimi: 12),
        FonBalinaOlayi(
            tarih: _g(9, 16),
            tutar: -151e6,
            buyuklukOrani: 0.022,
            sapmaKati: 3.4),
      ]),
    );
    expect(find.text('Büyük giriş · 29 Eyl'), findsOneWidget);
    expect(
        find.text('+₺398,00M · fon büyüklüğüne oranı %3,1 · '
            'olağan günlük hareketin 4,2 katı'),
        findsOneWidget);
    expect(find.text('Aynı gün yatırımcı sayısı +12'), findsOneWidget);
    expect(find.text('Büyük çıkış · 16 Eyl'), findsOneWidget);
    // İkinci olayın yatırımcı farkı bilinmiyor: tek satır.
    expect(find.textContaining('Aynı gün yatırımcı sayısı'), findsOneWidget);
    expect(find.textContaining('olağandışı büyüklükte'), findsNothing);
  });

  testWidgets('dipnot: kaynak, veri tarihi ve "kimin aldığı bilinemez"',
      (t) async {
    await _kur(t);
    expect(find.textContaining('Kaynak: TEFAS · veri tarihi 2 Eki'),
        findsOneWidget);
    expect(find.textContaining('Kimin alıp sattığı bu veriden bilinemez'),
        findsOneWidget);
    expect(find.textContaining('yatırım tavsiyesi değildir'), findsOneWidget);
  });

  testWidgets('bayrak kapalıyken çizilmez ve sorgu BAŞLAMAZ', (t) async {
    await _kur(t, acik: false);
    expect(find.byType(SandikCard), findsNothing);
    expect(find.text('PARA AKIŞI'), findsNothing);
    expect(_sorguSayisi, 0);
  });

  testWidgets('veri yoksa hiç yer kaplamaz', (t) async {
    await _kur(t, veriYok: true);
    expect(find.byType(SandikCard), findsNothing);
    expect(t.getSize(find.byType(ParaAkisiKarti)).height, 0);
  });

  testWidgets('varlık fon değilse çizilmez ve sorgu başlamaz', (t) async {
    await _kur(t,
        kart: const ParaAkisiKarti(tur: AssetType.hisse, ticker: 'THYAO'));
    expect(find.byType(SandikCard), findsNothing);
    expect(_sorguSayisi, 0);
  });

  testWidgets('BES fonu da kartı alır', (t) async {
    await _kur(t,
        kart: const ParaAkisiKarti(tur: AssetType.bes, ticker: 'TEFAS:AH5'));
    expect(find.text('PARA AKIŞI'), findsOneWidget);
  });

  testWidgets('dar ekran (320) ve büyük yazı (1,5×) taşmaz', (t) async {
    await _kur(
      t,
      genislik: 320,
      olcek: 1.5,
      ozet: _ozet(olaylar: [
        FonBalinaOlayi(
            tarih: _g(9, 29),
            tutar: 398e6,
            buyuklukOrani: 0.031,
            sapmaKati: 4.2,
            yatirimciDegisimi: 12),
      ]),
    );
    expect(t.takeException(), isNull);
    expect(find.text('+₺412,00M'), findsOneWidget);
  });

  testWidgets('İngilizce: metinler çevrili', (t) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        balinaRadariAcikProvider.overrideWithValue(true),
        fonAkisiProvider.overrideWith((ref, kod) async => _ozet()),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: ParaAkisiKarti(tur: AssetType.fon, ticker: 'TTE'),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('MONEY FLOW'), findsOneWidget);
    expect(find.text('Net inflow, latest week'), findsOneWidget);
    expect(find.textContaining('cannot show who bought or sold'),
        findsOneWidget);
  });

  group('değişmezler (kaynak taraması)', () {
    test('bayrak varsayılanı KAPALI', () {
      // Veri sunucuda birikmeden kart açılmamalı; açılış Console'dan.
      final kaynak =
          ekranKaynagiSync('lib/services/remote_config_service.dart');
      expect(kaynak, contains("'balina_radari_acik': false"));
      expect(RemoteConfigService.instance.balinaRadariAcik, isFalse);
    });

    test('kart metinleri "balina" demez', () {
      // TEFAS kimin alıp sattığını vermiyor; etiket kanıtla sınırlı kalır.
      for (final arb in ['lib/l10n/app_tr.arb', 'lib/l10n/app_en.arb']) {
        final flow = RegExp(r'"flow\w+": "([^"]*)"')
            .allMatches(ekranKaynagiSync(arb))
            .map((m) => m[1]!.toLowerCase());
        expect(flow, isNotEmpty);
        expect(flow.where((m) => m.contains('balina') || m.contains('whale')),
            isEmpty,
            reason: arb);
      }
    });

    test('kart iki fon yüzeyinde de bağlı: varlık detayı ve varlık sayfası',
        () {
      expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
          contains('ParaAkisiKarti('));
      expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
          contains('ParaAkisiKarti('));
    });

    test('kural istemcide yeniden yazılmaz: eşik sabitleri yalnız sunucuda',
        () {
      // Kart, liste ve bildirim aynı `balina_olay` satırını okur. İstemcide
      // ikinci bir eşik, iki yüzeyin farklı gün göstermesi demek olurdu.
      final istemci = ekranKaynagiSync('lib/services/fon_akisi.dart') +
          ekranKaynagiSync('lib/widgets/para_akisi_karti.dart');
      expect(istemci, isNot(contains('stddev')));
      expect(istemci, isNot(contains('ASGARI_BUYUKLUK')));
      final sunucu =
          ekranKaynagiSync('supabase/functions/_shared/balina.ts');
      expect(sunucu, contains('export const SAPMA_KATI = 3;'));
      expect(sunucu, contains('export const BUYUKLUK_ORANI = 0.02;'));
      expect(sunucu, contains('export const ASGARI_BUYUKLUK = 50_000_000;'));
    });

    test('sunucu: cron kapısı fail-closed, yanıt ayrıntı sızdırmaz', () {
      final fn =
          ekranKaynagiSync('supabase/functions/akis-gozlem/index.ts');
      expect(fn, contains('cronSecretZorunlu('));
      expect(fn, contains('cronYetkisiVarMi('));
      expect(fn, isNot(contains('err.message')));
      expect(fn, isNot(contains('String(err)')));
    });

    test('migration: RLS + GRANT + doğrulama, istemci yazamaz', () {
      final sql =
          ekranKaynagiSync('supabase/migrations/0103_fon_akisi.sql');
      for (final tablo in ['fon_akis_gunluk', 'balina_olay', 'fon_akis_tur']) {
        expect(sql,
            contains('alter table public.$tablo enable row level security'));
        expect(sql,
            contains('alter table public.$tablo force row level security'));
      }
      expect(sql, contains('grant select on table public.fon_akis_gunluk to authenticated'));
      expect(sql, isNot(contains(RegExp(r'grant[^;]*(insert|update|delete)[^;]*to authenticated', caseSensitive: false))));
      expect(sql, isNot(contains(RegExp(r'to anon\b'))));
      // SECURITY DEFINER olan her fonksiyon search_path taşır.
      final definer = RegExp(r'security definer\s+set search_path')
          .allMatches(sql)
          .length;
      expect(definer, RegExp(r'security definer').allMatches(sql).length);
      expect(sql, contains("raise exception '0103:"));
    });
  });
}
