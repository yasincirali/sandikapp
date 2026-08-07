import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/widgets/zoom_data_controller.dart';

/// `ZoomDataController` yükleme davranışı.
///
/// İki regresyon korunuyor:
/// 1) Veri önbellekten anında dönebildiği için `_loading` HEMEN true
///    yapılmamalı — aksi halde her filtre/zoom değişiminde bir kare
///    spinner çakıyor. 120ms'lik grace süresi var.
/// 2) Filtre değişiminde eski controller dispose ediliyor; uçuşta olan
///    istek dönünce dispose sonrası notifyListeners() ÇAĞIRMAMALI.
void main() {
  Asset asset() => Asset(
        id: 'a1',
        userId: 'u1',
        name: 'Test',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 10,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 120,
        addedDate: DateTime(2026, 1, 1),
      );

  test('kurulumda loading anında true olmaz (spinner çakması yok)', () {
    final c = ZoomDataController(
      assets: [asset()],
      initialFrom: DateTime(2026, 1, 1),
      initialTo: DateTime(2026, 2, 1),
    );
    addTearDown(c.dispose);

    // Constructor _reload(immediate: true) tetikler ama grace timer
    // dolmadan loading duyurulmamalı.
    expect(c.loading, isFalse,
        reason: 'loading kurulumda hemen true olmamalı — grace bekleniyor');
  });

  test('tohum veri stale olarak işaretlenir', () {
    final seed = {DateTime(2026, 1, 1).millisecondsSinceEpoch: 1000.0};
    final c = ZoomDataController(
      assets: [asset()],
      initialFrom: DateTime(2026, 1, 1),
      initialTo: DateTime(2026, 2, 1),
      seedData: seed,
    );
    addTearDown(c.dispose);

    expect(c.data, seed);
    expect(c.stale, isTrue,
        reason: 'devralınan veri gerçek sonuç sayılmamalı');
  });

  test('tohum verisiz kurulumda stale false', () {
    final c = ZoomDataController(
      assets: [asset()],
      initialFrom: DateTime(2026, 1, 1),
      initialTo: DateTime(2026, 2, 1),
    );
    addTearDown(c.dispose);
    expect(c.stale, isFalse);
  });

  test('dispose sonrası bekleyen iş notify etmez (exception fırlatmaz)',
      () async {
    final c = ZoomDataController(
      assets: [asset()],
      initialFrom: DateTime(2026, 1, 1),
      initialTo: DateTime(2026, 2, 1),
    );
    // Uçuşta istek varken hemen dispose et — filtre değişimi senaryosu.
    c.dispose();

    // İstek dönene kadar bekle. Dispose sonrası notifyListeners()
    // çağrılırsa burada exception patlar.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Buraya exception'sız ulaşmak testin kendisidir.
    expect(true, isTrue);
  });

  test('dispose iki kez çağrılabilir olmalı değil — tek dispose güvenli', () {
    final c = ZoomDataController(
      assets: [asset()],
      initialFrom: DateTime(2026, 1, 1),
      initialTo: DateTime(2026, 2, 1),
    );
    c.dispose();
    // Grace timer iptal edildiği için ek bir iş kalmamalı.
    expect(c.loading, isFalse);
  });
}
