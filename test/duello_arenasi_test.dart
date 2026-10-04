import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/leaderboard_screen.dart';
import 'package:portfoy_takip/screens/siralama_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/lider_seridi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/duello_arenasi.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';
import 'package:portfoy_takip/widgets/yaris_sahnesi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yarış "Düello arenası" (kullanıcı seçimi 2026-10-04, bayrak
/// `yaris_duello_arena`, varsayılan KAPALI).
///
/// Kilitlenenler:
///   · tam 2 kişi → arena (ortağın verisi yoksa da: "Henüz veri yok",
///     halat ortada); 3+ kişi → eski kürsü + liste; bayrak kapalı → eski;
///   · dönem değişince değerler yeni döneme akar, lider değişince taç karşı
///     tarafa geçer;
///   · animasyon bitince boşta kare istenmez (ticker durur);
///   · hareketi azalt: son hâl ilk karede, kıvılcım yok;
///   · 320/390 pt ve büyük yazıda taşma yok;
///   · ekran: eski Yarış ve Sıralama › Ortaklarım aynı arenayı çizer.
YarisKatilimci _k(String id, double? roi,
        {bool ben = false, String? ad, int renk = 1}) =>
    YarisKatilimci(
      id: id,
      ad: ad ?? id,
      ben: ben,
      roi: roi,
      renkSirasi: ben ? 0 : renk,
    );

List<YarisKatilimci> _sirala(List<YarisKatilimci> k) => [...k]..sort((a, b) {
    if (a.roi == null) return 1;
    if (b.roi == null) return -1;
    return b.roi!.compareTo(a.roi!);
  });

Future<void> _pump(
  WidgetTester tester,
  List<YarisKatilimci> k, {
  int yenileme = 1,
  int donem = 30,
  double genislik = 390,
  double olcek = 1,
  bool hareketsiz = false,
  bool arena = true,
  LiderSeridi? serit,
  Brightness parlaklik = Brightness.dark,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: parlaklik == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(genislik, 1400),
        textScaler: TextScaler.linear(olcek),
        disableAnimations: hareketsiz,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: YarisSahnesi(
            katilimcilar: _sirala(k),
            yenileme: yenileme,
            // Canlı başlığın saniyelik etiket tiki boşta kare ölçümünü
            // bulandırmasın: zaman damgası yok.
            sonGuncelleme: null,
            donemGun: donem,
            arena: arena,
            liderSeridi: serit,
          ),
        ),
      ),
    ),
  ));
}

/// Taç kimin başında: ekranın sol yarısı sen, sağ yarısı ortak.
String? _tacTarafi(WidgetTester tester, {double genislik = 390}) {
  final f = find.byType(YarisTaci);
  if (f.evaluate().isEmpty) return null;
  expect(f, findsOneWidget, reason: 'aynı anda tek taç');
  return tester.getCenter(f).dx < genislik / 2 ? 'sen' : 'ortak';
}

Finder _kivilcim() => find.byWidgetPredicate((w) =>
    w is CustomPaint &&
    w.painter.runtimeType.toString() == '_KivilcimBoyaci');

LiderSeridi _serit(int gun, List<SeritLider> c) => LiderSeridi(
      cubuklar: c,
      baslangic: DateTime(2026, 9, 28),
      aylik: gun > 31,
      donemGun: gun,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);
  tearDown(() => RemoteConfigService.testAcik = {});

  group('vitrin kuralı', () {
    test('arena açık: tam 2 kişi HER ZAMAN arena (veri yoksa da)', () {
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', 2)], arena: true),
          YarisVitrini.arena);
      expect(
          yarisVitrini([_k('sen', 1, ben: true), _k('a', null)], arena: true),
          YarisVitrini.arena);
    });
    test('arena açık: 3 kişi eski kürsü', () {
      expect(
          yarisVitrini([_k('sen', 1, ben: true), _k('a', 2), _k('b', 3)],
              arena: true),
          YarisVitrini.kursu);
    });
    test('arena kapalı: eski kural birebir', () {
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', 2)]),
          YarisVitrini.duello);
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', null)]),
          YarisVitrini.yok);
    });
  });

  group('halat', () {
    test('ölçek dönem başına: hafta 4, ay 8, yıl 20 puan', () {
      expect(arenaOlcegi(7), 4);
      expect(arenaOlcegi(30), 8);
      expect(arenaOlcegi(365), 20);
      // 2 puan önde: haftada çeyrek, yılda yirmide bir kayar.
      expect(arenaHalatOrani(3, 1, 7), closeTo(0.75, 1e-9));
      expect(arenaHalatOrani(3, 1, 365), closeTo(0.55, 1e-9));
    });
    test('uca yapışmaz; veri yoksa ortada', () {
      expect(arenaHalatOrani(50, -50, 7), closeTo(0.92, 1e-9));
      expect(arenaHalatOrani(-50, 50, 7), closeTo(0.08, 1e-9));
      expect(arenaHalatOrani(3, null, 7), 0.5);
    });
    test('lider: kıyas yoksa kimse', () {
      expect(arenaLideri(1, 2), 1);
      expect(arenaLideri(2, 1), 0);
      expect(arenaLideri(null, 1), isNull);
    });
  });

  testWidgets('2 kişi: arena, VS, liste yok, fark cümlesi', (tester) async {
    await _pump(tester, [
      _k('sen', 6.4, ben: true, ad: 'Deneme'),
      _k('ayse', 4.1, ad: 'Ayşe Nur'),
    ]);
    // Giriş sırasında cümle "ölçülüyor".
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Fark ölçülüyor…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(DuelloArenasi), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('Sen'), findsOneWidget);
    expect(find.text('Ayşe'), findsOneWidget);
    expect(find.text('+%6,4'), findsOneWidget);
    expect(find.text('+%4,1'), findsOneWidget);
    expect(find.text('2,3'), findsOneWidget, reason: 'halat pili');
    expect(find.text("Ayşe'nin 2,3 puan önündesin"), findsOneWidget);
    // Canlı liste YOK — "SEN" etiketi ve sıra madalyası liste satırında.
    expect(find.text('SEN'), findsNothing);
    expect(_tacTarafi(tester), 'sen');
  });

  testWidgets('ortak gerideyse: "… önde · yetişebilirsin"', (tester) async {
    await _pump(tester, [
      _k('sen', 1.2, ben: true),
      _k('ayse', 1.8, ad: 'Ayşe'),
    ], donem: 7);
    await tester.pumpAndSettle();
    expect(find.text('Ayşe 0,6 puan önde · yetişebilirsin'), findsOneWidget);
    expect(_tacTarafi(tester), 'ortak');
  });

  testWidgets('ortak verisi yok: arena yine çizilir, "Henüz veri yok"',
      (tester) async {
    await _pump(tester, [
      _k('sen', 3.2, ben: true),
      _k('ayse', null, ad: 'Ayşe'),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(DuelloArenasi), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);
    expect(find.text('Henüz veri yok'), findsOneWidget);
    expect(find.text('Getiriler ölçülünce düello başlar'), findsOneWidget);
    expect(find.text('+%3,2'), findsOneWidget);
    expect(_tacTarafi(tester), isNull, reason: 'kıyas yokken taç yok');
  });

  testWidgets('3 kişi: arena değil, eski kürsü + liste', (tester) async {
    await _pump(tester, [
      _k('sen', 4.1, ben: true),
      _k('ayse', 6.3, ad: 'Ayşe'),
      _k('mert', 2.2, ad: 'Mert', renk: 2),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(DuelloArenasi), findsNothing);
    expect(find.text('VS'), findsNothing);
    expect(find.text('Lidere 2,2 puan'), findsOneWidget);
  });

  testWidgets('bayrak kapalı (arena: false): eski düello kartı', (tester) async {
    await _pump(tester, [_k('sen', -2.7, ben: true), _k('ayse', -3.2)],
        arena: false);
    await tester.pumpAndSettle();
    expect(find.byType(DuelloArenasi), findsNothing);
    expect(find.text('SEN'), findsOneWidget, reason: 'eski liste duruyor');
  });

  testWidgets('dönem değişince değerler yeni döneme akar, taç el değiştirir',
      (tester) async {
    await _pump(tester, [_k('sen', 1.2, ben: true), _k('ayse', 1.8)],
        donem: 7);
    await tester.pumpAndSettle();
    expect(_tacTarafi(tester), 'ortak');

    await _pump(tester, [_k('sen', 6.4, ben: true), _k('ayse', 4.1)],
        donem: 30, yenileme: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Ortada: sayaç yolda, cümle ölçüyor.
    expect(find.text('+%6,4'), findsNothing);
    expect(find.text('Fark ölçülüyor…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('+%6,4'), findsOneWidget);
    expect(find.text('+%4,1'), findsOneWidget);
    expect(_tacTarafi(tester), 'sen');
  });

  testWidgets('canlı yenileme (aynı dönem, aynı lider): ölçülüyor yazmaz',
      (tester) async {
    await _pump(tester, [_k('sen', 6.4, ben: true), _k('ayse', 4.1)]);
    await tester.pumpAndSettle();
    await _pump(tester, [_k('sen', 6.5, ben: true), _k('ayse', 4.1)],
        yenileme: 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fark ölçülüyor…'), findsNothing);
    expect(_kivilcim(), findsNothing, reason: 'lider aynı: kutlama yok');
    await tester.pumpAndSettle();
    expect(find.text('+%6,5'), findsOneWidget);
  });

  testWidgets('animasyon bitince boşta kare yok (ticker durur)',
      (tester) async {
    await _pump(
      tester,
      [_k('sen', 6.4, ben: true), _k('ayse', 4.1)],
      serit: _serit(30, [SeritLider.ben, SeritLider.rakip, SeritLider.ben]),
    );
    // Giriş ~2,6 sn; kare kare ilerlet, sonra boşta kare istenmemeli.
    // Bu sırada her karede YENİDEN KURULAN widget'ları say: yalnız hareketli
    // yapraklar (AnimatedBuilder'lar) kurulmalı — arena, avatar, şerit
    // kartı ilk karedeki hâlleriyle kalır (yerleşim her karede baştan
    // hesaplanmaz).
    await tester.pump();
    final kurulan = <String, int>{};
    debugOnRebuildDirtyWidget = (e, _) {
      final ad = e.widget.runtimeType.toString();
      kurulan[ad] = (kurulan[ad] ?? 0) + 1;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    var kare = 0;
    while (tester.binding.hasScheduledFrame && kare < 400) {
      await tester.pump(const Duration(milliseconds: 16));
      kare++;
    }
    debugOnRebuildDirtyWidget = null;
    expect(kare, greaterThan(100), reason: 'giriş gerçekten oynadı');
    expect(kurulan['DuelloArenasi'] ?? 0, 0);
    expect(kurulan['LiderSeridiKarti'] ?? 0, 0);
    expect(kurulan['_VsRozeti'] ?? 0, 0);
    // Kare başına kurulan widget sayısı küçük ve sabit: taç ×2, sayaç ×2,
    // halat dolgusu, fark pili (+ cümle eşiğinde bir kez). Şerit ve
    // kıvılcım boyacı; kurulum değil boyama.
    final toplam = kurulan.values.fold<int>(0, (a, b) => a + b);
    // Ölçüm (2026-10-04): 162 kare, kare başına 11 kurulum — 6
    // AnimatedBuilder, 3 Text (iki sayaç + pil), pil kabuğu.
    expect(toplam / kare, lessThan(12), reason: '$kurulan');
    expect(kare, lessThan(400), reason: 'sonsuz döngü yok');
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('hareketi azalt: son hâl ilk karede, kıvılcım yok',
      (tester) async {
    await _pump(tester, [_k('sen', 6.4, ben: true), _k('ayse', 4.1, ad: 'Ayşe')],
        hareketsiz: true,
        serit: _serit(30, [SeritLider.ben, SeritLider.rakip]));
    await tester.pump();
    expect(find.text('+%6,4'), findsOneWidget);
    expect(find.text("Ayşe'nin 2,3 puan önündesin"), findsOneWidget);
    expect(_kivilcim(), findsNothing);
    expect(_tacTarafi(tester), 'sen');
    // Dönem değişimi de anında.
    await _pump(tester, [_k('sen', 1.2, ben: true), _k('ayse', 1.8)],
        donem: 7, yenileme: 2, hareketsiz: true);
    await tester.pump();
    expect(find.text('+%1,2'), findsOneWidget);
    expect(_tacTarafi(tester), 'ortak');
    expect(_kivilcim(), findsNothing);
  });

  testWidgets('lider şeridi: başlık, yer değişimi, Bugün; dönem uymuyorsa yok',
      (tester) async {
    await _pump(
      tester,
      [_k('sen', 6.4, ben: true), _k('ayse', 4.1)],
      serit: _serit(30, [
        SeritLider.ben,
        SeritLider.rakip,
        SeritLider.berabere,
        SeritLider.ben,
        SeritLider.bilinmiyor,
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LiderSeridiKarti), findsOneWidget);
    expect(find.text('Gün gün önde olan'), findsOneWidget);
    expect(find.text('2 kez yer değişti'), findsOneWidget);
    expect(find.text('Bugün'), findsOneWidget);

    // Eski dönemin şeridi yeni dönemin arenasının altında kalmaz.
    await _pump(tester, [_k('sen', 6.4, ben: true), _k('ayse', 4.1)],
        donem: 7, serit: _serit(30, [SeritLider.ben, SeritLider.rakip]));
    await tester.pumpAndSettle();
    expect(find.byType(LiderSeridiKarti), findsNothing);

    // Yıl: ay ay.
    await _pump(tester, [_k('sen', 6.4, ben: true), _k('ayse', 4.1)],
        donem: 365,
        serit: _serit(365, [SeritLider.ben, SeritLider.ben]));
    await tester.pumpAndSettle();
    expect(find.text('Ay ay önde olan'), findsOneWidget);
    expect(find.text('Yer hiç değişmedi'), findsOneWidget);
  });

  group('taşma', () {
    final uzun = [
      _k('sen', 123.4, ben: true, ad: 'Çok Uzun Bir Kullanıcı Adı Soyadı'),
      _k('p1', -88.8, ad: 'Mehmetemincanberkayoğlu Karahanoğlu'),
    ];
    final serit = _serit(365, [
      for (var i = 0; i < 12; i++) i.isEven ? SeritLider.ben : SeritLider.rakip
    ]);
    for (final (w, o) in [
      (320.0, 1.0),
      (320.0, 1.6),
      (320.0, 2.0),
      (390.0, 1.0),
      (390.0, 2.0),
    ]) {
      testWidgets('${w.toInt()}pt × $o', (tester) async {
        await _pump(tester, uzun,
            genislik: w, olcek: o, donem: 365, serit: serit);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _pump(tester, [uzun.first, _k('p1', null, ad: 'Mehmet')],
            genislik: w, olcek: o, parlaklik: Brightness.light);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('ekran', () {
    Future<void> ekran(WidgetTester tester, Widget home,
        {required int ortak}) async {
      SharedPreferences.setMockInitialValues({'pref_leaderboard_opt_in': true});
      await initPreferencesCache();
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          portfolioProvider.overrideWith(_FakePortfolio.new),
          partnersProvider.overrideWith(() => _FakePartners([
                for (var i = 0; i < ortak; i++)
                  _ortak('p$i', i == 0 ? 'Ayşe Yılmaz' : 'Mehmet Demir'),
              ])),
          allPartnerAssetsProvider.overrideWith(_FakePartnerAssets.new),
        ],
        child: MaterialApp(theme: ThemeData.dark(), home: home),
      ));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('eski Yarış, bayrak açık, tek ortak (verisi yok) → arena',
        (tester) async {
      RemoteConfigService.testAcik = {'yaris_duello_arena'};
      await ekran(tester, const LeaderboardScreen(), ortak: 1);
      expect(find.byType(DuelloArenasi), findsOneWidget);
      expect(find.text('Henüz veri yok'), findsNWidgets(2));
      // Seçici: kayan hap (ortak segment kontrolü), 1H · 1A · 1Y.
      expect(find.byType(SandikSegment), findsOneWidget);
      expect(find.text('1A'), findsOneWidget);
      expect(find.text('30G'), findsNothing);
    });

    testWidgets('eski Yarış, bayrak kapalı → birebir eski', (tester) async {
      await ekran(tester, const LeaderboardScreen(), ortak: 1);
      expect(find.byType(DuelloArenasi), findsNothing);
      expect(find.byType(SandikSegment), findsNothing);
      expect(find.text('30G'), findsOneWidget);
    });

    testWidgets('iki ortak (3 kişi) → arena yok', (tester) async {
      RemoteConfigService.testAcik = {'yaris_duello_arena'};
      await ekran(tester, const LeaderboardScreen(), ortak: 2);
      expect(find.byType(DuelloArenasi), findsNothing);
    });

    testWidgets('Sıralama › Ortaklarım aynı arenayı çizer', (tester) async {
      RemoteConfigService.testAcik = {
        'yaris_duello_arena',
        'siralama_tek_sayfa',
      };
      await ekran(
          tester, SiralamaScreen(zirveRizaYukleyici: () async => true),
          ortak: 1);
      expect(find.byType(DuelloArenasi), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _FakePartners extends PartnersNotifier {
  _FakePartners(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _FakePartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

PartnerAccount _ortak(String id, String ad) => PartnerAccount(
      user: AppUser(
          id: id,
          email: '$id@example.com',
          displayName: ad,
          createdAt: DateTime(2026, 1, 1)),
      isActive: true,
    );
