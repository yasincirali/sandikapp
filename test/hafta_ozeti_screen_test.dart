import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/hafta_ozeti_provider.dart';
import 'package:portfoy_takip/screens/hafta_ozeti_screen.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';
import 'package:portfoy_takip/services/hisse_hacmi.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';

import 'helpers/kaynak.dart';

/// "Haftanın özeti" ekranı (Balina B4). Liste provider override'ıyla verilir.
///
/// ## Kilitlenen davranışlar
/// 1. Satır: fon kodu, adı (kesilmeden), yönlü tutar, yön etiketi + aralık.
/// 2. Son haftasında büyük hareket olan fon rozet alır ve ÜSTE çıkar.
/// 3. Liste boşsa açıklayıcı boş durum; hata/uydurma satır yok.
/// 4. Ekran portföy yüzdesi hesaplamaz (tek kaynağı Özet).
/// 5. Bildirim yalnız `akis: '1'` VE bayrak açıkken bu ekrana gider.
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
          HaftaAkisi(
              baslangic: DateTime.utc(2026, 9, 28 - 7 * i), net: 1e6),
        HaftaAkisi(baslangic: _g(9, 28), net: net),
      ],
      sonHaftaNet: net,
      sonHaftaIlkGun: _g(9, 28),
      veriTarihi: _g(10, 2),
      buyukluk: buyukluk,
      yatirimci: null,
      yatirimciDegisimi: null,
      olaylar: olaylar,
    );

FonHaftasi _fon(String kod, double net,
        {String? ad,
        double buyukluk = 1e9,
        List<FonBalinaOlayi> olaylar = const []}) =>
    FonHaftasi(
        pozisyon: _poz(kod, ad ?? '$kod Fonu'),
        ozet: _ozet(net, buyukluk: buyukluk, olaylar: olaylar));

FonBalinaOlayi _olay(int ay, int gun, double tutar) => FonBalinaOlayi(
    tarih: _g(ay, gun), tutar: tutar, buyuklukOrani: 0.05, sapmaKati: 5);

Future<void> _kur(WidgetTester t, List<FonHaftasi> liste,
    {double genislik = 390,
    double olcek = 1,
    List<HacimHaftasi> hacimler = const []}) async {
  t.view.physicalSize = Size(genislik, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      haftaOzetiProvider.overrideWith((ref) async => liste),
      haftaHacimProvider.overrideWith((ref) async => hacimler),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(genislik, 1600), textScaler: TextScaler.linear(olcek)),
        child: const HaftaOzetiScreen(),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('satır: kod, ad, yönlü tutar, yön etiketi ve aralık', (t) async {
    await _kur(t, [
      _fon('TTE', -26.34e6, ad: 'İş Portföy BIST Teknoloji Fonu'),
      _fon('AFT', 412e6),
    ]);
    expect(find.text('Haftanın özeti'), findsOneWidget);
    expect(find.text('FONLARINDA PARA AKIŞI'), findsOneWidget);
    expect(find.text('TTE'), findsOneWidget);
    expect(find.text('İş Portföy BIST Teknoloji Fonu'), findsOneWidget);
    expect(find.text('−₺26,34M'), findsOneWidget);
    expect(find.text('Net çıkış · 28 Eyl - 2 Eki'), findsOneWidget);
    expect(find.text('+₺412,00M'), findsOneWidget);
    expect(find.text('Net giriş · 28 Eyl - 2 Eki'), findsOneWidget);
    expect(find.textContaining('büyük'), findsNothing);
    expect(find.textContaining('Kaynak: TEFAS'), findsOneWidget);
  });

  testWidgets('son haftada büyük hareket rozeti; eski olay rozet vermez',
      (t) async {
    await _kur(t, [
      _fon('DOV', -1.65e9, olaylar: [_olay(9, 29, -2e9)]),
      _fon('TTE', -26e6, olaylar: [_olay(9, 21, -50e6)]), // önceki hafta
    ]);
    expect(find.text('Bu hafta büyük çıkış var'), findsOneWidget);
    expect(find.text('Bu hafta büyük giriş var'), findsNothing);
  });

  testWidgets('boş liste: açıklayıcı boş durum, kart yok', (t) async {
    await _kur(t, const []);
    expect(find.byType(SandikCard), findsNothing);
    expect(find.textContaining('Bu hafta gösterecek bir şey yok'),
        findsOneWidget);
  });

  testWidgets('dar ekran (320) ve büyük yazı (1,5×) taşmaz', (t) async {
    await _kur(
      t,
      [
        _fon('TTE', -26.34e6,
            ad: 'İş Portföy BIST Teknoloji Ağırlık Sınırlamalı Endeksi '
                'Hisse Senedi (TL) Fonu (Hisse Senedi Yoğun Fon)',
            olaylar: [_olay(9, 30, -30e6)]),
      ],
      genislik: 320,
      olcek: 1.5,
    );
    expect(t.takeException(), isNull);
    expect(find.text('−₺26,34M'), findsOneWidget);
  });

  testWidgets('olağandışı hacim bölümü: hisse TL, kripto dolar ve alıcı payı',
      (t) async {
    final hisse = aggregatePositions([
      Asset(
        id: 'h',
        userId: 'u1',
        name: 'Astor Enerji',
        ticker: 'ASTOR.IS',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 1,
        addedDate: DateTime(2026, 3, 14),
      ),
    ]).single;
    await _kur(t, const [], hacimler: [
      HacimHaftasi(
        pozisyon: hisse,
        kripto: false,
        olay: HacimOlayi(
            tarih: _g(10, 1),
            yukselis: true,
            paraHacmi: 35.46e9,
            ortalamaKati: 4.7,
            fiyatDegisim: 0.0997),
      ),
      HacimHaftasi(
        pozisyon: hisse,
        kripto: true,
        olay: HacimOlayi(
            tarih: _g(9, 30),
            yukselis: false,
            paraHacmi: 2.62e9,
            ortalamaKati: 2.3,
            fiyatDegisim: -0.03,
            aliciPayi: 0.482),
      ),
    ]);
    expect(find.text('OLAĞANDIŞI HACİM'), findsOneWidget);
    expect(find.text('FONLARINDA PARA AKIŞI'), findsNothing);
    expect(find.text('Olağandışı hacim · 1 Eki'), findsOneWidget);
    expect(find.text('₺35,46Mr · ortalamanın 4,7 katı · fiyat +%10,0'),
        findsOneWidget);
    expect(
        find.text(r'$2,62Mr · ortalamanın 2,3 katı · fiyat −%3,0 · '
            'alıcı payı %48,2'),
        findsOneWidget);
    expect(find.textContaining('Bu hafta gösterecek'), findsNothing);
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
    test('olaylı fon üste; sonra akışın büyüklüğe ORANI (tutar değil)', () {
      final sirali = haftaSirasi([
        _fon('BUYUK', 500e6, buyukluk: 50e9), // %1
        _fon('KUCUK', -40e6, buyukluk: 500e6), // %8
        _fon('OLAY', 10e6, buyukluk: 5e9, olaylar: [_olay(10, 1, 300e6)]),
      ]);
      expect(sirali.map((f) => f.pozisyon.representative.ticker),
          ['TEFAS:OLAY', 'TEFAS:KUCUK', 'TEFAS:BUYUK']);
    });

    test('sonHaftaOlayi yalnız son haftaya düşen olayı verir', () {
      expect(sonHaftaOlayi(_ozet(1, olaylar: [_olay(9, 25, 5e6)])), isNull);
      expect(
          sonHaftaOlayi(_ozet(1, olaylar: [_olay(9, 28, 5e6)]))!.tarih,
          _g(9, 28));
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
  });
}
