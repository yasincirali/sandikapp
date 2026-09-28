import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/add_watchlist_screen.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: const <Asset>[],
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

class _Takip extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];
}

class _Oturumsuz extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

/// Arama ekranı — boş hâl, gruplu sonuç, tür çipi (arama tasarımı 2026-09-28).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SymbolSearchService.clearCacheForTest();
  });

  Future<void> kur(WidgetTester t,
      {Map<String, YahooQuote> kotasyon = const {}}) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith(_Oturumsuz.new),
        portfolioProvider.overrideWith(_Portfoy.new),
        watchlistProvider.overrideWith(_Takip.new),
      ],
      child: MaterialApp(home: AddWatchlistScreen(baslangicKotasyon: kotasyon)),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> yaz(WidgetTester t, String q) async {
    await t.enterText(find.byType(EditableText), q);
    // Fon katmanı testte ağa çıkamaz (400/zaman aşımı); arama tüm
    // katmanları beklediği için hem gerçek G/Ç'ye hem sahte saate süre ver.
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('boş sorgu: Piyasalar önerileri görünür', (t) async {
    await kur(t);
    expect(find.text('PİYASALAR'), findsOneWidget);
    expect(find.text('BIST 100 Endeksi'), findsOneWidget);
    expect(find.text('Vazgeç'), findsOneWidget);
  });

  testWidgets('"altin": altın grubu 3 satır + Tümü (n); çip türe odaklar',
      (t) async {
    await kur(t);
    await yaz(t, 'altin');
    expect(find.text('ALTIN'), findsWidgets, reason: 'grup başlığı');
    expect(find.text('Aranıyor…'), findsNothing);
    final tumu = find.textContaining(RegExp(r'^Tümü \(\d+\)$'));
    expect(tumu, findsWidgets);
    await t.tap(tumu.first);
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    // Tür seçilince o grup kısaltılmaz: "Tümü (n)" o grupta kalkar.
    expect(find.textContaining(RegExp(r'^Tümü \(\d+\)$')), findsNothing);
  });

  testWidgets('bölüm başlığı Türkçe büyük harf: HİSSE, DÖVİZ', (t) async {
    await kur(t);
    await yaz(t, 'dolar');
    expect(find.text('DÖVİZ'), findsOneWidget);
    expect(find.text('DÖVIZ'), findsNothing);
  });

  testWidgets('yerleşik sonuçlar fon katmanını BEKLEMEDEN görünür',
      (t) async {
    await kur(t);
    await t.enterText(find.byType(EditableText), 'turk hava');
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    // Fon katmanı henüz dönmedi ("Aranıyor…") ama hisse zaten listede.
    expect(find.text('Türk Hava Yolları'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(seconds: 1));
    }
  });

  testWidgets('satırda fiyat ve günlük değişim; bilinmeyen yazılmaz',
      (t) async {
    await kur(t, kotasyon: const {
      'XU100.IS': YahooQuote(
          symbol: 'XU100.IS',
          regularMarketPrice: 11482.4,
          regularMarketChangePercent: 1.25),
    });
    expect(find.text('11.482'), findsOneWidget);
    expect(find.textContaining('1,25'), findsOneWidget);
    // Garanti'nin kotasyonu yok: satırda sayı UYDURULMAZ.
    expect(find.text('Garanti BBVA'), findsOneWidget);
    expect(find.textContaining('₺'), findsNothing);
  });

  testWidgets('sonuç yoksa söylenir', (t) async {
    await kur(t);
    await yaz(t, 'zzzqqqxyz123');
    expect(find.textContaining('zzzqqqxyz123'), findsWidgets);
  });
}
