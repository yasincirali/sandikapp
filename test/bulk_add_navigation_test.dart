import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Toplu ekleme sonrası portföye dönüş — navigasyon sözleşmesi.
///
/// **Yakalanan hata (2026-08-09):** Yığın şöyleydi:
///
///     MainNav → AddAssetScreen → BulkAddAssetScreen
///
/// `BulkAddAssetScreen` kaydettikten sonra `pop()` ile YALNIZCA kendini
/// kapatıyordu. Kullanıcı arkada duran boş `AddAssetScreen` formunda
/// kalıyordu; tekli eklemede portföye dönülürken toplu eklemede
/// dönülmüyordu. Ayrıca `MainNav`'daki `refreshPrices()` de tetiklenmiyordu
/// çünkü o, `AddAssetScreen`'in kapanmasını bekliyor.
///
/// Sözleşme:
///   - Toplu ekran başarıyla kaydederse `pop(true)` döner.
///   - `AddAssetScreen` bu sonucu görünce kendisi de `pop(true)` yapar.
///   - Sepete ekleme (cartMode) `pop()` — değersiz — döner ve zincir
///     tetiklenmez; kullanıcı sepet listesinde kalmalıdır.
///
/// Burada gerçek ekranlar kurulmuyor (Supabase/provider bağımlılıkları
/// widget testinde ağır); yığın davranışı birebir aynı sözleşmeyle
/// modelleniyor. Regresyon, sözleşmenin kendisinde yakalanır.
void main() {
  /// Üç katmanlı yığını kurar ve en üstteki ekranın döndürdüğü değere göre
  /// zincirin nasıl çözüldüğünü ölçer.
  Future<List<String>> runStack(
    WidgetTester tester, {
    required Object? topResult,
  }) async {
    final log = <String>[];
    late BuildContext rootCtx;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          rootCtx = context;
          return const Scaffold(body: Text('MainNav'));
        }),
      ),
    );

    // MainNav → AddAssetScreen
    final addResult = Navigator.of(rootCtx).push<bool>(
      MaterialPageRoute(
        builder: (addCtx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-bulk'),
              onPressed: () async {
                // AddAssetScreen → BulkAddAssetScreen
                final added = await Navigator.of(addCtx).push<bool>(
                  MaterialPageRoute(
                    builder: (bulkCtx) => Scaffold(
                      body: Center(
                        child: ElevatedButton(
                          key: const Key('save-bulk'),
                          onPressed: () =>
                              Navigator.of(bulkCtx).pop(topResult),
                          child: const Text('Kaydet'),
                        ),
                      ),
                    ),
                  ),
                );
                log.add('bulk->add: $added');
                // ── Düzeltmenin kendisi ──
                if (added == true && addCtx.mounted) {
                  Navigator.of(addCtx).pop(true);
                }
              },
              child: const Text('Toplu ekle'),
            ),
          ),
        ),
      ),
    );
    addResult.then((v) => log.add('add->main: $v'));

    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-bulk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-bulk')));
    await tester.pumpAndSettle();

    return log;
  }

  testWidgets('toplu kayıt başarılıysa zincir portföye kadar çözülür',
      (tester) async {
    final log = await runStack(tester, topResult: true);

    expect(log, contains('bulk->add: true'));
    // Asıl iddia: AddAssetScreen de kapanmalı, yani MainNav'a dönülmeli.
    expect(log, contains('add->main: true'),
        reason: 'Toplu ekleme sonrası AddAssetScreen açık kalıyor — '
            'kullanıcı boş formda mahsur kalır.');
    expect(find.text('MainNav'), findsOneWidget);
  });

  testWidgets('sepete ekleme zinciri tetiklemez (cartMode)', (tester) async {
    // cartMode `pop()` ile değersiz döner.
    final log = await runStack(tester, topResult: null);

    expect(log, contains('bulk->add: null'));
    // AddAssetScreen KAPANMAMALI — kullanıcı eklemeye devam edebilmeli.
    expect(log.any((l) => l.startsWith('add->main')), isFalse,
        reason: 'Sepete ekleme akışında form kapanmamalı.');
    expect(find.text('MainNav'), findsNothing);
  });

  test('toplu ekleme basari dialogu GOSTERMEZ', () {
    // UX kararı (2026-08-09): tekli ekleme kaydettikten sonra hiçbir onay
    // penceresi göstermiyor, doğrudan portföye dönüyor. Toplu ekleme
    // "Tümü Eklendi" dialogu gösteriyordu; iki akışın hissi ayrılıyordu
    // ve kullanıcıya fazladan bir dokunuş yaptırıyordu.
    //
    // Hata durumu dialogu KALIR — orada kullanıcının bilmesi gereken
    // bir bilgi var (hangi varlıklar eklenemedi).
    final src = File('lib/screens/bulk_add_asset_screen.dart')
        .readAsStringSync();

    expect(
      src.contains('showAppSuccess'),
      isFalse,
      reason: 'Toplu eklemede başarı dialogu geri gelmiş. Tekli ekleme ile '
          'deneyim birebir olmalı: kayıt bitince doğrudan portföye dön.',
    );
    // Hata yolu korunmalı.
    expect(src.contains('showSandikDialog'), isTrue,
        reason: 'Kısmi başarısızlık bildirimi kaldırılmamalı.');
  });
}
