import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/ortak_paylasimi.dart';
import 'package:portfoy_takip/models/portfoy.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/ortak_paylasimi_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/portfoy_yonetimi_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ortak hangi portföyleri görür (0135). Asıl sınır sunucuda (RLS,
/// `ortak_portfoyu_gorur`); burada istemci eşi ([OrtakPaylasimi.gorur]),
/// seçim sayfası ve bayrak kapalıyken hiçbir yüzeyin çizilmediği kilitlenir.
const _uid = 'user-1';
const _ortakId = 'ortak-1';
const _a = 'pf-a';
const _b = 'pf-b';

final _ayse = AppUser(
  id: _ortakId,
  email: 'ayse@example.com',
  displayName: 'Ayşe Yılmaz',
  createdAt: DateTime(2026, 1, 1),
);

Asset _lot(String id, String ticker, {String? portfoy}) => Asset(
      id: id,
      userId: _uid,
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      currentPrice: 150,
      addedDate: DateTime(2026, 3, 14),
      portfoyId: portfoy,
    );

final _defter = [
  _lot('1', 'ASELS', portfoy: _a),
  _lot('2', 'TUPRS', portfoy: _b),
  _lot('3', 'THYAO'),
];

const _liste = [
  Portfoy(id: _a, userId: _uid, ad: 'Emeklilik', sira: 1),
  Portfoy(id: _b, userId: _uid, ad: 'Çocuk', sira: 2),
];

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: _uid,
        email: 'test@example.com',
        displayName: 'Test',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _defter, ownerId: _uid);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async =>
      [PartnerAccount(user: _ayse, isActive: true)];
}

class _SabitPortfoyler extends PortfoylerNotifier {
  @override
  Future<List<Portfoy>> build() async => _liste;
}

class _SahtePaylasimlar extends OrtakPaylasimlariNotifier {
  _SahtePaylasimlar(this.ilk);
  final List<OrtakPaylasimi> ilk;
  final kaydedilen = <OrtakPaylasimi>[];
  @override
  Future<List<OrtakPaylasimi>> build() async => ilk;
  @override
  Future<void> kaydet(OrtakPaylasimi p) async {
    kaydedilen.add(p);
    state = AsyncData([p]);
  }
}

List<Override> _ortak(_SahtePaylasimlar paylasimlar, {bool premium = true}) => [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(_FakePortfolio.new),
      partnersProvider.overrideWith(_FakePartners.new),
      portfoylerProvider.overrideWith(_SabitPortfoyler.new),
      ortakPaylasimlariProvider.overrideWith(() => paylasimlar),
      isPushAdminProvider.overrideWith((_) async => false),
      gelistiriciAnahtariSayilirProvider.overrideWithValue(false),
      magazaPremiumProvider.overrideWith((_) => premium),
      gecerliPremiumHakkiProvider.overrideWithValue(null),
    ];

Future<void> _yonetim(WidgetTester t, _SahtePaylasimlar p,
    {bool premium = true}) async {
  t.view.physicalSize = const Size(390 * 3, 1200 * 3);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: _ortak(p, premium: premium),
    child: MaterialApp(
        theme: ThemeData.dark(), home: const PortfoyYonetimiScreen()),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });
  tearDown(() => RemoteConfigService.testAcik = {});

  group('OrtakPaylasimi (RLS ortak_portfoyu_gorur eşi)', () {
    test('hepsi: her portföy, Ana dahil', () {
      const p = OrtakPaylasimi.hepsi(sahipId: _uid, ortakId: _ortakId);
      expect(p.gorur(null), isTrue);
      expect(p.gorur(_a), isTrue);
      expect(p.gorur('sonradan-acilan'), isTrue);
      expect(p.kisitli, isFalse);
    });

    test('seçili: yalnız Ana ve seçilenler; yeni portföy gizli başlar', () {
      const p = OrtakPaylasimi(
          sahipId: _uid,
          ortakId: _ortakId,
          tumu: false,
          ana: true,
          portfoyIdler: {_a});
      expect(p.gorur(null), isTrue);
      expect(p.gorur(_a), isTrue);
      expect(p.gorur(_b), isFalse);
      expect(p.gorur('sonradan-acilan'), isFalse);
      expect(p.gorunenSayisi([_a, _b]), 2);
      expect(p.kisitli, isTrue);
    });

    test('sunucu satırı gidiş-dönüş; dizi kararlı sırada yazılır', () {
      const p = OrtakPaylasimi(
          sahipId: _uid,
          ortakId: _ortakId,
          tumu: false,
          ana: false,
          portfoyIdler: {_b, _a});
      final m = p.toSupabase();
      expect(m['portfoy_idler'], [_a, _b]);
      final geri = OrtakPaylasimi.fromSupabase(m);
      expect(geri.tumu, isFalse);
      expect(geri.ana, isFalse);
      expect(geri.portfoyIdler, {_a, _b});
    });

    test('eksik sütunlu satır (null) = hepsi, güvenli olmayan yöne düşmez', () {
      final p =
          OrtakPaylasimi.fromSupabase({'sahip_id': _uid, 'ortak_id': _ortakId});
      expect(p.tumu, isTrue);
    });
  });

  group('Portföyler ekranı', () {
    testWidgets('bayrak kapalı: ortak satırı ve durum yazısı yok', (t) async {
      await _yonetim(t, _SahtePaylasimlar(const []));
      expect(find.text('ORTAĞIN NE GÖRÜR'), findsNothing);
      expect(find.textContaining('görüyor'), findsNothing);
    });

    testWidgets('bayrak açık, tek ortak: satır başına görüyor / görmüyor',
        (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      await _yonetim(
          t,
          _SahtePaylasimlar(const [
            OrtakPaylasimi(
                sahipId: _uid,
                ortakId: _ortakId,
                tumu: false,
                ana: true,
                portfoyIdler: {_a}),
          ]));
      expect(find.text('ORTAĞIN NE GÖRÜR'), findsOneWidget);
      expect(find.text('Ayşe görüyor'), findsNWidgets(2),
          reason: 'Ana ve Emeklilik');
      expect(find.text('Ayşe görmüyor'), findsOneWidget, reason: 'Çocuk');
      expect(find.text('2 / 3 portföy'), findsOneWidget);
    });

    testWidgets('seçim sayfası: Seçtiklerim → Çocuk kapat → kaydet', (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      final p = _SahtePaylasimlar(const []);
      await _yonetim(t, p);
      expect(find.text('Hepsi'), findsOneWidget, reason: 'satır yok = hepsi');

      await t
          .tap(find.byKey(const ValueKey('ortak-paylasim-satiri-$_ortakId')));
      await t.pumpAndSettle();
      expect(find.text('Ayşe neyi görsün?'), findsOneWidget);

      await t.tap(find.text('Seçtiklerim'));
      await t.pump();
      await t.tap(find.descendant(
          of: find.byKey(const ValueKey('ortak-paylasim-$_b')),
          matching: find.byType(Switch)));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('ortak-paylasim-kaydet')));
      await t.pumpAndSettle();

      expect(p.kaydedilen, hasLength(1));
      final k = p.kaydedilen.single;
      expect(k.sahipId, _uid);
      expect(k.ortakId, _ortakId);
      expect(k.tumu, isFalse);
      expect(k.ana, isTrue);
      expect(k.portfoyIdler, {_a});
      expect(find.text('2 / 3 portföy'), findsOneWidget);
    });
    testWidgets('Premium yokken satır kilitli: değer görünür, sayfa açılmaz',
        (t) async {
      RemoteConfigService.testAcik = {'coklu_portfoy', 'paywall_enabled'};
      await _yonetim(
          t,
          _SahtePaylasimlar(const [
            OrtakPaylasimi(
                sahipId: _uid, ortakId: _ortakId, tumu: false, ana: true),
          ]),
          premium: false);
      final satir =
          find.byKey(const ValueKey('ortak-paylasim-satiri-$_ortakId'));
      expect(satir, findsOneWidget,
          reason: 'mevcut seçim görünür; Premium biten kullanıcı neyin '
              'gizli olduğunu bilmeli');
      expect(
          find.descendant(
              of: satir, matching: find.byIcon(Icons.lock_outline_rounded)),
          findsOneWidget);
      expect(find.text('1 / 3 portföy'), findsOneWidget);
    });
  });
}
