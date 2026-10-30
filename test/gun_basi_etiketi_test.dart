import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/widgets/grafik_stili.dart';

/// Gün içi grafiğin taban çizgisi etiketi (Ar-Ge 2026-10-30 12:45 #2).
///
/// Gün içi seri 00:00'dan başlar; ilk nokta günün tabanıdır (hissede önceki
/// kapanış, #262). "AÇILIŞ · 00:00" yanlış okunuyordu: borsa 10:00'da
/// açılır. Taban sonradan başlıyorsa (bugün eklenen varlık) saat kalır.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<String> etiket(WidgetTester tester, DateTime an,
      {required bool gunIci, bool oncekiKapanis = false}) async {
    late String metin;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      metin = GrafikStili.donemBasiEtiketi(c,
          an: an,
          deger: '₺294,12',
          gunIci: gunIci,
          oncekiKapanis: oncekiKapanis);
      return const SizedBox();
    })));
    return metin;
  }

  testWidgets('hissede gece yarısı tabanı "ÖNCEKİ KAPANIŞ"', (t) async {
    expect(
        await etiket(t, DateTime(2026, 10, 29),
            gunIci: true, oncekiKapanis: true),
        'ÖNCEKİ KAPANIŞ · ₺294,12');
  });

  testWidgets('portföy ve öteki türlerde "GÜN BAŞI", saat yazılmaz', (t) async {
    expect(await etiket(t, DateTime(2026, 10, 29), gunIci: true),
        'GÜN BAŞI · ₺294,12');
  });

  testWidgets('taban gün içinde sonra başlıyorsa saat kalır', (t) async {
    expect(
        await etiket(t, DateTime(2026, 10, 29, 14, 5),
            gunIci: true, oncekiKapanis: true),
        'AÇILIŞ · 14:05 · ₺294,12');
  });

  testWidgets('gün içi dışında başlangıç tarihi', (t) async {
    expect(await etiket(t, DateTime(2026, 10, 1), gunIci: false),
        startsWith('BAŞLANGIÇ · 1 '));
  });
}
