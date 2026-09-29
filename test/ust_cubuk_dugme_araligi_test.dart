import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/home_screen.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/screens/profile_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Üst çubuk düğmeleri — dört sekmede AYNI kabuk ve AYNI aralık.
///
/// Kullanıcı bildirimi (2026-09-28, üç ekran görüntüsüyle): "sağ üstteki
/// chip'ler standart aralıkta olmalı, farklı mesafe ya da hizasızlık
/// olmamalı, her ekranda aynı." O gün ölçülen hâl: Portföy 8 ve 4,
/// Ana 8, Profil 8, Performans 6 (ve yarış ikonu kutusuz). Bu test dört
/// ekranın başlık satırındaki 44pt kutuları bulur; aralık `SandikSpace.sm`,
/// üst kenarlar eşit, en sağdaki kutu ekran kenarına `screenH` kadar.
///
/// Kutular türle değil ÖLÇÜYLE bulunur (44×44, başlık satırında): her
/// ekran kendi düğme sınıfını yazıyor ve hepsini tek tipe indirmek bu
/// testin işi değil — ölçü kuralı yeterli, sınıf adı değişince kırılmaz.

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

const double _w = 375;

Future<void> _pump(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(_w * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
      signalProvider.overrideWith(_FakeSignals.new),
    ],
    // Sekmeler uygulamada `MainNavigationScreen`'in Scaffold'u altında;
    // Profil'deki TextField Material ister.
    child: MaterialApp(
        home: Material(type: MaterialType.transparency, child: ekran)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Başlık satırındaki 44×44 kutular, soldan sağa.
List<Rect> _basilikKutulari(WidgetTester tester) {
  final kutular = <Rect>[];
  for (final e in find.byType(Container).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final s = ro.size;
    if ((s.width - SandikTouch.min).abs() > 0.5 ||
        (s.height - SandikTouch.min).abs() > 0.5) {
      continue;
    }
    final r = tester.getRect(find.byWidget(e.widget));
    if (r.top > 70) continue; // başlık satırı dışı
    if (kutular.any((k) => (k.left - r.left).abs() < 0.5)) continue; // iç içe
    kutular.add(r);
  }
  kutular.sort((a, b) => a.left.compareTo(b.left));
  return kutular;
}

/// Başlık bloğunun altındaki ilk görünür kutunun üst kenarı: kart, kabuk
/// ya da şerit (`Container`/`DecoratedBox`). 44×44 dokunma kutuları
/// sayılmaz — görünen içerik onların İÇİNDEKİ kutudur (ör. piyasa
/// şeridinin 30pt bandı, 44pt dokunma alanının üstüne yaslı).
double? _ilkIcerikUstu(WidgetTester tester, double blokAlti) {
  double? enUst;
  for (final t in [Container, DecoratedBox]) {
    for (final el in find.byType(t).evaluate()) {
      final ro = el.renderObject;
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      if ((ro.size.width - SandikTouch.min).abs() < 0.5 &&
          (ro.size.height - SandikTouch.min).abs() < 0.5) {
        continue;
      }
      final r = tester.getRect(find.byWidget(el.widget));
      if (r.top < blokAlti - 0.5) continue;
      if (enUst == null || r.top < enUst) enUst = r.top;
    }
  }
  return enUst;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    // Ana ekran açılışta günlük yazar; Supabase yok, sessiz kalsın.
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  // Ekran → (widget, başlık metni). Ana sayfanın başlığı kelime işareti
  // "sandık"; 2026-09-28'e kadar logolu/çerçeveli rozetti ve metin öteki
  // sekmelerden 14pt içeriden başlıyordu (kullanıcı: "başlık bloğu dört
  // sekmede aynı, Portföy'deki değerlerle").
  final ekranlar = <String, (Widget, String)>{
    'Ana': (const HomeScreen(), 'sandık'),
    'Portföy': (const PortfolioScreen(), 'Portföy'),
    'Performans': (const PortfolioPerformanceScreen(), 'Performans'),
    'Profil': (const ProfileScreen(), 'Profil'),
  };

  for (final e in ekranlar.entries) {
    testWidgets('${e.key}: başlık düğmeleri eşit aralıkta ve hizalı',
        (tester) async {
      await _pump(tester, e.value.$1);
      final kutular = _basilikKutulari(tester);
      expect(kutular, isNotEmpty, reason: '${e.key}: başlıkta 44pt kutu yok');

      // Başlık metni: ekran kenarından `screenH`, düğme satırıyla aynı
      // eksende, dört sekmede aynı yazı boyu (headlineMedium).
      final baslik = tester.getRect(find.text(e.value.$2).first);
      final kenarBaslik =
          SandikSpace.screenH(tester.element(find.byType(MaterialApp)));
      expect((baslik.left - kenarBaslik).abs(), lessThan(0.5),
          reason: '${e.key}: başlık sol kenarı ${baslik.left}, beklenen $kenarBaslik');
      expect((baslik.center.dy - kutular.first.center.dy).abs(), lessThan(0.5),
          reason: '${e.key}: başlık düğmelerle aynı eksende değil');
      final stil = tester.widget<Text>(find.text(e.value.$2).first).style;
      expect(stil?.fontSize,
          tester.element(find.byType(MaterialApp)).t.headlineMedium?.fontSize,
          reason: '${e.key}: başlık headlineMedium değil');

      // İlk içerik başlık bloğunun hemen altında başlar: düğme satırının
      // altı + `xs` (bloğun alt dolgusu). 2026-09-28'de Performans 12,
      // Profil 4, Ana 7 pt daha aşağıdan başlıyordu.
      final blokAlti = kutular.first.bottom + SandikSpace.xs;
      final ilk = _ilkIcerikUstu(tester, blokAlti);
      expect(ilk, isNotNull, reason: '${e.key}: başlık altında içerik yok');
      expect((ilk! - blokAlti).abs(), lessThan(0.5),
          reason: '${e.key}: ilk içerik $ilk, beklenen $blokAlti');

      // Hepsi aynı satırda.
      final ust = kutular.first.top;
      for (final k in kutular) {
        expect((k.top - ust).abs(), lessThan(0.5),
            reason: '${e.key}: kutu üst kenarları farklı ($kutular)');
      }
      // Ardışık kutular arası `SandikSpace.sm`.
      for (var i = 1; i < kutular.length; i++) {
        final aralik = kutular[i].left - kutular[i - 1].right;
        expect((aralik - SandikSpace.sm).abs(), lessThan(0.5),
            reason: '${e.key}: $i. aralık $aralik, beklenen ${SandikSpace.sm}');
      }
      // En sağdaki kutu ekran kenarına `screenH` kadar (kenar hizası).
      final kenar = SandikSpace.screenH(tester.element(find.byType(MaterialApp)));
      expect((_w - kutular.last.right - kenar).abs(), lessThan(0.5),
          reason: '${e.key}: sağ kenar hizası ${_w - kutular.last.right}, beklenen $kenar');
      expect(tester.takeException(), isNull);
    });
  }
}
