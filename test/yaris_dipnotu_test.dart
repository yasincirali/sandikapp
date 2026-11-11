// Sıralama dipnotu (müşteri işi 10 Kas): görünen tek güven cümlesi +
// "Nasıl ölçülür?" satırı. 2026-11-11 (Ar-Ge #4): satır ⓘ ile aynı bilgi
// sayfasını (`_RoiInfoSheet`) açar; güven sözü orada ayrı blok.
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
import 'package:portfoy_takip/screens/siralama_screen.dart';

/// Yarış (leaderboard) ekranının taşma regresyonu.
///
/// Ekran 1.665 satır ve kartları private; `asset_card_overflow_test.dart`
/// ile aynı kalıp kullanılıyor: ekranı gerçek haliyle pump et, veriyi
/// ProviderScope override'larıyla besle. İç yapı değil dış davranış
/// doğrulanır — ekran ileride parçalanınca test yine geçmeli.
///
/// Ekranın iki ayrı hâli var ve ikisi de farklı yerleşim çiziyor:
///   - opt-in KAPALI → `_OptInPrompt` (katılım daveti)
///   - opt-in AÇIK   → sıralama kartları + hero kart
/// İkisi de test ediliyor.

const _uid = 'user-1';

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
  double qty = 100,
  double buy = 250.75,
  double current = 312.40,
}) =>
    Asset(
      id: '$ticker-$qty',
      userId: _uid,
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: buy,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: current,
      addedDate: DateTime(2026, 3, 14),
    );

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Çok Uzun Bir Kullanıcı Adı Soyadı',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;

  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

/// Gerçek notifier polling kurar ve Supabase init olmadığı için test
/// çıktısını hata loguyla doldurur — davranış değişmez, yalnızca gürültü.
class _FakePartners extends PartnersNotifier {
  _FakePartners(this._partners);
  final List<PartnerAccount> _partners;

  @override
  Future<List<PartnerAccount>> build() async => _partners;
}

PartnerAccount _partner(String id, String name) => PartnerAccount(
      user: AppUser(
        id: id,
        email: '$id@example.com',
        displayName: name,
        createdAt: DateTime(2026, 1, 1),
      ),
      isActive: true,
    );

Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  List<Asset> assets = const [],
  List<PartnerAccount> partners = const [],
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        portfolioProvider.overrideWith(() => _FakePortfolio(assets)),
        partnersProvider.overrideWith(() => _FakePartners(partners)),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        // Ayrı Yarış ekranı 2026-10-05'te silindi; aynı gövde Sıralama ›
        // Ortaklarım'da.
        home: SiralamaScreen(zirveRizaYukleyici: () async => true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'pref_leaderboard_opt_in': true});
    await initPreferencesCache();
  });

  testWidgets('ortaklı: kısa güven cümlesi görünür, ayrıntı bilgi sayfasında',
      (tester) async {
    await _pump(tester,
        assets: [_asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları')],
        partners: [_partner('p1', 'Ayşe')]);
    await _ortaklaraGec(tester);
    expect(find.byKey(const ValueKey('yaris_guven_cumlesi')), findsOneWidget);
    expect(find.text('Kimsenin varlık listesi görünmez.'), findsOneWidget);
    // Uzun dipnot artık listenin altında değil.
    expect(find.textContaining('para ekleme zamanı etkilemez'), findsNothing);

    final satir = find.byKey(const ValueKey('yaris_nasil_olculur'));
    expect(tester.getSize(satir).height, greaterThanOrEqualTo(44));
    await tester.tap(satir);
    await tester.pumpAndSettle();
    _tekBilgiSayfasi(guven: 'Kimsenin varlık listesi görünmez.');
  });

  // Ar-Ge 2026-11-11_1704 #4: ⓘ ve "Nasıl ölçülür?" aynı sayfayı açar;
  // eski ikinci sayfa (dipnotun üç paragrafı) yok.
  testWidgets('ⓘ ve "Nasıl ölçülür?" aynı bilgi sayfasını açar',
      (tester) async {
    await _pump(tester,
        assets: [_asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları')],
        partners: [_partner('p1', 'Ayşe')]);
    await _ortaklaraGec(tester);

    await tester.tap(find.byKey(const ValueKey('yaris_nasil_olculur')));
    await _yerles(tester);
    _tekBilgiSayfasi(guven: 'Kimsenin varlık listesi görünmez.');
    await tester.tap(find.bySemanticsLabel('Kapat'));
    await _yerles(tester);
    expect(find.byKey(const ValueKey('yaris_bilgi_guven')), findsNothing);

    await tester.tap(find.byTooltip('Getiri nasıl hesaplanıyor?'));
    await _yerles(tester);
    _tekBilgiSayfasi(guven: 'Kimsenin varlık listesi görünmez.');
  });
}

Future<void> _ortaklaraGec(WidgetTester tester) async {
  final ortaklar = find.text('Ortaklarım');
  if (ortaklar.evaluate().isNotEmpty) {
    await tester.tap(ortaklar.first);
    await _yerles(tester);
  }
}

/// Açık sayfa `_RoiInfoSheet`: başlığı, ölçüm blokları ve güven bloğu var;
/// eski "Nasıl ölçülür?" sayfasının tekrar eden ilk cümlesi yok.
void _tekBilgiSayfasi({required String guven}) {
  expect(find.text('Getiri nasıl hesaplanıyor?'), findsOneWidget);
  expect(find.text('Para eklemek sıralamayı değiştirmez'), findsOneWidget);
  expect(find.textContaining('en az'), findsOneWidget);
  expect(find.textContaining('Sıralama ise yalnız seçimlerini ölçer'),
      findsOneWidget);
  final blok = find.byKey(const ValueKey('yaris_bilgi_guven'));
  expect(blok, findsOneWidget);
  expect(find.descendant(of: blok, matching: find.text('Neler paylaşılmaz?')),
      findsOneWidget);
  expect(find.descendant(of: blok, matching: find.text(guven)), findsOneWidget);
  expect(find.textContaining('para ekleme zamanı etkilemez'), findsNothing);
  // Tek sayfa: başlığı "Nasıl ölçülür?" olan ikinci sayfa açılmaz.
  expect(find.text('Nasıl ölçülür?'), findsOneWidget);
}

/// pumpAndSettle yerine sabit adım: aynı dosyadaki ikinci testte ekranda
/// süren bir animasyon pumpAndSettle'ı zaman aşımına düşürüyor; 1 sn sheet
/// açılış/kapanış geçişine yeter.
Future<void> _yerles(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
