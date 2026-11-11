// Hızlı Al "Adet · Tutar" kipi (2026-11-11, Ar-Ge 11 Kas #2): tutar yazılır,
// adet = tutar ÷ fiyat alanındaki birim fiyat (`tutardanAdet`, Varlık ekle
// formuyla aynı fonksiyon); kayıt yine adet + fiyat.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/services/hizli_tekrar_al.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _Kayit = ({double adet, double fiyat, DateTime? tarih});

class _KaydedenPortfoy extends PortfolioNotifier {
  _KaydedenPortfoy(this.lotlar);
  final List<Asset> lotlar;
  final kayitlar = <_Kayit>[];

  @override
  Future<PortfolioState> build() async => PortfolioState(assets: lotlar);

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
    String? sozlesmeId,
    String? portfoyId,
    String yol = 'form',
    bool maliyetBilinmiyor = false,
  }) async {
    kayitlar.add((adet: quantity, fiyat: purchasePrice, tarih: addedDate));
  }
}

/// Geçmiş kapanış [kapanis] (null → yok), güncel fiyat 100.
class _Kapi implements AddAssetPriceLookup {
  _Kapi({this.kapanis});
  final double? kapanis;
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async =>
      kapanis;
  @override
  Future<double?> spot(String ticker) async => 100;
  @override
  Future<String?> companyName(String ticker) async => 'Şirket';
}

Asset _varlik({
  AssetType tur = AssetType.fon,
  String ticker = 'AAK',
  double adet = 500,
  double fiyat = 100,
  double guncel = 100,
  String id = 'p1',
  DateTime? t,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: guncel,
      addedDate: t ?? DateTime(2026, 1, 1),
    );

DateTime _dun() {
  final b = dayKey(DateTime.now());
  return DateTime(b.year, b.month, b.day - 1);
}

final _kip = find.byKey(const ValueKey('hizli_miktar_kipi'));
final _adetSatiri = find.byKey(const ValueKey('hizli_tutardan_adet'));

Future<_KaydedenPortfoy> _ac(
  WidgetTester tester,
  Asset pozisyon, {
  List<Asset> defter = const [],
  double? kapanis,
  QuickAdjustMode mod = QuickAdjustMode.add,
}) async {
  // 600 pt: diyaloğun "Toplam maliyet" satırı test yazı tipinde (Ahem)
  // 390 pt'de taşıyor — bu değişiklikten önce de (tarih_cipleri_test notu).
  tester.view.physicalSize = const Size(1800, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final portfoy = _KaydedenPortfoy(defter);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => portfoy),
      addAssetPriceLookupProvider.overrideWithValue(_Kapi(kapanis: kapanis)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              await ref.read(portfolioProvider.future);
              if (!context.mounted) return;
              await showQuickAdjustDialog(context, ref,
                  asset: pozisyon, mode: mod);
            },
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
  return portfoy;
}

Future<void> _tutarKipi(WidgetTester tester) async {
  await tester.tap(find.text('Tutar (₺)'));
  await tester.pumpAndSettle();
}

Future<void> _al(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Al'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  test('alimTutari: miktar × fiyat kuruşa yuvarlı; geçersizde null', () {
    expect(alimTutari(_varlik(adet: 25, fiyat: 200)), 5000);
    expect(alimTutari(_varlik(adet: 2499.99875, fiyat: 2.000001)), 5000);
    expect(alimTutari(_varlik(adet: 0, fiyat: 200)), isNull);
    expect(alimTutari(_varlik(adet: double.infinity, fiyat: 2)), isNull);
  });

  testWidgets('varsayılan Adet: diyalog eskisi gibi, seçici 44 pt',
      (tester) async {
    await _ac(tester, _varlik());
    expect(_kip, findsOneWidget);
    expect(tester.getSize(_kip).height, greaterThanOrEqualTo(44));
    expect(find.text('Miktar'), findsOneWidget);
    // Seçili kip yalnız renkle değil: ekran okuyucu "seçili" der.
    expect(tester.getSemantics(find.bySemanticsLabel('Miktarı Adet olarak gir')),
        isSemantics(isSelected: true));
  });

  testWidgets('Tutar kipi: adet canlı hesaplanır, kayıt adet + fiyat',
      (tester) async {
    final a = _varlik();
    final portfoy = await _ac(tester, a);
    await _tutarKipi(tester);
    expect(find.text('Tutar'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '5.000');
    await tester.pump();
    expect(find.text('≈ 50 ${a.unitLabel}'), findsOneWidget);
    // "≈" yerine cümle okunur.
    expect(find.bySemanticsLabel('Hesaplanan miktar: 50 ${a.unitLabel}'),
        findsOneWidget);
    // Toplam satırı tutarı tekrar etmez.
    expect(find.text('Toplam maliyet'), findsNothing);
    await _al(tester);
    expect(portfoy.kayitlar.single.adet, 50);
    expect(portfoy.kayitlar.single.fiyat, 100);
  });

  testWidgets('Tutar → Adet: hesaplanan adet miktar alanına yazılır',
      (tester) async {
    await _ac(tester, _varlik());
    await _tutarKipi(tester);
    await tester.enterText(find.byType(TextField).first, '2500');
    await tester.tap(find.text('Adet'));
    await tester.pumpAndSettle();
    expect(find.text('Miktar'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
  });

  testWidgets('fiyat yoksa Tutar kapalı, nedeni yazılı; adet uydurulmaz',
      (tester) async {
    await _ac(tester, _varlik());
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.pump();
    expect(find.byKey(const ValueKey('hizli_tutar_fiyat_yok')), findsOneWidget);
    expect(
        tester.getSemantics(
            find.bySemanticsLabel('Miktarı Tutar (₺) olarak gir')),
        isSemantics(hasEnabledState: true, isEnabled: false));
    await _tutarKipi(tester);
    expect(find.text('Miktar'), findsOneWidget,
        reason: 'kapalı segmente dokunuş kipi değiştirmez');
    // Fiyat girilince açılır.
    await tester.enterText(find.byType(TextField).at(1), '40');
    await tester.pump();
    expect(find.byKey(const ValueKey('hizli_tutar_fiyat_yok')), findsNothing);
    await _tutarKipi(tester);
    expect(find.text('Tutar'), findsOneWidget);
  });

  testWidgets('Dün: kapanış fiyat alanını değiştirince adet onu izler',
      (tester) async {
    final a = _varlik();
    final portfoy = await _ac(tester, a, kapanis: 80);
    await _tutarKipi(tester);
    await tester.enterText(find.byType(TextField).first, '4000');
    await tester.pump();
    expect(find.text('≈ 40 ${a.unitLabel}'), findsOneWidget);
    await tester.tap(find.widgetWithText(SandikFiltreCipi, 'Dün'));
    await tester.pumpAndSettle();
    expect(find.text('≈ 50 ${a.unitLabel}'), findsOneWidget);
    await _al(tester);
    expect(portfoy.kayitlar.single.adet, 50);
    expect(portfoy.kayitlar.single.fiyat, 80);
    expect(portfoy.kayitlar.single.tarih, _dun());
  });

  testWidgets('Tutar kipinde "Son alımın" son alımın tutarını önerir',
      (tester) async {
    final a = _varlik();
    final lot = _varlik(id: 'l1', adet: 25, fiyat: 200, t: DateTime(2026, 10, 5));
    final portfoy = await _ac(tester, a, defter: [lot]);
    // Adet kipinde miktar.
    expect(find.textContaining('Son alımın · 25'), findsOneWidget);
    await _tutarKipi(tester);
    final cip = find.text('Son alımın · ₺5.000');
    expect(cip, findsOneWidget);
    expect(find.text('1'), findsNothing, reason: 'adet önerileri tutar değil');
    await tester.tap(cip);
    await tester.pump();
    expect(find.widgetWithText(TextField, '5000'), findsOneWidget);
    expect(_adetSatiri, findsOneWidget);
    await _al(tester);
    expect(portfoy.kayitlar.single.adet, 50);
    expect(portfoy.kayitlar.single.fiyat, 100);
  });

  testWidgets('Eurobond, mevduat ve satışta seçici yok', (tester) async {
    await _ac(tester, _varlik(tur: AssetType.eurobond, ticker: 'XS123'));
    expect(_kip, findsNothing);
    await tester.pumpWidget(const SizedBox());

    await _ac(tester, _varlik(tur: AssetType.mevduat, ticker: 'MEV', fiyat: 1, guncel: 1));
    expect(_kip, findsNothing);
    expect(find.byType(SandikSegment), findsNothing);
    await tester.pumpWidget(const SizedBox());

    await _ac(tester, _varlik(), mod: QuickAdjustMode.remove);
    expect(_kip, findsNothing);
  });
}
