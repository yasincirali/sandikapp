import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/widgets/varlik_iskeleti.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';

import 'helpers/kaynak.dart';

/// Portföy › varlık detayının A düzeni (kullanıcı kararı, 2026-09-28):
/// varlık sayfası ailesi + fiyatın altında pozisyon satırı. Bu test
/// "hiçbir veri kaybolmasın" şartının bekçisidir: yeni üst blok (güncel
/// fiyat, pozisyon satırı), 5Y dönemi ve eski pozisyon bölümü birlikte
/// görünmeli; parçalar varlık sayfasıyla ORTAK kalmalı.

const _uid = 'user-1';

Asset _asset() => Asset(
      id: 'THYAO-1',
      userId: _uid,
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 100,
      purchasePrice: 250.75,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 312.40,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test Kullanıcı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: [_asset()],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  testWidgets('üst blok: güncel fiyat, pozisyon satırı, 5Y, pozisyon bölümü',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: _asset(), showBackButton: true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('GÜNCEL FİYAT'), findsOneWidget);
    expect(find.textContaining('Pozisyonun:'), findsOneWidget);
    expect(find.text('5Y'), findsOneWidget);
    // Eski pozisyon bölümü yerinde (veri kaybı yok): başlık + adet satırı.
    expect(find.text('POZİSYONUN'), findsOneWidget);

    // Güncel fiyat, sinyal/pozisyon bloğundan ÖNCE gelir (A düzeni).
    final fiyatY = tester.getTopLeft(find.text('GÜNCEL FİYAT')).dy;
    final pozisyonY = tester.getTopLeft(find.text('POZİSYONUN')).dy;
    expect(fiyatY, lessThan(pozisyonY));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pozisyon kartı: alış fiyatı, toplam ve dönem kâr/zararı düz dille',
      (tester) async {
    // Kullanıcı şartı (2026-09-28): "kaçtan aldığım, toplam kâr/zarar ve
    // dönem içindeki kâr/zarar KESİNLİKLE olmalı; okunaklı, basit
    // ibarelerle." Eski "ALIŞ / LOT → BUGÜN / LOT" oku ve rozet içindeki
    // üç minik sayı yerine etiket · değer satırları.
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: _asset(), showBackButton: true),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    for (final etiket in [
      'Miktar',
      'Alış fiyatın (ortalama)',
      'Bugünkü fiyat',
      'Ödediğin toplam',
      'Bugünkü değer',
      'Toplam kâr/zarar',
    ]) {
      expect(find.text(etiket), findsOneWidget, reason: '$etiket satırı yok');
    }
    // Seçili dönemin satırı: "{dönem} kâr/zarar" — toplamla birlikte iki.
    expect(find.textContaining('kâr/zarar'), findsNWidgets(2));
    // Alış 250,75 → bugün 312,40: kâr; tutar ve yüzde işaretli, tek satırda.
    expect(find.text('₺250,75 / lot'), findsOneWidget, reason: 'alış fiyatı');
    // Büyük güncel fiyat da 312,40 yazar; kart satırı birimiyle aranır.
    expect(find.text('₺312,40 / lot'), findsOneWidget, reason: 'bugünkü fiyat');
    expect(find.textContaining('+₺6.165 · +%24,59'), findsOneWidget,
        reason: 'toplam kâr/zarar: (312,40−250,75)×100 = 6.165, %24,59');
    // Eski sıkışık dil gitti.
    expect(find.textContaining('ALIŞ /'), findsNothing);
    expect(find.textContaining('DEĞİŞİM'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('açılış: seriler gelene kadar tek iskelet, sonra hepsi birden',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    HistoryService.clearCache();
    final bekleyen = <Completer<List<(int, double)>>>[];
    HistoryService.seriCekici = (sym, range, interval) {
      final c = Completer<List<(int, double)>>();
      bekleyen.add(c);
      return c.future;
    };
    addTearDown(() =>
        HistoryService.seriCekici = HistoryService.varsayilanSeriCekici);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(_FakePortfolio.new),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: AssetDetailScreen(asset: _asset(), showBackButton: true),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    // Başlık hemen, geri kalan tek iskelet.
    expect(find.text('THYAO'), findsOneWidget);
    expect(find.byType(VarlikIskeleti), findsOneWidget);
    expect(find.text('GÜNCEL FİYAT'), findsNothing);
    expect(find.text('POZİSYONUN'), findsNothing);

    final now = DateTime.now();
    for (final c in bekleyen) {
      c.complete([
        (now.subtract(const Duration(days: 2000)).millisecondsSinceEpoch, 280.0),
        (now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch, 312.4),
      ]);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(VarlikIskeleti), findsNothing);
    expect(find.text('GÜNCEL FİYAT'), findsOneWidget);
    expect(find.text('POZİSYONUN'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('dönem aralığı 320pt\'de büyük tutarla taşmaz', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 600 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: DonemAralikCubugu(
            dusuk: 1234567.89,
            yuksek: 9876543.21,
            konum: 0.4,
            bicim: tryFormatter(digits: 2),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  test('dönem seçici, ızgara ve aralık iki ekranda da ORTAK widget\'tan gelir', () {
    final sayfa = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
    final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    for (final w in [
      'DonemSecici(',
      'DonemIstatistikIzgarasi(',
      'DonemAralikCubugu(',
    ]) {
      expect(sayfa, contains(w), reason: 'varlık sayfası $w kullanmalı');
      expect(detay, contains(w), reason: 'varlık detayı $w kullanmalı');
    }
    // Detay ekranı kendi dönem düğmesi satırını geri getirmesin.
    expect(detay, isNot(contains('_buildPeriodToggle')));
    expect(File('lib/widgets/donem_istatistik.dart').existsSync(), isTrue);
  });
}
