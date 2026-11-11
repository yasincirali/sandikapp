import 'dart:async';

import 'package:flutter/gestures.dart' show kPressTimeout;
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
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/screens/asset_detail_screen.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// **Basma anında seri ön isteği (2026-11-11).**
///
/// Portföy ve Takip satırı parmak değdiği an (`onTapDown`) varlık
/// sayfasının ilk açılışta isteyeceği seriyi başlatır. Kazancın şartı ön
/// isteğin sayfanın İSTEĞİYLE AYNI anahtarı kullanması: değilse ağ boşuna
/// iki kez gider. Bu test üç şeyi kilitler: (1) `SandikTappable.onBasildi`
/// basmada (dokunuş bitmeden) çağrılır; (2) ön istek ile sayfa aynı
/// `seriCek` anahtarlarına biner, sayfa açılınca o anahtarlar için ikinci
/// ağ çağrısı yoktur; (3) Takip sayfasının ilk dönemi ön istekle aynı
/// fonksiyondan seçilir.

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
  late List<String> cagrilar;
  late List<Completer<List<(int, double)>>> bekleyenler;
  // `hepsiniBirak`tan sonra gelen istekler hemen yanıtlanır (servisin yedek
  // merdiveni 8 sn zaman aşımı beklemesin).
  var serbest = false;

  void hepsiniBirak() {
    serbest = true;
    final ts = DateTime(2026, 11, 10, 12).millisecondsSinceEpoch;
    for (final c in bekleyenler) {
      if (!c.isCompleted) c.complete([(ts, 300.0), (ts + 60000, 310.0)]);
    }
  }

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  setUp(() {
    HistoryService.clearCache();
    // Tier katmanının kendi önbelleği de var; önceki testin serisi orada
    // kalırsa ön istek ağa hiç çıkmaz ve test boşuna kırılır.
    HistoryService.instance.clearTierCache();
    cagrilar = [];
    bekleyenler = [];
    serbest = false;
    // Yanıt elle bırakılır: ön istek UÇUŞTAYKEN sayfa açılır — gerçek
    // durum budur (geçiş animasyonu yanıttan kısa).
    HistoryService.seriCekici = (sym, range, interval) {
      cagrilar.add('$sym|$range|${interval ?? "-"}');
      final c = Completer<List<(int, double)>>();
      bekleyenler.add(c);
      if (serbest) hepsiniBirak();
      return c.future;
    };
  });

  tearDown(() {
    HistoryService.seriCekici = HistoryService.varsayilanSeriCekici;
    HistoryService.clearCache();
  });


  testWidgets('SandikTappable.onBasildi parmak değdiği an, onTap öncesi',
      (tester) async {
    final olaylar = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SandikTappable(
          onTap: () => olaylar.add('tap'),
          onBasildi: () => olaylar.add('bas'),
          child: const SizedBox(width: 100, height: 60),
        ),
      ),
    ));
    final jest = await tester.startGesture(
        tester.getCenter(find.byType(SandikTappable)));
    // Dokunuş tanıyıcı `onTapDown`'u kısa bir beklemeden sonra verir.
    await tester.pump(kPressTimeout);
    expect(olaylar, ['bas'], reason: 'Ön istek dokunuş bitmeden başlamalı.');
    await jest.up();
    await tester.pumpAndSettle();
    expect(olaylar, ['bas', 'tap']);
  });

  testWidgets('pasif yüzey (onTap yok) ön istek başlatmaz', (tester) async {
    var basildi = 0;
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SandikTappable(
          onBasildi: () => basildi++,
          child: const SizedBox(width: 100, height: 60),
        ),
      ),
    ));
    await tester.tap(find.byType(SandikTappable));
    await tester.pumpAndSettle();
    expect(basildi, 0);
  });

  for (final donem in [SummaryPeriod.gunluk, SummaryPeriod.birAy]) {
    testWidgets(
        'varlık ekranı (${donem.name}): ön istekle AYNI anahtar, ikinci ağ '
        'çağrısı yok', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      Widget ekran() => ProviderScope(
            overrides: [
              authProvider.overrideWith(_FakeAuth.new),
              portfolioProvider.overrideWith(_FakePortfolio.new),
              seciliDonemProvider.overrideWith((ref) => donem),
              // Sinyal serisi `initState`'te beklemeden istenir ve ilk
              // isteği o olurdu; burada ölçülen seçili dönemin serisi.
              sinyalYuzeyiProvider.overrideWithValue(SinyalYuzeyi.gizli),
            ],
            child: MaterialApp(
              theme: ThemeData.dark(),
              home: AssetDetailScreen(asset: _asset(), showBackButton: true),
            ),
          );

      // Kontrol koşusu (ön istek YOK): sayfanın İLK isteği seçili dönemin
      // serisidir (`_loadHistory`, öteki dönemlerden önce). Ön istek o
      // anahtarı içermeli — yalnız "çift çağrı yok" yetmez: sayfa öteki
      // dönemleri de istediği için yanlış dönemi ön isteyen bir hata da
      // çift çağrı üretmez, ama seçili dönemi hızlandırmaz.
      await tester.pumpWidget(ekran());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(cagrilar, isNotEmpty);
      final seciliAnahtar = cagrilar.first;
      hepsiniBirak();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      HistoryService.clearCache();
      HistoryService.instance.clearTierCache();
      cagrilar.clear();
      bekleyenler.clear();
      serbest = false;

      AssetDetailScreen.seriyiOnIste(_asset(), donem);
      await tester.pump();
      final onIstek = cagrilar.toSet();
      expect(onIstek, isNotEmpty, reason: 'Ön istek ağa hiç çıkmadı.');
      expect(onIstek.length, cagrilar.length);
      expect(onIstek, contains(seciliAnahtar),
          reason: 'Ön istek sayfanın seçili dönemini istemiyor.');

      await tester.pumpWidget(ekran());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Sayfa diğer dönemleri de ister (çip getirileri); onlar başka
      // anahtar. Ön isteğin anahtarları ise TAM BİR KEZ çekilmiş olmalı.
      for (final k in onIstek) {
        expect(cagrilar.where((c) => c == k).length, 1,
            reason: '$k sayfa açılınca yeniden istendi — ön istek sayfanın '
                'isteğiyle birleşmiyor (farklı dönem/anahtar ya da uçuşan '
                'istek paylaşılmıyor).');
      }

      hepsiniBirak();
      await tester.pump(const Duration(seconds: 1));
      final yanitSonrasi = cagrilar.length;
      // Yanıt geldikten sonra da (süreli önbellek) aynı anahtar ağa çıkmaz.
      for (final k in onIstek) {
        expect(cagrilar.where((c) => c == k).length, 1);
      }
      expect(cagrilar.length, yanitSonrasi);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }

  test('Takip sayfası: ilk dönem tek fonksiyondan', () {
    // Geçerli istek kazanır; geçersizse ortak dönem.
    expect(VarlikSayfasi.ilkGun(30, SummaryPeriod.gunluk), 30);
    expect(VarlikSayfasi.ilkGun(null, SummaryPeriod.birAy),
        SummaryPeriod.birAy.sembolGunu);
    expect(VarlikSayfasi.ilkGun(-7, SummaryPeriod.birAy),
        SummaryPeriod.birAy.sembolGunu);
  });

  test('Takip sayfası: ön istek sayfanın çağrısıyla birleşir', () async {
    VarlikSayfasi.seriyiOnIste('THYAO.IS', 30, SummaryPeriod.gunluk);
    await Future<void>.delayed(Duration.zero);
    final onIstek = cagrilar.toSet();
    expect(onIstek, isNotEmpty);

    // Sayfanın taze yükleyicisi (`_tazeYukleyici` varsayılanı) AYNI anda.
    final sayfa = HistoryService.instance.getSymbolHistoryTazelikli(
        'THYAO.IS',
        periodDays: VarlikSayfasi.ilkGun(30, SummaryPeriod.gunluk));
    await Future<void>.delayed(Duration.zero);
    for (final k in onIstek) {
      expect(cagrilar.where((c) => c == k).length, 1, reason: k);
    }
    hepsiniBirak();
    await sayfa;
    // Servisin kendi yedek merdiveni (ince seri → başka aralık) sonra
    // başka anahtar isteyebilir; ön isteğin anahtarı yine TEK kez gider.
    for (final k in onIstek) {
      expect(cagrilar.where((c) => c == k).length, 1, reason: k);
    }
  });

  test('boş sembol ağa çıkmaz', () async {
    VarlikSayfasi.seriyiOnIste('  ', 30, SummaryPeriod.gunluk);
    await Future<void>.delayed(Duration.zero);
    expect(cagrilar, isEmpty);
  });
}
