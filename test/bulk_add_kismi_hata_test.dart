import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/bulk_add_asset_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Toplu eklemede kısmi hata — 2026-09-23 denetimi F13.
///
/// **Yakalanan hata:** bir kısmı kaydedilip bir kısmı düşen toplu eklemede
/// sepet olduğu gibi kalıyordu. Kullanıcı yeniden "Tümünü Kaydet"e bastığında
/// (ya da premium'a geçip otomatik yeniden deneme koştuğunda) ilk turda
/// KAYDEDİLMİŞ kalemler ikinci kez portföye yazılıyordu.
///
/// Sözleşme: başarılı her kalem sepetten anında düşer; sepette yalnızca
/// eklenemeyenler kalır; kullanıcıya kaçının eklendiği/eklenemediği söylenir.
/// Tüm kalemlerin fiyatı dolu verilir ki ekran ağa çıkmasın.

class _SahtePortfoy extends PortfolioNotifier {
  _SahtePortfoy(this.basarisiz);

  /// Bu adlardaki kalemler kayıtta hata fırlatır.
  final Set<String> basarisiz;
  final List<String> eklenen = [];

  @override
  Future<PortfolioState> build() async => const PortfolioState();

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
  }) async {
    if (basarisiz.contains(name)) throw Exception('ağ koptu');
    eklenen.add(name);
  }
}

BulkCartItem _kalem(String ad) => BulkCartItem(
      id: 'id-$ad',
      type: AssetType.diger,
      name: ad,
      ticker: '',
      quantity: 1,
      price: 100,
      currency: 'TRY',
      addedDate: DateTime.now(),
      isManualPrice: true,
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'kısmi hatada kaydedilenler sepetten düşer, yeniden deneme kopya üretmez',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final portfoy = _SahtePortfoy({'Beta'});
    final container = ProviderContainer(overrides: [
      portfolioProvider.overrideWith(() => portfoy),
    ]);
    addTearDown(container.dispose);
    final sepet = container.read(bulkCartProvider.notifier);
    sepet.add(_kalem('Alfa'));
    sepet.add(_kalem('Beta'));
    sepet.add(_kalem('Gama'));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const BulkAddAssetScreen(),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Tümünü Kaydet (3)'));
    await tester.pumpAndSettle();

    // Kaydedilenler sepetten düştü; yalnızca eklenemeyen kaldı.
    expect(portfoy.eklenen, unorderedEquals(['Alfa', 'Gama']));
    expect(container.read(bulkCartProvider).map((e) => e.name), ['Beta']);

    // Kullanıcıya sayılar söylendi.
    expect(
      find.textContaining('2 varlık eklendi, 1 varlık eklenemedi'),
      findsOneWidget,
    );

    // Dialogu kapat, sorun giderilmiş olsun ve yeniden dene.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final kapat = find.byType(TextButton);
    if (kapat.evaluate().isNotEmpty) {
      await tester.tap(kapat.last);
      await tester.pumpAndSettle();
    }
    portfoy.basarisiz.clear();

    await tester.tap(find.text('Tümünü Kaydet (1)'));
    await tester.pumpAndSettle();

    // Asıl iddia: Alfa ve Gama İKİNCİ kez eklenmedi.
    expect(portfoy.eklenen, unorderedEquals(['Alfa', 'Gama', 'Beta']));
    expect(container.read(bulkCartProvider), isEmpty);
  });

  test('ilerleme paydası kayıt başında sabitlenir', () {
    // Sepet kayıt sürerken küçüldüğü için pay/payda `items.length` olamaz.
    final src = ekranKaynagiSync('lib/screens/bulk_add_asset_screen.dart');
    expect(src, contains('bulkAddSavingProgress(_saved, _toplam)'));
    expect(src, isNot(contains(r'$_saved / ${items.length}')));
  });
}
