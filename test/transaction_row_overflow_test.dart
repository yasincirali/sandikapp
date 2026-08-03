import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Portföy hareketleri satırının taşma regresyonu.
///
/// **Bug:** kullanıcı ekranında "BOTTOM OVERFLOWED BY 3.9 PIXELS" görünüyordu.
/// Sol kolon (başlık + rozet satırı) varsayılan `MainAxisSize.max` ile satırın
/// yüksekliğine zorlanıyordu; iki satırlık fon başlığı (TEFAS fon adları
/// `maxLines: 2`) artı rozet satırı bu yüksekliğe sığmayınca taşıyordu.
///
/// Buradaki ağaç `home_screen.dart`'taki `_buildAssetTile`'ın yapısal
/// kopyasıdır — o metot `_HomeScreenState`'e private olduğu ve Riverpod +
/// Supabase + auth istediği için doğrudan pump edilemiyor. Yapı değişirse
/// burası da güncellenmeli.
///
/// Flutter'da taşma bir exception olarak raporlanır; `tester.takeException()`
/// null değilse satır taşmış demektir.

/// [minified] true → düzeltilmiş hâl (Column.mainAxisSize.min).
Widget buildRow({
  required String title,
  required int titleMaxLines,
  required bool minified,
  bool showQtyBadge = true,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.pie_chart, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: minified ? MainAxisSize.min : MainAxisSize.max,
                children: [
                  Text(title,
                      maxLines: titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 4),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: const Text('Fon', style: TextStyle(fontSize: 10)),
                      ),
                      const Text('24 Tem 2026', style: TextStyle(fontSize: 12)),
                      if (showQtyBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: const Text('486.948',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 116,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 11),
                        SizedBox(width: 4),
                        Text('Eklendi',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('+₺396.802,725',
                        maxLines: 1, style: TextStyle(fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  group('portföy hareketleri satırı', () {
    testWidgets('iki satırlık fon başlığında taşma OLMAZ', (tester) async {
      // Kullanıcının ekran görüntüsündeki senaryo: uzun TEFAS fon adı.
      await tester.pumpWidget(buildRow(
        title: 'TEFAS:YKT Yapı Kredi Portföy Teknoloji Fonu',
        titleMaxLines: 2,
        minified: true,
      ));
      expect(tester.takeException(), isNull,
          reason: 'satır taşmamalı — sol kolon içeriğe göre boyutlanmalı');
    });

    testWidgets('tek satırlık hisse başlığında taşma olmaz', (tester) async {
      await tester.pumpWidget(buildRow(
        title: 'THYAO',
        titleMaxLines: 1,
        minified: true,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('temettü satırında (miktar rozeti yok) taşma olmaz',
        (tester) async {
      await tester.pumpWidget(buildRow(
        title: 'THYAO',
        titleMaxLines: 1,
        minified: true,
        showQtyBadge: false,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('dar ekranda da taşma olmaz', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(buildRow(
        title: 'TEFAS:IJC İş Portföy Çoklu Varlık Değişken Fon',
        titleMaxLines: 2,
        minified: true,
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
