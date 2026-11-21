// Portföy turu 2026-11-21: (1) Sattıkların listesi özet kapanınca yeniden
// açılır; (2) başa baş kilidi tam genişlik; (4) açık pozisyon yok metni
// kapanmış pozisyona göre; (5) Premium bitince kayıtlı portföy hedefi için
// kilit satırı, hedef yoksa hiçbir şey.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/gorunum_kapsami.dart' show PortfoySecimi;
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/portfoy_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart'
    show premiumOzellikleriGorunurProvider;
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/widgets/kapanis_ozeti_sheet.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:portfoy_takip/widgets/portfoy_hedef_satiri.dart';
import 'package:portfoy_takip/widgets/sattiklarin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

const _uid = 'user-1';

Asset _lot(String id, String t, AssetKind k, DateTime d, {double? satis}) =>
    Asset(
      id: id,
      userId: _uid,
      name: t,
      ticker: t,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: true,
      kind: k,
      sellPrice: satis,
      currentPrice: 100,
      addedDate: d,
      createdAt: d,
    );

List<Asset> _kapali(String t) => [
      _lot('${t}a', t, AssetKind.buy, DateTime(2026, 2, 1)),
      _lot('${t}s', t, AssetKind.sell, DateTime(2026, 5, 1), satis: 130),
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
  _FakePortfolio(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, usdTry: 42, eurTry: 46, gbpTry: 54);
}

class _FakePartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];
}

class _SabitHedef extends KapsamHedefiNotifier {
  _SabitHedef(this._v);
  final int _v;
  @override
  int build(String arg) => _v;
}

List<Override> _ortak(List<Asset> varliklar) => [
      authProvider.overrideWith(_FakeAuth.new),
      portfolioProvider.overrideWith(() => _FakePortfolio(varliklar)),
      partnersProvider.overrideWith(_FakePartners.new),
      premiumOzellikleriGorunurProvider.overrideWithValue(true),
      premiumKilitliProvider.overrideWithValue(false),
    ];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('1: özet kapanınca Sattıkların listesi yeniden açılır',
      (t) async {
    t.view.physicalSize = const Size(390 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: _ortak([..._kapali('THYAO'), ..._kapali('KCHOL')]),
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Consumer(
          builder: (ctx, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showSattiklarinListesi(ctx, tutarGizli: () => false),
              child: const Text('ac'),
            ),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('ac'));
    await t.pumpAndSettle();
    for (final tk in ['THYAO', 'KCHOL']) {
      expect(find.byType(SattiklarinSayfasi), findsOneWidget);
      await t.tap(find.byKey(ValueKey('sattigin_$_uid|hisse|$tk|TRY')));
      await t.pumpAndSettle();
      expect(find.byType(KapanisOzetiSayfasi), findsOneWidget);
      // Özeti kapat (sayfa dışına dokun / geri): liste geri gelmeli.
      await t.tapAt(const Offset(195, 20));
      await t.pumpAndSettle();
    }
    expect(find.byType(SattiklarinSayfasi), findsOneWidget,
        reason: 'ikinci özetten sonra da liste açık');
  });

  Future<void> portfoyAc(WidgetTester t, List<Asset> v) async {
    t.view.physicalSize = const Size(390 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: _ortak(v),
      child: MaterialApp(theme: ThemeData.dark(), home: const PortfolioScreen()),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
  }

  testWidgets('4: hepsi satılmış: "Şu an açık pozisyonun yok"', (t) async {
    await portfoyAc(t, _kapali('THYAO'));
    expect(find.text('Şu an açık pozisyonun yok'), findsOneWidget);
    expect(find.text('Henüz varlık eklenmemiş'), findsNothing);
  });

  testWidgets('4: hiç işlem yok: "Henüz varlık eklenmemiş"', (t) async {
    await portfoyAc(t, const []);
    expect(find.text('Henüz varlık eklenmemiş'), findsOneWidget);
    expect(find.text('Şu an açık pozisyonun yok'), findsNothing);
  });

  group('5: kayıtlı portföy hedefi kilidi', () {
    Future<void> hedefAc(WidgetTester t,
        {required OzellikDurumu durum, required int hedef}) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          portfoyKapsamiProvider
              .overrideWithValue((secim: PortfoySecimi.ana, bilinen: <String>{})),
          hedefTarihiDurumuProvider.overrideWithValue(durum),
          kapsamHedefiProvider.overrideWith(() => _SabitHedef(hedef)),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(body: PortfoyHedefSatiri())),
      ));
      await t.pump();
    }

    testWidgets('kilitli + kayıtlı hedef: kilit satırı, tutar yok', (t) async {
      await hedefAc(t, durum: OzellikDurumu.kilitli, hedef: 3000);
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.textContaining('hedefin kayıtlı'), findsOneWidget);
      expect(find.textContaining('3.000'), findsNothing);
    });

    testWidgets('kilitli ama hedef yok: hiçbir şey', (t) async {
      await hedefAc(t, durum: OzellikDurumu.kilitli, hedef: 0);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('gizli (paywall kapalı): hiçbir şey', (t) async {
      await hedefAc(t, durum: OzellikDurumu.gizli, hedef: 3000);
      expect(find.byType(KilitSatiri), findsNothing);
    });
  });

  test('2: başa baş kilidi tam genişlik Column, açıkken Row korunur', () {
    final k = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    final i = k.indexOf('basaBas && ref.watch(premiumKilitliProvider)');
    expect(i, greaterThan(0));
    final blok = k.substring(i, i + 700);
    expect(blok, contains('Column('));
    expect(blok, contains("BasaBasSatiri(oran: basaBasOrani!"));
    expect(k, contains('if (temettuVar) Expanded(child: temettuSatiri),'),
        reason: 'açık hâlin iki kolonlu Row\'u dokunulmadan kalır');
  });
}
