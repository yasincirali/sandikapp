import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/halka_arz_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/halka_arz_screen.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/halka_arz_service.dart';

/// Halka arz ekranı (F6) — gruplar, çevrimdışı yol, dar ekran, katılım
/// akışı ve Profil giriş satırının bayrağa bağlılığı.
///
/// "Bugün" `halkaArzSaatProvider` ile 29 Eylül 2026'ya sabit; servis ağa
/// çıkmaz (`MockClient`), dosya önbelleği kapalı (FakeAsync içinde gerçek
/// disk G/Ç'si beklemez).
final _bugun = DateTime(2026, 9, 29, 12);

Map<String, Object?> _k(
  String kod,
  String sirket, {
  String? bas,
  String? bit,
  String? islem,
  double? fiyat,
}) =>
    {
      'kod': kod,
      'sirket': sirket,
      'talep_baslangic': bas,
      'talep_bitis': bit,
      'fiyat': fiyat,
      'dagitim': 'eşit',
      'islem_baslangic': islem,
      'pazar': 'Yıldız Pazar',
      'kaynak': 'https://ornek.test/$kod',
      'guncelleme': '2026-09-29',
    };

/// Her gruptan bir kayıt (bugün = 29 Eylül).
final _karma = jsonEncode({
  'surum': 1,
  'guncelleme': '2026-09-29',
  'kayitlar': [
    _k('TALEP', 'Talep Toplayan Uzun Adlı Sanayi ve Ticaret Anonim Şirketi',
        bas: '2026-09-28', bit: '2026-09-30', fiyat: 12.5),
    _k('YAKIN', 'Yaklaşan A.Ş.', bas: '2026-10-06', bit: '2026-10-08'),
    _k('BEKLE', 'Bekleyen A.Ş.', bas: '2026-09-22', bit: '2026-09-24'),
    _k('ISLEM', 'İşlem Gören A.Ş.',
        bas: '2026-09-09', bit: '2026-09-11', islem: '2026-09-17', fiyat: 25.52),
    _k('BELIR', 'Belirsiz A.Ş.'),
  ],
});

HalkaArzService _servis({String? ag, String? gomulu}) => HalkaArzService(
      client: MockClient((r) async {
        if (ag == null) throw const SocketException('çevrimdışı');
        return http.Response.bytes(utf8.encode(ag), 200);
      }),
      gomuluYukle: () async => gomulu ?? (throw StateError('gömülü yok')),
      onbellekDosyasi: () async => null,
    );

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState(
        assets: <Asset>[],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

/// Fiyat araması sayılır: ön dolu fiyatla açılan form ağa ÇIKMAMALI.
class _SayanLookup implements AddAssetPriceLookup {
  int cagri = 0;
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async {
    cagri++;
    return null;
  }

  @override
  Future<double?> spot(String ticker) async {
    cagri++;
    return null; // işlem görmeyen hisse: kotasyon yok
  }

  @override
  Future<String?> companyName(String ticker) async => null;
}

Future<void> _ekran(
  WidgetTester tester,
  HalkaArzService servis, {
  double genislik = 375,
  _SayanLookup? lookup,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      halkaArzServiceProvider.overrideWithValue(servis),
      halkaArzSaatProvider.overrideWithValue(() => _bugun),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      addAssetPriceLookupProvider.overrideWithValue(lookup ?? _SayanLookup()),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: const HalkaArzScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

// ── Profil ──────────────────────────────────────────────────────────────────

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _FakeSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];
}

Future<void> _profil(WidgetTester tester, {required bool bayrak}) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      halkaArzEtkinProvider.overrideWithValue(bayrak),
      halkaArzServiceProvider.overrideWithValue(_servis(
          gomulu: File('assets/data/halka_arz.json').readAsStringSync())),
      halkaArzSaatProvider.overrideWithValue(() => _bugun),
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
    ],
    child: const MaterialApp(
        home: Material(
            type: MaterialType.transparency, child: ProfileScreen())),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// `pushGuarded` çift dokunma penceresini GERÇEK saatle ölçer (350 ms);
/// art arda koşan testlerde önceki testin push'u bir sonrakini yutmasın.
Future<void> _gercekZamanBekle(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  group('liste', () {
    testWidgets('beş durum grubu doğru sırada, sayılarıyla', (tester) async {
      await _ekran(tester, _servis(ag: _karma));
      final basliklar = [
        'TALEP TOPLANIYOR',
        'YAKLAŞAN',
        'İŞLEM GÖRMEYİ BEKLİYOR',
        'İŞLEM GÖRÜYOR',
        'TARİHİ BELİRSİZ',
      ];
      // Yalnız İLERİ kaydırarak hepsi bulunuyorsa sıra da doğrudur:
      // `scrollUntilVisible` geri gitmez.
      for (final b in basliklar) {
        await tester.scrollUntilVisible(find.text(b), 200);
        expect(find.text(b), findsOneWidget, reason: '$b grubu yok');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('grup sırası: talep en üstte, belirsiz en altta', (tester) async {
      await _ekran(tester, _servis(ag: _karma), genislik: 430);
      final ilk = tester.getTopLeft(find.text('TALEP TOPLANIYOR')).dy;
      final ikinci = tester.getTopLeft(find.text('YAKLAŞAN')).dy;
      expect(ilk, lessThan(ikinci));
      expect(find.text('Talep: 28 Eyl – 30 Eyl'), findsOneWidget);
      expect(find.text('₺12,50'), findsOneWidget);
      // Fiyatı bilinmeyen kayıt "—" gösterir, 0 değil.
      expect(find.text('—'), findsWidgets);
      expect(find.textContaining('Çevrimdışı'), findsNothing);
    });

    testWidgets('çevrimdışı: gömülü asset listesi + açık not', (tester) async {
      final gercekAsset = File('assets/data/halka_arz.json').readAsStringSync();
      await _ekran(tester, _servis(gomulu: gercekAsset));
      expect(find.textContaining('Çevrimdışı'), findsOneWidget);
      // Gerçek verideki kayıtların hepsi 29 Eylül itibarıyla işlem görüyor.
      expect(find.text('İŞLEM GÖRÜYOR'), findsOneWidget);
      expect(find.text('NETGL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hiçbir kaynak yoksa hata görünümü, çökme yok', (tester) async {
      await _ekran(tester, _servis());
      expect(find.text('NETGL'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final w in <double>[320, 360]) {
      testWidgets('${w.toInt()}pt: liste ve detay taşmıyor', (tester) async {
        await _ekran(tester, _servis(ag: _karma), genislik: w);
        expect(tester.takeException(), isNull, reason: 'liste taşıyor');
        await tester.tap(find.text('TALEP'));
        await tester.pumpAndSettle();
        expect(find.text('Talep toplama'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'detay taşıyor');
      });
    }
  });

  group('detay ve katılım', () {
    testWidgets('talep toplanırken "Katıldım" yok, neden yazılı', (tester) async {
      await _ekran(tester, _servis(ag: _karma));
      await tester.tap(find.text('TALEP'));
      await tester.pumpAndSettle();
      expect(find.text('Katıldım, portföye ekle'), findsNothing);
      expect(find.textContaining('Dağıtım sonuçları'), findsOneWidget);
      expect(find.text('Kaynağı aç'), findsOneWidget);
    });

    testWidgets(
        'işlem görüyor: "Katıldım" formu kod, fiyat ve tarihle ön dolu açar; '
        'fiyat araması yapılmaz', (tester) async {
      final lookup = _SayanLookup();
      await _ekran(tester, _servis(ag: _karma), lookup: lookup);
      await tester.scrollUntilVisible(find.text('ISLEM'), 200);
      await tester.tap(find.text('ISLEM'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lot sayısını'), findsOneWidget);
      await _gercekZamanBekle(tester);
      await tester.tap(find.text('Katıldım, portföye ekle'));
      await tester.pumpAndSettle();

      final form = tester.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(form.prefillTicker, 'ISLEM.IS');
      expect(form.prefillPrice, 25.52);
      expect(form.prefillDate, DateTime(2026, 9, 17),
          reason: 'işlem başlangıç günü');
      // Alış fiyatı alanı yazılı geldi → önizleme ağa çıkmadı.
      expect(
          find.byWidgetPredicate(
              (w) => w is EditableText && w.controller.text == '25,52'),
          findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(lookup.cagri, 0,
          reason: 'işlem görmemiş hissenin kotasyonu olmayabilir; halka arz '
              'fiyatı verildiğinde arama yapılmamalı');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'işlem bekliyor + fiyat bilinmiyor: uyarı gösterilir, form fiyatsız '
        'açılır ve tarih bugündür', (tester) async {
      await _ekran(tester, _servis(ag: _karma));
      await tester.scrollUntilVisible(find.text('BEKLE'), 200);
      await tester.tap(find.text('BEKLE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Halka arz fiyatı listede yok'),
          findsOneWidget);
      await _gercekZamanBekle(tester);
      await tester.tap(find.text('Katıldım, portföye ekle'));
      await tester.pumpAndSettle();
      final form = tester.widget<AddAssetScreen>(find.byType(AddAssetScreen));
      expect(form.prefillPrice, isNull);
      expect(form.prefillDate, DateTime(2026, 9, 29));
      expect(tester.takeException(), isNull);
    });
  });

  group('Profil giriş satırı', () {
    testWidgets('bayrak kapalıyken satır YOK', (tester) async {
      await _profil(tester, bayrak: false);
      expect(find.byType(HalkaArzProfilSatiri), findsOneWidget);
      expect(find.text('Halka arzlar'), findsNothing);
    });

    testWidgets('bayrak açıkken satır var ve ekranı açar', (tester) async {
      await _profil(tester, bayrak: true);
      expect(find.text('Halka arzlar'), findsOneWidget);
      await _gercekZamanBekle(tester);
      await tester.tap(find.text('Halka arzlar'));
      await tester.pumpAndSettle();
      expect(find.byType(HalkaArzScreen), findsOneWidget);
      expect(find.text('NETGL'), findsOneWidget);
    });
  });
}
