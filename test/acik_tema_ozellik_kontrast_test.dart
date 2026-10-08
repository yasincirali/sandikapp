import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/sozlesme_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/siralama_screen.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/mevduat_vade_seridi.dart';
import 'package:portfoy_takip/widgets/sozlesme_karti.dart';
import 'package:portfoy_takip/widgets/yaris_sahnesi.dart';
import 'package:portfoy_takip/widgets/zirve_cetveli.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kontrast_denetimi.dart';

/// Açık temada hiç gözle görülmemiş özellik yüzeyleri — Sıralama (yarış +
/// zirve) ve mevduat/BES (TECHNICAL_DEBT "Light mode", 2026-10-08). Her
/// metin arkasındaki gerçek zemine karşı AA. Ekran listesi
/// `acik_tema_ekran_kontrast_test` ile aynı denetimi kullanır.

class _Auth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => AppUser(
        id: 'u1',
        email: 'test@example.com',
        displayName: 'Deneme',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _Portfoy extends PortfolioNotifier {
  _Portfoy([this.lotlar = const <Asset>[]]);
  final List<Asset> lotlar;
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: lotlar, usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _Ortaklar extends PartnersNotifier {
  _Ortaklar(this._liste);
  final List<PartnerAccount> _liste;
  @override
  Future<List<PartnerAccount>> build() async => _liste;
}

class _OrtakVarliklari extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};
}

class _Sozlesmeler extends SozlesmeNotifier {
  _Sozlesmeler(this.durum);
  final SozlesmeState durum;
  @override
  Future<SozlesmeState> build() async => durum;
}

class _FiyatYok implements AddAssetPriceLookup {
  const _FiyatYok();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

PartnerAccount _ortak(String id, String ad) => PartnerAccount(
      user: AppUser(
          id: id,
          email: '$id@example.com',
          displayName: ad,
          createdAt: DateTime(2026, 1, 1)),
      isActive: true,
    );

// ── Mevduat / BES verisi (sozlesme_karti_test ile aynı kurgu) ──────────────
final _bugun = DateTime.now();
final _gun = DateTime(_bugun.year, _bugun.month, _bugun.day);
const _mid = 'm-1';
const _bid = 'b-1';
final _mevduat = Sozlesme(
    id: _mid,
    userId: 'u',
    tur: SozlesmeTuru.mevduat,
    kurum: 'Enpara',
    baslangic: _gun.subtract(const Duration(days: 40)));
final _bes = Sozlesme(
  id: _bid,
  userId: 'u',
  tur: SozlesmeTuru.bes,
  kurum: 'Anadolu Hayat Emeklilik',
  baslangic: DateTime(_gun.year - 7, 1, 1),
  aylikKatki: 5000,
  katkiGunu: 1,
  fonDagilimi: const [FonPayi(kod: 'AH5', oran: 100)],
  dkFonKodu: 'AEK',
);
Asset _lot(String sozlesme, AssetType tur, String ticker,
        {String? sub, double qty = 1000, double fiyat = 1, double guncel = 1}) =>
    Asset(
      id: '$ticker-$sub',
      userId: 'u',
      name: 'x',
      ticker: ticker,
      type: tur,
      subCategory: sub,
      quantity: qty,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: guncel,
      addedDate: _gun.subtract(const Duration(days: 40)),
      sozlesmeId: sozlesme,
    );
final _lotlar = [
  _lot(_mid, AssetType.mevduat, mevduatSembolu(_mid), qty: 250000, guncel: 1.03),
  _lot(_bid, AssetType.bes, 'TEFAS:AH5',
      sub: 'katki', qty: 10000, fiyat: 0.02, guncel: 0.03),
  _lot(_bid, AssetType.bes, 'TEFAS:AEK',
      sub: 'dk', qty: 2000, fiyat: 0.025, guncel: 0.03),
];
MevduatDonemi _donem({required bool dolmus}) => MevduatDonemi(
      id: 'd',
      sozlesmeId: _mid,
      baslangic: _gun.subtract(Duration(days: dolmus ? 40 : 8)),
      vadeSonu: dolmus
          ? _gun.subtract(const Duration(days: 8))
          : _gun.add(const Duration(days: 24)),
      yillikFaiz: 42,
      stopaj: 17.5,
    );

YarisKatilimci _k(String id, double? roi, {bool ben = false, int renk = 1}) =>
    YarisKatilimci(
        id: id, ad: id, ben: ben, roi: roi, renkSirasi: ben ? 0 : renk);

Future<void> _kur(
  WidgetTester tester,
  Brightness b,
  Widget ekran, {
  bool optIn = true,
  bool ortakli = true,
  MevduatDonemi? donem,
}) async {
  SharedPreferences.setMockInitialValues(
      optIn ? {'pref_leaderboard_opt_in': true} : {});
  await initPreferencesCache();
  tester.view.physicalSize = const Size(412 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      authProvider.overrideWith(_Auth.new),
      portfolioProvider.overrideWith(() => _Portfoy(_lotlar)),
      partnersProvider.overrideWith(() => _Ortaklar(ortakli
          ? [_ortak('p1', 'Ayşe Yılmaz'), _ortak('p2', 'Mehmet Demir')]
          : const [])),
      allPartnerAssetsProvider.overrideWith(_OrtakVarliklari.new),
      sozlesmeProvider.overrideWith(() => _Sozlesmeler(SozlesmeState(
            sozlesmeler: {_mid: _mevduat, _bid: _bes},
            donemler: {
              _mid: [donem ?? _donem(dolmus: true)],
            },
          ))),
      addAssetPriceLookupProvider.overrideWithValue(const _FiyatYok()),
    ],
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: SandikApp.buildTheme(p, b),
      home: ekran,
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _denetle(WidgetTester tester, Brightness b,
    {Set<String> haric = const {}}) {
  final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
  expect(olculenMetinSayisi(tester), greaterThan(2),
      reason: 'Denetim boş geçti — ekran metin çizmedi.');
  final bulgular =
      kontrastDenetle(tester, varsayilanZemin: p.background, haric: haric);
  expect(bulgular, isEmpty, reason: bulgular.join('\n'));
}

Future<void> _sok(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 1));
}

Widget _govde(Widget w) => Scaffold(
    body: SingleChildScrollView(
        padding: const EdgeInsets.all(16), child: w));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    DbLogger.silentInTests = true;
  });
  tearDownAll(() => DbLogger.silentInTests = false);

  for (final b in Brightness.values) {
    final ad = b == Brightness.light ? 'açık tema' : 'koyu tema';

    group('$ad — Sıralama', () {
      testWidgets('Ortaklarım: ortaklı yarış', (tester) async {
        await _kur(tester, b,
            SiralamaScreen(zirveRizaYukleyici: () async => true));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('Ortaklarım: katılım daveti', (tester) async {
        await _kur(
            tester, b, SiralamaScreen(zirveRizaYukleyici: () async => false),
            optIn: false);
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('Herkes: rıza kartı', (tester) async {
        await _kur(
            tester,
            b,
            SiralamaScreen(
                sekme: SiralamaSekmesi.herkes,
                zirveRizaYukleyici: () async => false));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('yarış sahnesi: kürsü (4 kişi)', (tester) async {
        await _kur(
            tester,
            b,
            _govde(YarisSahnesi(
              katilimcilar: [
                _k('Ayşe', 4.2, renk: 1),
                _k('Sen', 2.1, ben: true),
                _k('Mehmet', -0.4, renk: 2),
                _k('Zeynep', -3.0, renk: 3),
              ],
              yenileme: 1,
              sonGuncelleme: DateTime.now(),
              donemGun: 7,
            )));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('yarış sahnesi: düello (2 kişi)', (tester) async {
        await _kur(
            tester,
            b,
            _govde(YarisSahnesi(
              katilimcilar: [_k('Sen', 3.4, ben: true), _k('Ayşe', -1.2)],
              yenileme: 1,
              sonGuncelleme: DateTime.now(),
              donemGun: 30,
            )));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('zirve cetveli', (tester) async {
        await _kur(
            tester,
            b,
            _govde(ZirveCetveli(
              isaretler: const [
                ZirveIsaret(anahtar: '1', etiket: '1.', roi: 2.70, sira: 1),
                ZirveIsaret(anahtar: '2', etiket: '2.', roi: -3.30, sira: 2),
                ZirveIsaret(anahtar: '3', etiket: '3.', roi: -3.32, sira: 3),
                ZirveIsaret(
                    anahtar: 'sen', etiket: 'Sen', roi: -6.36, sen: true),
              ],
              secili: 'sen',
              onSec: (_) {},
            )));
        _denetle(tester, b);
        await _sok(tester);
      });
    });

    group('$ad — mevduat / BES / Varlık Ekle', () {
      testWidgets('mevduat kartı: vade doldu', (tester) async {
        await _kur(tester, b, _govde(SozlesmeKarti(varlik: _lotlar[0])));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('mevduat vade şeridi', (tester) async {
        await _kur(
            tester,
            b,
            _govde(MevduatVadeSeridi(
                temsilci: _lotlar[0],
                pay: 250000,
                baz: const BazPara.lira())),
            donem: _donem(dolmus: false));
        _denetle(tester, b);
        await _sok(tester);
      });
      testWidgets('BES kartı', (tester) async {
        await _kur(tester, b, _govde(SozlesmeKarti(varlik: _lotlar[1])));
        _denetle(tester, b);
        await _sok(tester);
      });
      // Varlık Ekle formu her tür için: tür çipi ve forma özgü seçiciler
      // kategori rengini ikon/metin olarak kullanıyor.
      for (final tur in AssetType.eklemeSirasi) {
        testWidgets('Varlık Ekle: ${tur.label} formu', (tester) async {
          await _kur(tester, b, const AddAssetScreen());
          await tester.tap(find.text(tur.label).first);
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          _denetle(tester, b);
          await _sok(tester);
        });
      }
    });
  }
}
