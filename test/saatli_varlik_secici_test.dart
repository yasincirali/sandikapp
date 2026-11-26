import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/saatli_bildirim.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show initPreferencesCache;
import 'package:portfoy_takip/providers/saatli_bildirim_provider.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart' show OlcekHafizasi;
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/arama_satiri.dart';
import 'package:portfoy_takip/widgets/saatli_bildirim.dart';
import 'package:portfoy_takip/widgets/sandik_arama_alani.dart';
import 'package:portfoy_takip/widgets/varlik_rozeti.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Saatli extends SaatliBildirimlerNotifier {
  @override
  Future<List<SaatliBildirim>> build() async => [
        SaatliBildirim(
          id: 's1',
          userId: 'u1',
          symbol: 'THYAO.IS',
          label: 'Türk Hava Yolları',
          saatler: const [540, 780, 1080],
          createdAt: DateTime(2026, 11, 20),
        ),
      ];
}

const _kendi = [
  VarlikKimligi(
      ticker: 'ALTIN_GRAM24',
      name: 'Gram Altın (24 Ayar)',
      type: AssetType.altin,
      subCategory: 'ALTIN_GRAM24',
      currency: 'TRY'),
  VarlikKimligi(
      ticker: 'ASELS.IS',
      name: 'Aselsan',
      type: AssetType.hisse,
      currency: 'TRY'),
  VarlikKimligi(
      ticker: 'USDTRY=X',
      name: 'Amerikan Doları',
      type: AssetType.doviz,
      subCategory: 'USD',
      currency: 'TRY'),
  VarlikKimligi(
      ticker: 'TEFAS:AFT',
      name: 'Ak Portföy Yeni Teknolojiler Yabancı Hisse Fonu',
      type: AssetType.fon,
      currency: 'TRY'),
  VarlikKimligi(
      ticker: 'THYAO.IS',
      name: 'Türk Hava Yolları',
      type: AssetType.hisse,
      currency: 'TRY'),
];

/// Saatli bildirim › "Varlık seç" (2026-11-26 yeniden tasarım): kenar payı,
/// arama satırı, kurulu bildirim etiketi, tür başlıkları, ×2 yazı.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    SymbolSearchService.clearCacheForTest();
    // Disk belleği yükleme future'ı önceki testin sahte saatinde kalmasın.
    PriceService.instance.sonBilinenFiyatlariTemizle();
    OlcekHafizasi.instance.temizle();
    PriceService.instance.testIcinOnbellegeYaz(const YahooQuote(
        symbol: 'ASELS.IS',
        regularMarketPrice: 164.20,
        regularMarketChangePercent: 2.35,
        currency: 'TRY'));
  });

  Future<void> kur(WidgetTester t, {double olcek = 1}) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [saatliBildirimlerProvider.overrideWith(_Saatli.new)],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(olcek)),
            child: const Scaffold(
              body: SingleChildScrollView(
                  child: SaatliVarlikSecici(kendi: _kendi)),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      // Fiyat yolu (`fetchQuotes`) diskteki belleği gerçek G/Ç ile okur.
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> yaz(WidgetTester t, String q) async {
    await t.enterText(find.byType(EditableText), q);
    // Fon katmanı testte ağa çıkamaz; arama katmanları beklediği için hem
    // gerçek G/Ç'ye hem sahte saate süre ver (arama_ekrani_test kalıbı).
    for (var i = 0; i < 20; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(seconds: 1));
    }
  }

  testWidgets('alan ve satırlar ekran kenarından screenH içeride', (t) async {
    await kur(t);
    const hp = SandikSpace.smd; // screenH
    final alan = t.getRect(find.byType(SandikAramaAlani));
    expect(alan.left, hp);
    expect(alan.right, 390 - hp);
    final satir = t.getRect(find.byType(AramaSatirKutusu).first);
    expect(satir.left, hp);
    expect(satir.right, 390 - hp);
  });

  testWidgets('satır arama satırıdır: rozet, sembol · tür, fiyat', (t) async {
    await kur(t);
    expect(find.byType(AramaSatirKutusu), findsNWidgets(5));
    expect(find.byType(VarlikRozeti), findsNWidgets(5));
    expect(find.text('ASELS · Hisse'), findsOneWidget);
    expect(find.text('AFT · Fon'), findsOneWidget);
    expect(find.text('USD · Döviz'), findsOneWidget);
    expect(find.text('₺164,20'), findsOneWidget);
    // Fiyatı bilinmeyen varlıkta sayı uydurulmaz.
    expect(find.textContaining('₺0'), findsNothing);
  });

  testWidgets('kurulu bildirimde "3 saat" ve tek cümlelik etiket', (t) async {
    final h = t.ensureSemantics();
    await kur(t);
    expect(find.text('3 saat'), findsOneWidget);
    expect(
        find.bySemanticsLabel(
            'Türk Hava Yolları, THYAO, 3 saatte bildirim kurulu'),
        findsOneWidget);
    expect(find.bySemanticsLabel('Aselsan, ASELS, ₺164,20'), findsOneWidget);
    h.dispose();
  });

  testWidgets('satırlar en az 44 pt', (t) async {
    await kur(t);
    for (final e in find.byType(AramaSatirKutusu).evaluate()) {
      expect(e.size!.height, greaterThanOrEqualTo(SandikTouch.min));
    }
  });

  testWidgets('boş sorgu: tür başlıkları AssetType sırasıyla', (t) async {
    await kur(t);
    double y(String s) => t.getTopLeft(find.text(s).first).dy;
    expect(find.byType(SandikSectionHeader), findsNWidgets(4));
    expect(y('Hisse'), lessThan(y('Fon')));
    expect(y('Fon'), lessThan(y('Döviz')));
    expect(y('Döviz'), lessThan(y('Altın')));
    // Aynı türün satırları başlığının altında.
    expect(y('Aselsan'), greaterThan(y('Hisse')));
    expect(y('Türk Hava Yolları'), lessThan(y('Fon')));
  });

  testWidgets('yazarken "Aranıyor…", sonuçta türe göre başlıklar',
      (t) async {
    await kur(t);
    await t.enterText(find.byType(EditableText), 'altin');
    await t.pump();
    expect(find.text('Aranıyor…'), findsOneWidget);
    await yaz(t, 'altin');
    expect(find.text('Aranıyor…'), findsNothing);
    expect(find.widgetWithText(SandikSectionHeader, 'Altın'), findsOneWidget);
    expect(find.byType(AramaSatirKutusu), findsWidgets);
    // Kendi listesi aramada görünmez (yalnız sonuç).
    expect(find.text('Aselsan'), findsNothing);
  });

  testWidgets('eşleşme yoksa eski metin', (t) async {
    await kur(t);
    await yaz(t, 'zzqqxx');
    expect(find.text('Eşleşen varlık yok'), findsOneWidget);
  });

  testWidgets('yazı ×2: taşma yok', (t) async {
    await kur(t, olcek: 2);
    expect(t.takeException(), isNull);
    expect(find.text('3 saat'), findsOneWidget);
  });

  testWidgets('satıra dokunmak sembol ve adı döndürür', (t) async {
    t.view.physicalSize = const Size(390 * 3, 844 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    SaatliSecim? sonuc;
    await t.pumpWidget(ProviderScope(
      overrides: [saatliBildirimlerProvider.overrideWith(_Saatli.new)],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.light, Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => sonuc = await showSandikSheet<SaatliSecim>(
              context: context,
              isScrollControlled: true,
              baslik: 'Varlık seç',
              builder: (_) => const SaatliVarlikSecici(kendi: _kendi),
            ),
            child: const Text('aç'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    await t.tap(find.text('Gram Altın (24 Ayar)'));
    await t.pumpAndSettle();
    expect(sonuc, (sembol: 'ALTIN_GRAM24', ad: 'Gram Altın (24 Ayar)'));
  });
}
