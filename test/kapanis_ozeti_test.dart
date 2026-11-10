// Kapanış özeti ("Tümünü sat" sonrası, müşteri işi 10 Kas).
//
// Kilitlenen: (1) kâr yıllık raporun satırıyla aynı sayı; (2) süre bugünkü
// elde tutmanın ilk alışından satış gününe; (3) 12 aydan kısada yıllık
// ortalama yok; (4) maliyet bilinmiyorsa tutar ve yüzde yok; (5) kısmi
// satışta özet yok; (6) sayfa tümünü satıştan sonra açılır, zararda paylaş
// düğmesi yok; (7) paylaşım kartında tutar yok.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/kapanis_ozeti.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/review_prompt_service.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';
import 'package:portfoy_takip/utils/tr_iyelik.dart';
import 'package:portfoy_takip/widgets/kapanis_ozeti_sheet.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Asset _lot(
  String id,
  AssetKind kind,
  DateTime tarih, {
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  double komisyon = 0,
  bool? maliyetYok,
  double guncel = 0,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      commission: komisyon,
      currentPrice: guncel,
      addedDate: tarih,
      createdAt: tarih,
    )..maliyetBilinmiyor = maliyetYok;

void main() {
  final alis = DateTime(2025, 7, 1);

  group('kapanisOzeti (hesap)', () {
    test('kâr ve yüzde yıllık raporun satırıyla aynı', () {
      final satis = _lot('s', AssetKind.sell, DateTime(2026, 11, 10),
          satis: 130, komisyon: 5);
      final o = kapanisOzeti(
          defter: [_lot('b', AssetKind.buy, alis), satis], satis: satis)!;
      final satir = yillikSatisSatiri(satis)!;
      expect(o.karTry, satir.karTry);
      expect(o.karTry, closeTo(1300 - 1000 - 5, 1e-9));
      expect(o.karPct, closeTo(29.5, 1e-9));
      expect(o.kazanc, isTrue);
      expect((o.yil, o.ay, o.gun), (1, 4, 0));
      expect(o.yillikPct, isNotNull);
    });

    test('12 aydan kısa: ay ya da gün, yıllık ortalama yok', () {
      final s1 = _lot('s', AssetKind.sell, DateTime(2025, 10, 5), satis: 120);
      final o1 = kapanisOzeti(
          defter: [_lot('b', AssetKind.buy, alis), s1], satis: s1)!;
      expect((o1.yil, o1.ay, o1.gun), (0, 3, 0));
      expect(o1.yillikPct, isNull);

      final s2 = _lot('s', AssetKind.sell, DateTime(2025, 7, 13), satis: 120);
      final o2 = kapanisOzeti(
          defter: [_lot('b', AssetKind.buy, alis), s2], satis: s2)!;
      expect((o2.yil, o2.ay, o2.gun), (0, 0, 12));

      final s3 = _lot('s', AssetKind.sell, alis, satis: 120);
      final o3 = kapanisOzeti(
          defter: [_lot('b', AssetKind.buy, alis), s3], satis: s3)!;
      expect((o3.yil, o3.ay, o3.gun), (0, 0, 0));
    });

    test('maliyet bilinmiyor: tutar ve yüzde yok, süre var', () {
      final satis =
          _lot('s', AssetKind.sell, DateTime(2025, 10, 5), satis: 120);
      final o = kapanisOzeti(defter: [
        _lot('b', AssetKind.buy, alis, maliyetYok: true),
        satis,
      ], satis: satis)!;
      expect(o.karTry, isNull);
      expect(o.karPct, isNull);
      expect(o.kazanc, isFalse);
      expect(o.ay, 3);
    });

    test('kısmi satış: özet yok', () {
      final satis = _lot('s', AssetKind.sell, DateTime(2025, 10, 5),
          miktar: 4, satis: 120);
      expect(
          kapanisOzeti(
              defter: [_lot('b', AssetKind.buy, alis), satis], satis: satis),
          isNull);
    });

    test('yeniden alınan pozisyonda süre yeni ilk alıştan', () {
      final satis =
          _lot('s2', AssetKind.sell, DateTime(2026, 3, 1), satis: 120);
      final o = kapanisOzeti(defter: [
        _lot('b1', AssetKind.buy, DateTime(2023, 1, 1)),
        _lot('s1', AssetKind.sell, DateTime(2024, 1, 1), satis: 110),
        _lot('b2', AssetKind.buy, DateTime(2025, 12, 1)),
        satis,
      ], satis: satis)!;
      expect((o.yil, o.ay), (0, 3));
    });

    test('belirtme eki adın son ünlüsüne göre', () {
      expect(trBelirtme('THYAO'), "THYAO'yu");
      expect(trBelirtme('Gram Altın'), "Gram Altın'ı");
      expect(trBelirtme('ASELS'), "ASELS'i");
      expect(trBelirtme('Gümüş'), "Gümüş'ü");
    });

    test('süre metni', () {
      final l = AppLocalizationsTr();
      KapanisOzeti o(int y, int a, int g) =>
          KapanisOzeti(ad: 'X', yil: y, ay: a, gun: g);
      expect(kapanisSureMetni(l, o(1, 4, 0)), '1 yıl 4 ay');
      expect(kapanisSureMetni(l, o(2, 0, 0)), '2 yıl');
      expect(kapanisSureMetni(l, o(0, 3, 0)), '3 ay');
      expect(kapanisSureMetni(l, o(0, 0, 12)), '12 gün');
      expect(kapanisSureMetni(l, o(0, 0, 0)), 'bir günden kısa');
    });

    test('paylaşım kartı ve metni tutar taşımaz', () {
      final l = AppLocalizationsTr();
      final kart = kapanisPaylasimKarti(l, ad: 'THYAO', karPct: 29.5);
      expect(kart.degisimPct, 29.5);
      final metin = kapanisPaylasimMetni(l, ad: 'THYAO', karPct: 29.5);
      expect(metin, contains('+%29,5'));
      expect(metin, isNot(contains('₺')));
    });

    test('değerlendirme anı listede', () {
      expect(ReviewAni.values, contains(ReviewAni.kapanis));
      expect(kapanisDegerlendirmeEsigiPct, 5.0);
    });
  });

  group('Hızlı Sat → kapanış sayfası', () {
    setUpAll(() async {
      await initializeDateFormatting('tr_TR');
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();
    });

    Future<void> sat(WidgetTester tester,
        {required double guncel, bool tumu = true}) async {
      final pozisyon =
          _lot('b', AssetKind.buy, DateTime(2025, 1, 1), guncel: guncel);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _SatanPortfoy(pozisyon)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  await ref.read(portfolioProvider.future);
                  if (!context.mounted) return;
                  await showQuickAdjustDialog(context, ref,
                      asset: pozisyon, mode: QuickAdjustMode.remove);
                },
                child: const Text('ac'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ac'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, tumu ? '10' : '4');
      await tester.pump();
      await tester.tap(find.widgetWithText(SandikAsyncButton, 'Sat'));
      await tester.pumpAndSettle();
    }

    testWidgets('kazançta sayfa açılır, paylaş düğmesi var', (tester) async {
      await sat(tester, guncel: 130);
      expect(find.text('Pozisyon kapandı'), findsOneWidget);
      expect(find.byKey(const ValueKey('kapanis_sure')), findsOneWidget);
      expect(find.byKey(const ValueKey('kapanis_paylas')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('kapanis_sonuc'))).data,
          '+₺300 · +%30,0');
    });

    testWidgets('zararda paylaş düğmesi yok, nötr cümle var', (tester) async {
      await sat(tester, guncel: 80);
      expect(find.text('Pozisyon kapandı'), findsOneWidget);
      expect(find.byKey(const ValueKey('kapanis_paylas')), findsNothing);
      expect(find.text('Bu pozisyon zararla kapandı.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('kapanis_tamam')));
      await tester.pumpAndSettle();
      expect(find.text('Pozisyon kapandı'), findsNothing);
    });

    testWidgets('kısmi satışta sayfa açılmaz', (tester) async {
      await sat(tester, guncel: 130, tumu: false);
      expect(find.text('Pozisyon kapandı'), findsNothing);
    });
  });
}

/// Satışı deftere yazan sahte portföy (sağlayıcının yaptığı gibi satırı
/// başa ekler, `createdAt` şimdi).
class _SatanPortfoy extends PortfolioNotifier {
  _SatanPortfoy(this.pozisyon);
  final Asset pozisyon;

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: [pozisyon]);

  @override
  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
    DateTime? addedDate,
  }) async {
    final satis = Asset(
      id: 'satis',
      userId: asset.userId,
      name: asset.name,
      ticker: asset.ticker,
      type: asset.type,
      quantity: quantity,
      purchasePrice: asset.purchasePrice,
      currency: asset.currency,
      notes: '',
      isManualPrice: false,
      kind: AssetKind.sell,
      sellPrice: sellPrice,
      createdAt: DateTime.now(),
    );
    final s = state.valueOrNull ?? const PortfolioState();
    state = AsyncData(s.copyWith(assets: [satis, ...s.assets]));
  }
}
