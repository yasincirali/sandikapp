import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/yasal_adimlar.dart';

/// Kayıt ekranı ve yeniden onay kapısı ortak adım listesinin
/// (`YasalAdimListesi`, 2026-10-05) test yardımcıları.

/// `pushGuarded`'ın çift dokunma penceresi GERÇEK saatle ölçülür (500 ms);
/// önceki itme pencerede kalmasın.
Future<void> gercekBekle(WidgetTester tester) => tester
    .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 550)));

/// Uyarı / Açık Rıza adımlarının işaretlenmemiş kutusu (2026-11-20'den
/// beri zorunlu okuma yok: adımda metin bağlantısı + kendi kutusu). Kayıt
/// kutusu da [YasalIsaretSatiri]'dır ama bağlantılı cümlesi (`span`) var.
final Finder bekleyenOkumaKutusu = find.byWidgetPredicate(
    (w) => w is YasalIsaretSatiri && !w.isaretli && w.span == null);

/// Sıradaki uyarı / Açık Rıza adımlarını [adet] kez kutusundan onaylar.
/// Liste tembel kurulabilir (dar ekran): her seferinde kutu görünene kadar
/// kaydırılır.
Future<void> adimlariOnayla(WidgetTester tester, {required int adet}) async {
  for (var i = 0; i < adet; i++) {
    // `.first` kaydırmadan SONRA: kurulmamış listede boş bulucuya `.first`
    // hata verir.
    await tester.scrollUntilVisible(bekleyenOkumaKutusu, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(bekleyenOkumaKutusu.first);
    await tester.pumpAndSettle();
  }
}
