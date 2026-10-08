import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';

/// Kayıt ekranı ve yeniden onay kapısı ortak adım listesinin
/// (`YasalAdimListesi`, 2026-10-05) test yardımcıları.

/// `pushGuarded`'ın çift dokunma penceresi GERÇEK saatle ölçülür (500 ms);
/// önceki itme pencerede kalmasın.
Future<void> gercekBekle(WidgetTester tester) => tester
    .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 550)));

/// Sıradaki okuma adımlarını ("Oku ve onayla" — [dugme] o dildeki etiket)
/// [adet] kez açar ve okuyucuyu "sonuna kadar okundu, onaylandı" ile
/// kapatır. Liste tembel kurulur (dar ekranda düğme henüz kurulmamış
/// olabilir): her seferinde düğme görünene kadar kaydırılır. Kaydırma
/// mekaniği `zorunlu_okuma_test`'te; burada akış sınanır.
Future<void> adimlariOku(WidgetTester tester, String dugme,
    {required int adet}) async {
  for (var i = 0; i < adet; i++) {
    final d = find.text(dugme);
    await tester.scrollUntilVisible(d, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await gercekBekle(tester);
    await tester.tap(d);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(LegalDocScreen))).pop(
        const ZorunluOkumaSonucu(onaylandi: true, sonunaKadarOkundu: true));
    await tester.pumpAndSettle();
  }
}
