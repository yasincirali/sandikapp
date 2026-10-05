import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/hafta_ozeti_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show initPreferencesCache;
import 'package:portfoy_takip/screens/hafta_ozeti_screen.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// "Haftanın özeti" ekranı (Balina B4). Liste provider override'ıyla verilir.
///
/// ## Kilitlenen davranışlar (tek liste S6-B + notlar S16-B, 2026-10-05)
/// 1. Başlık olağandışı hareketi sayar; satır: kod, ad (kesilmeden), rozet,
///    sayı cümlesi.
/// 2. Tek liste, önem sırası: olağandışı → hareketli → sakin; sakinler
///    tercihle gizlenebilir.
/// 3. Not başlığı ilgili satırda; aylık rapor varsa en üstte tek satır.
/// 4. Liste boşsa açıklayıcı boş durum; hata/uydurma satır yok.
/// 5. Ekran portföy yüzdesi hesaplamaz (tek kaynağı Özet).
/// 6. Bildirim yalnız `akis: '1'` VE bayrak açıkken bu ekrana gider.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

Position _poz(String kod, String ad) => aggregatePositions([
      Asset(
        id: kod,
        userId: 'u1',
        name: ad,
        ticker: 'TEFAS:$kod',
        type: AssetType.fon,
        quantity: 100,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 1,
        addedDate: DateTime(2026, 3, 14),
      ),
    ]).single;

FonAkisOzeti _ozet(double net,
        {double buyukluk = 1e9, List<FonBalinaOlayi> olaylar = const []}) =>
    FonAkisOzeti(
      haftalar: [
        for (var i = 7; i >= 1; i--)
          HaftaAkisi(baslangic: DateTime.utc(2026, 9, 28 - 7 * i), net: 1e6),
        HaftaAkisi(baslangic: _g(9, 28), net: net),
      ],
      sonHaftaNet: net,
      sonHaftaIlkGun: _g(9, 28),
      veriTarihi: _g(10, 2),
      buyukluk: buyukluk,
      yatirimci: null,
      yatirimciDegisimi: null,
      olaylar: olaylar,
      // Hafta başı büyüklüğü = en yeni büyüklük (oranlar tam okunsun).
      sonHaftaBasBuyukluk: buyukluk,
    );

Position _hisse(String sembol, String ad, AssetType tur) => aggregatePositions([
      Asset(
        id: sembol,
        userId: 'u1',
        name: ad,
        ticker: sembol,
        type: tur,
        quantity: 1,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 1,
        addedDate: DateTime(2026, 3, 14),
      ),
    ]).single;

HaftaSatiri _fon(String kod, double net,
        {String? ad,
        double buyukluk = 1e9,
        List<FonBalinaOlayi> olaylar = const []}) =>
    fonSatiri(_poz(kod, ad ?? '$kod Fonu'), kod,
        _ozet(net, buyukluk: buyukluk, olaylar: olaylar));

FonBalinaOlayi _olay(int ay, int gun, double tutar) => FonBalinaOlayi(
    tarih: _g(ay, gun), tutar: tutar, buyuklukOrani: 0.05, sapmaKati: 5);

/// [pay7] verilmezse haftanın payı son günle aynı.
HacimOzeti _hacimOzeti(
        {double? kat,
        double? pay,
        double? pay7,
        List<HacimOlayi> olaylar = const []}) =>
    HacimOzeti(
      gunler: const [],
      sonGun: HacimGunu(
          tarih: _g(10, 2), kapanis: 1, paraHacmi: 1e9, aliciPayi: pay),
      ortalama: kat == null ? null : 1e9 / kat,
      kat: kat,
      fiyatDegisim: 0.012,
      olaylar: olaylar,
      aliciPayi: pay,
      aliciPayi7: pay7 ?? pay,
    );

HacimOlayi _hacimOlayi() => HacimOlayi(
    tarih: _g(10, 1),
    yukselis: true,
    paraHacmi: 35.46e9,
    ortalamaKati: 4.7,
    fiyatDegisim: 0.0997);

Future<void> _kur(WidgetTester t, List<HaftaSatiri> liste,
    {double genislik = 390,
    double olcek = 1,
    bool sakinGoster = true,
    Map<String, AnalizOzeti> notlar = const {},
    Map<String, AnalizOzeti> aylik = const {}}) async {
  SharedPreferences.setMockInitialValues(
      {if (!sakinGoster) PrefKeys.haftaSakinGoster: false});
  await initPreferencesCache();
  t.view.physicalSize = Size(genislik, 2000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      haftaOzetiProvider.overrideWith((ref) async => haftaSirasi(liste)),
      notOzetleriProvider
          .overrideWith((ref, a) async => a.$2 == 'aylik' ? aylik : notlar),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(olcek)),
        child: child!,
      ),
      home: const HaftaOzetiScreen(),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('başlık sayar; fon satırı: kod, ad, rozet, net ve oran',
      (t) async {
    await _kur(t, [
      _fon('TTE', -26.34e6, ad: 'İş Portföy BIST Teknoloji Fonu'),
      _fon('AFT', 412e6, olaylar: [_olay(9, 29, 400e6)]),
    ]);
    expect(find.text('Haftanın özeti'), findsOneWidget);
    expect(find.text('Son haftada 1 varlığında olağandışı hareket var.'),
        findsOneWidget);
    expect(find.text('İş Portföy BIST Teknoloji Fonu'), findsOneWidget);
    expect(find.text('Büyük giriş'), findsOneWidget);
    expect(find.text('Net +₺412,00M · büyüklüğün %41,2'), findsOneWidget);
    expect(find.text('Net −₺26,34M · büyüklüğün %2,6'), findsOneWidget);
    expect(find.textContaining('TEFAS · hacim Yahoo Finance'), findsOneWidget);
  });

  testWidgets('tek liste, önem sırası: olağandışı → hareketli → sakin',
      (t) async {
    await _kur(t, [
      _fon('SAKIN', 1e6),
      fonSatiri(_poz('HRK', 'Hareketli Fon'), 'HRK', _ozet(2e6)),
      hacimSatiri(_hisse('THYAO.IS', 'Türk Hava Yolları', AssetType.hisse),
          'THYAO.IS', _hacimOzeti(kat: 1.4, olaylar: [_hacimOlayi()]),
          kripto: false),
      // Son gün alıcı ağır, hafta satıcı ağır: haftalık listede rozet
      // haftayı anlatır.
      hacimSatiri(_hisse('KRIPTO:BTC', 'Bitcoin', AssetType.kripto),
          'KRIPTO:BTC', _hacimOzeti(pay: 0.56, pay7: 0.44),
          kripto: true),
    ]);
    double y(String metin) => t.getTopLeft(find.text(metin)).dy;
    // Satır, ekrandaki kısa adı yazar (`displayTicker`).
    expect(y('THYAO'), lessThan(y('BTC')));
    expect(y('BTC'), lessThan(y('HRK')));
    expect(y('HRK'), lessThan(y('SAKIN')));
    expect(find.text('Olağandışı hacim'), findsOneWidget);
    expect(find.text('Satıcı istekli'), findsOneWidget);
    expect(find.text('Hareketli'), findsOneWidget);
    expect(find.text('Sakin'), findsOneWidget);
    expect(find.text('1 Eki · hacim 4,7 kat · fiyat +%10,0'), findsOneWidget);
    expect(
        find.text('7 günde alıcı payı %44,0 · son gün %56,0'), findsOneWidget);
    expect(find.text('Son haftada 2 varlığında olağandışı hareket var.'),
        findsOneWidget);
  });

  testWidgets('"sakin varlıkları göster" kapalıysa sakinler gizlenir',
      (t) async {
    await _kur(t, [_fon('SAKIN', 1e6), _fon('AFT', 412e6)], sakinGoster: false);
    expect(find.text('SAKIN'), findsNothing);
    expect(find.text('AFT'), findsOneWidget);
  });

  testWidgets('hiç olağandışı yoksa başlık bunu söyler', (t) async {
    await _kur(t, [_fon('SAKIN', 1e6)]);
    expect(find.text('Son haftada varlıklarında olağandışı bir hareket yok.'),
        findsOneWidget);
  });

  testWidgets('not satırı ve aylık rapor satırı (S16-B)', (t) async {
    await _kur(t, [
      _fon('AFT', 412e6, olaylar: [_olay(9, 29, 400e6)]),
    ], notlar: {
      'TEFAS:AFT': AnalizOzeti(
          ticker: 'TEFAS:AFT',
          donem: _g(9, 28),
          baslik: 'Fona geçen hafta +₺412,00M net para girdi.',
          rozet: 'buyuk_giris',
          maddeSayisi: 3),
    }, aylik: {
      'TEFAS:AFT': AnalizOzeti(
          ticker: 'TEFAS:AFT',
          donem: _g(9, 1),
          baslik: 'Eylülde fona para girdi.',
          rozet: 'buyuk_giris',
          maddeSayisi: 2),
    });
    expect(find.text('Not: Fona geçen hafta +₺412,00M net para girdi.'),
        findsOneWidget);
    expect(find.text('Oku'), findsOneWidget);
    expect(find.text('AYLIK RAPOR'), findsOneWidget);
    expect(find.text('Eylül 2026 raporu'), findsOneWidget);
  });

  testWidgets('boş liste: açıklayıcı boş durum, kart yok', (t) async {
    await _kur(t, const []);
    expect(find.byType(SandikCard), findsNothing);
    expect(find.textContaining('Bu hafta gösterecek'), findsOneWidget);
  });

  testWidgets('dar ekran (320) ve büyük yazı (1,6×) taşmaz', (t) async {
    await _kur(
        t,
        [
          _fon('TTE', -26.34e6,
              ad: 'İş Portföy BIST Teknoloji Yabancı Hisse Senedi Fonu (Hisse '
                  'Senedi Yoğun Fon)'),
          hacimSatiri(_hisse('KRIPTO:BTC', 'Bitcoin', AssetType.kripto),
              'KRIPTO:BTC', _hacimOzeti(pay: 0.44, olaylar: [_hacimOlayi()]),
              kripto: true),
        ],
        genislik: 320,
        olcek: 1.6,
        notlar: {
          'TEFAS:TTE': AnalizOzeti(
              ticker: 'TEFAS:TTE',
              donem: _g(9, 28),
              baslik: 'Fondan geçen hafta −₺26,34M net para çıktı; bu, '
                  'büyüklüğün %2,6’sı.',
              rozet: 'sakin',
              maddeSayisi: 1),
        });
    expect(t.takeException(), isNull);
  });

  test('sonHaftaHacimOlayi: son 7 gün içindeki en yeni olay', () {
    HacimOzeti ozet(List<HacimOlayi> olaylar) => HacimOzeti(
          gunler: const [],
          sonGun: HacimGunu(tarih: _g(10, 2), kapanis: 1, paraHacmi: 1),
          ortalama: null,
          kat: null,
          fiyatDegisim: null,
          olaylar: olaylar,
        );
    HacimOlayi o(int ay, int gun) => HacimOlayi(
        tarih: _g(ay, gun),
        yukselis: true,
        paraHacmi: 1,
        ortalamaKati: 3,
        fiyatDegisim: 0);
    expect(sonHaftaHacimOlayi(ozet([o(9, 25)])), isNull);
    expect(sonHaftaHacimOlayi(ozet([o(10, 1), o(9, 26)]))!.tarih, _g(10, 1));
    expect(sonHaftaHacimOlayi(ozet([o(9, 26)]))!.tarih, _g(9, 26));
  });

  group('sıra ve yardımcılar', () {
    test('aynı rozette fon: akışın büyüklüğe ORANI (tutar değil)', () {
      final sirali = haftaSirasi([
        _fon('BUYUK', 500e6, buyukluk: 50e9), // %1
        _fon('KUCUK', -40e6, buyukluk: 500e6), // %8
        _fon('OLAY', 10e6, buyukluk: 5e9, olaylar: [_olay(10, 1, 300e6)]),
      ]);
      expect(sirali.first.anahtar, 'TEFAS:OLAY');
      expect(sirali.first.rozet, HaftaRozeti.buyukGiris);
    });

    test('sonHaftaOlayi yalnız son haftaya düşen olayı verir', () {
      expect(sonHaftaOlayi(_ozet(1, olaylar: [_olay(9, 25, 5e6)])), isNull);
      expect(sonHaftaOlayi(_ozet(1, olaylar: [_olay(9, 28, 5e6)]))!.tarih,
          _g(9, 28));
    });

    test('sunucu rozeti eşlemesi ve "olağandışı" kümesi', () {
      expect(haftaRozetiSunucudan('alici_istekli'), HaftaRozeti.aliciIstekli);
      expect(haftaRozetiSunucudan('bilinmeyen'), isNull);
      expect(HaftaRozeti.saticiIstekli.olagandisi, isTrue);
      expect(HaftaRozeti.hareketli.olagandisi, isFalse);
    });

    test('kripto rozet: ≤ 0,45 satıcı, ≥ 0,55 alıcı (sunucuyla aynı sınır)',
        () {
      HaftaRozeti r(double p) => hacimSatiri(
              _hisse('KRIPTO:BTC', 'Bitcoin', AssetType.kripto),
              'KRIPTO:BTC',
              _hacimOzeti(pay: p),
              kripto: true)
          .rozet;
      expect(r(0.45), HaftaRozeti.saticiIstekli);
      expect(r(0.55), HaftaRozeti.aliciIstekli);
      expect(r(0.53), HaftaRozeti.hareketli);
      expect(r(0.51), HaftaRozeti.sakin);
    });
  });

  group('bildirim yönlendirmesi', () {
    tearDown(() => RemoteConfigService.testAcik = {});

    test('akis işareti VE bayrak birlikte gerekir', () {
      expect(NotificationService.haftaOzetineGider({'akis': '1'}), isFalse,
          reason: 'bayrak kapalıyken eski hedef (Özet)');
      RemoteConfigService.testAcik = {'balina_radari_acik'};
      expect(NotificationService.haftaOzetineGider({'akis': '1'}), isTrue);
      expect(NotificationService.haftaOzetineGider({}), isFalse);
      expect(NotificationService.haftaOzetineGider({'akis': '0'}), isFalse);
    });

    test('push ve çan aynı kuralı kullanır; sunucu işareti yazar', () {
      expect(ekranKaynagiSync('lib/screens/home_screen.dart'),
          contains('NotificationService.haftaOzetineGider(b.data)'));
      final fn = ekranKaynagiSync('supabase/functions/weekly-summary/index.ts');
      expect(fn, contains("{ type: bildirimTipi, sent_on: bugun, akis: '1' }"));
      expect(fn, contains("{ sent_on: bugun, akis: '1' }"));
    });
  });

  test('ekran portföy yüzdesi hesaplamaz (tek kaynağı Performans › Özet)', () {
    final kaynak = ekranKaynagiSync('lib/screens/hafta_ozeti_screen.dart') +
        ekranKaynagiSync('lib/providers/hafta_ozeti_provider.dart');
    expect(kaynak, isNot(contains('PeriodSummary')));
    // `fmtPct` hacim satırındaki fiyat değişimi için var; portföy getirisi
    // için değil — dönem özeti servisi ya da XIRR buraya girmez.
    expect(kaynak, isNot(contains('xirr')));
    expect(kaynak, isNot(contains('getiriPct')));
    // Sayılar kartla aynı provider'dan.
    expect(kaynak, contains('fonAkisiProvider('));
    expect(kaynak, contains('hisseHacmiProvider('));
    expect(kaynak, contains('kriptoBaskiProvider('));
  });
}
