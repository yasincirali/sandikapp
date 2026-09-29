import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/demo/demo_kabugu.dart';
import 'package:portfoy_takip/demo/demo_modu.dart';
import 'package:portfoy_takip/demo/demo_saglayicilar.dart';
import 'package:portfoy_takip/demo/demo_verisi.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/screens/login_screen.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/services/supabase_service.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

import 'helpers/kaynak.dart';

/// "Örnek portföyle dene" (F1) — demo sunucuya DOKUNMAZ (ADR-1).
///
/// Testin gücü kurulumunda: `Supabase.initialize` ÇAĞRILMAZ. Demo içinden
/// herhangi bir yol `Supabase.instance`'a uzanırsa assert fırlar; bir
/// servis bu hatayı `catch` ile yutsa bile `SupabaseService` kapısı izi
/// `DemoModu.ihlaller`e yazar ve test onu da okur. Yani sızıntı ya
/// "yakalanmamış hata" ya da "ihlal listesi dolu" olarak görünür.
///
/// Fiyatlar sabit kotasyondan gelir (`DemoPortfolioNotifier.kotasyonlar`):
/// test ağsız ve belirleyici; üretimde aynı yuva `PriceService.fetchQuotes`.

Future<Map<String, YahooQuote>> _sabitKotasyon(
    List<String> semboller, bool _) async {
  const fiyat = <String, double>{
    'USDTRY=X': 41.2,
    'EURTRY=X': 48.1,
    'GBPTRY=X': 55.3,
    'ALTIN_CEYREK': 10800,
    'TEFAS:DLY': 6.2,
    'TEFAS:AFT': 0.98,
    'KCHOL.IS': 206.1,
    'SAHOL.IS': 86.0,
  };
  return {
    for (final s in semboller)
      if (fiyat[s] != null)
        s: YahooQuote(symbol: s, regularMarketPrice: fiyat[s]),
  };
}

/// Kökteki (gerçek uygulamanın) oturumu: giriş ekranında kimse yok.
class _OturumYok extends AuthNotifier {
  @override
  Future<AppUser?> build() async => null;
}

Future<void> _telefon(WidgetTester tester, {double en = 390, double boy = 844}) async {
  tester.view.physicalSize = Size(en * 3, boy * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

/// Ağaçtaki her şeyi söküp bekleyen zamanlayıcıları boşaltır.
Future<void> _sok(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 1));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });

  tearDownAll(() {
    DbLogger.silentInTests = false;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    DemoModu.ihlalleriSifirla();
    DemoPortfolioNotifier.kotasyonlar = _sabitKotasyon;
  });

  tearDown(() {
    DemoPortfolioNotifier.kotasyonlar =
        (s, z) => PriceService.instance.fetchQuotes(s, forceRefresh: z);
    DemoModu.girisDugmesiAcik = () => true;
  });

  testWidgets(
      'Supabase kurulmadan üç sekme gezilir; sunucuya tek istek gitmez',
      (tester) async {
    await _telefon(tester);
    await tester.pumpWidget(const MaterialApp(home: DemoKabugu()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(DemoModu.aktif, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('demo-sekme-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PortfolioScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('demo-sekme-2')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PortfolioPerformanceScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('demo-sekme-0')));
    await tester.pump(const Duration(milliseconds: 500));

    expect(DemoModu.ihlaller, isEmpty,
        reason: 'Demo sunucuya uzandı:\n${DemoModu.ihlaller.join('\n---\n')}');

    await _sok(tester);
    expect(DemoModu.aktif, isFalse,
        reason: 'Kabuk kapanınca bayrak inmeli — gerçek akış demodan '
            'etkilenmemeli.');
  });

  testWidgets('varlık ekranı da demo kapsamında, sunucusuz açılır',
      (tester) async {
    await _telefon(tester, boy: 2400);
    await tester.pumpWidget(const MaterialApp(home: DemoKabugu()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey('demo-sekme-1')));
    await tester.pump(const Duration(milliseconds: 500));

    // `pushGuarded`'ın çift dokunma penceresi GERÇEK saatle ölçülür;
    // önceki testin itmesi pencerede kalmasın.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    // Kart listesi ilk karede kurulmuyor (açılış animasyonu).
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find
        .descendant(
            of: find.byType(PortfolioScreen),
            matching: find.textContaining('KCHOL', findRichText: true))
        .first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AssetDetailScreen), findsOneWidget);
    // İtilen sayfa demo container'ını görmeli (kök navigator'a gitseydi
    // kök kapsamı okurdu — bu testte kök kapsam hiç yok, hata verirdi).
    final ctx = tester.element(find.byType(AssetDetailScreen));
    expect(
      ProviderScope.containerOf(ctx).read(authProvider).value?.id,
      kDemoKullaniciId,
    );
    expect(DemoModu.ihlaller, isEmpty,
        reason: 'Demo sunucuya uzandı:\n${DemoModu.ihlaller.join('\n---\n')}');

    await _sok(tester);
  });

  testWidgets('demo defteri CSV\'nin altı varlığı, fiyatlar canlı yuvadan',
      (tester) async {
    await _telefon(tester);
    await tester.pumpWidget(const MaterialApp(home: DemoKabugu()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ctx = tester.element(find.byType(HomeScreen));
    final state = ProviderScope.containerOf(ctx).read(portfolioProvider).value!;
    expect(state.ownerId, kDemoKullaniciId);
    final lotlar = state.assets;
    // Fonlar `TEFAS:` önekli (bulgu #2, 2026-09-29): CSV eskiden çıplak kod
    // yazıyordu ve demo fonları Yahoo'ya gidip fiyatsız kalıyordu.
    expect(lotlar.map((a) => a.ticker).toSet(), {
      'ALTIN_CEYREK', 'TEFAS:DLY', 'TEFAS:AFT', 'KCHOL.IS', 'USDTRY=X',
      'SAHOL.IS',
    });
    // Güncel fiyat kotasyondan; alış fiyatı CSV'den (uydurma yok).
    final kchol = lotlar.firstWhere((a) => a.ticker == 'KCHOL.IS');
    expect(kchol.purchasePrice, 148.0);
    expect(kchol.currentPrice, 206.1);
    // Fon da fiyatlanır — önekli sembol TEFAS yuvasına gider.
    expect(lotlar.firstWhere((a) => a.ticker == 'TEFAS:AFT').currentPrice,
        0.98);
    expect(state.totalValue, greaterThan(0));

    await _sok(tester);
  });

  testWidgets('yazma girişimi "hesap oluştur" sayfasını açar, kayıt ekranına '
      'götürür', (tester) async {
    // Uzun ekran: hareket satırları alt menünün altında kalmasın.
    await _telefon(tester, boy: 2400);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith(_OturumYok.new)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => demoyuAc(context),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.byType(DemoKabugu), findsOneWidget);

    // Ana ekrandaki bir hareket satırı → not düzenleme = yazma girişimi.
    final satir = find.byType(TransactionRow);
    expect(satir, findsWidgets);
    await tester.ensureVisible(satir.first);
    await tester.tap(satir.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text(trMetni('demoSaveSheetTitle')), findsOneWidget);
    expect(DemoModu.ihlaller, isEmpty);

    // Sayfadaki birincil düğme — şeritteki "Hesap oluştur" ile aynı metin,
    // sayfanınki en son çizilen.
    await tester.tap(find.text(trMetni('demoCreateAccount')).last);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(DemoKabugu), findsNothing);
    expect(find.byType(RegisterScreen), findsOneWidget);
    expect(DemoModu.aktif, isFalse);

    await _sok(tester);
  });

  testWidgets('demo notifier\'ı yazmayı sunucuya götürmez, engel fırlatır',
      (tester) async {
    final c = ProviderContainer(overrides: demoOverrides());
    addTearDown(c.dispose);
    DemoModu.ac();
    addTearDown(DemoModu.kapat);
    final defter = await c.read(portfolioProvider.future);
    final Asset lot = defter.assets.first;
    await expectLater(
      c.read(portfolioProvider.notifier).deletePositionLots([lot]),
      throwsA(isA<DemoYazmaEngeli>()),
    );
    await expectLater(
      c.read(portfolioProvider.notifier).updateNotes(lot, 'x'),
      throwsA(isA<DemoYazmaEngeli>()),
    );
    expect(DemoModu.ihlaller, isEmpty);
  });

  testWidgets('bayrak kapalıyken giriş ekranında "Önce bir göz at" yok',
      (tester) async {
    // Geniş ekran: test yazı tipi (Ahem) "Beni hatırla" satırını dar
    // ekranda taşırıyor — bu testin konusu değil.
    await _telefon(tester, en: 900, boy: 1600);
    Future<void> kur() => tester.pumpWidget(
          ProviderScope(
            overrides: [authProvider.overrideWith(_OturumYok.new)],
            child: const MaterialApp(home: LoginScreen()),
          ),
        );

    DemoModu.girisDugmesiAcik = () => false;
    await kur();
    await tester.pump();
    expect(find.text(trMetni('demoTryButton')), findsNothing);

    DemoModu.girisDugmesiAcik = () => true;
    await tester.pumpWidget(const SizedBox.shrink());
    await kur();
    await tester.pump();
    expect(find.text(trMetni('demoTryButton')), findsOneWidget);

    await _sok(tester);
  });

  test('lib/demo sunucu istemcisini import etmez', () {
    final dosyalar = Directory('lib/demo')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(dosyalar, isNotEmpty);
    for (final f in dosyalar) {
      // Yorum satırları sayılmaz: karar kaydı kapıyı adıyla anar.
      final src = ekranKaynagiSync(f.path)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src.contains('package:supabase_flutter'), isFalse,
          reason: '${f.path} supabase_flutter import ediyor — demo sunucuya '
              'dokunmamalı (ADR-1).');
      expect(src.contains('Supabase.instance'), isFalse,
          reason: '${f.path} Supabase.instance kullanıyor.');
      expect(src.contains('SupabaseService'), isFalse,
          reason: '${f.path} SupabaseService kullanıyor.');
    }
  });

  // Negatif kontrol: dedektör gerçekten çalışıyor mu? Demo açıkken sunucu
  // geçidine uzanan çağrı ağa çıkmadan düşmeli VE iz bırakmalı — yoksa
  // yukarıdaki "ihlal listesi boş" iddiası hiçbir şey kanıtlamazdı.
  test('demo açıkken sunucu geçidi çağrıyı düşürür ve izini bırakır',
      () async {
    DemoModu.ac();
    addTearDown(DemoModu.kapat);
    await expectLater(
      SupabaseService.instance.fetchByUser(kDemoKullaniciId),
      throwsA(isA<DemoSunucuEngeli>()),
    );
    expect(DemoModu.ihlaller, hasLength(1));
    expect(DemoModu.ihlaller.single, contains('SupabaseService'));
  });

  test('gerçek akışta demo kapalı: bayrak yalnızca kabukla açılır', () {
    expect(DemoModu.aktif, isFalse);
    expect(DemoModu.yazmaKapisi('x'), isFalse);
  });
}
