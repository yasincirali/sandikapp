import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Sistem **"Kalın Metin"** ayarı desteği.
///
/// iOS: Ayarlar → Erişilebilirlik → Ekran ve Metin Boyutu → Kalın Metin.
/// Android'de de karşılığı var (`boldText`).
///
/// Denetimde (2026-08-10) bulundu: `MediaQuery.highContrastOf` destekleniyordu
/// ama `boldTextOf` hiçbir yerde okunmuyordu — bu ayarı açan kullanıcı için
/// hiçbir şey değişmiyordu.
///
/// Çözüm `context.t` içinde: tüm metin stilleri zaten oradan geçiyor, tek
/// noktada çözülür. `context.c`'nin `highContrast` için yaptığının aynısı.
///
/// **Neden `FontWeight.bold` sabiti değil:** marka tipografisi w500–w900
/// arası beş ağırlık kullanıyor. Hepsini w700'e eşitlemek hiyerarşiyi
/// düzleştirir — w800 başlık ile w500 gövde ayırt edilemez hale gelir.
void main() {
  /// Verilen ayarla `context.t`'yi çözer.
  Future<TextTheme> resolve(WidgetTester tester, {required bool bold}) async {
    late TextTheme captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(
            headlineLarge: TextStyle(fontWeight: FontWeight.w800),
            titleMedium: TextStyle(fontWeight: FontWeight.w600),
            bodyMedium: TextStyle(fontWeight: FontWeight.w400),
            labelSmall: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(boldText: bold),
          child: Builder(builder: (context) {
            captured = context.t;
            return const SizedBox();
          }),
        ),
      ),
    );
    return captured;
  }

  testWidgets('kapalıyken ağırlıklar değişmez', (t) async {
    final tt = await resolve(t, bold: false);
    expect(tt.headlineLarge?.fontWeight, FontWeight.w800);
    expect(tt.titleMedium?.fontWeight, FontWeight.w600);
    expect(tt.bodyMedium?.fontWeight, FontWeight.w400);
  });

  testWidgets('açıkken her ağırlık artar', (t) async {
    final tt = await resolve(t, bold: true);
    // w400 iki kademe atlar (w500 gözle fark edilmiyor).
    expect(tt.bodyMedium?.fontWeight, FontWeight.w600);
    // Üst kademeler tek adım.
    expect(tt.titleMedium?.fontWeight, FontWeight.w700);
    expect(tt.headlineLarge?.fontWeight, FontWeight.w900);
  });

  testWidgets('w900 tavanda kalır — taşmaz', (t) async {
    final tt = await resolve(t, bold: true);
    expect(tt.labelSmall?.fontWeight, FontWeight.w900);
  });

  testWidgets('hiyerarşi korunur — hepsi tek ağırlığa çökmez', (t) async {
    final tt = await resolve(t, bold: true);
    final weights = <int>{
      tt.bodyMedium!.fontWeight!.value,
      tt.titleMedium!.fontWeight!.value,
      tt.headlineLarge!.fontWeight!.value,
    };
    expect(weights.length, greaterThan(1),
        reason: 'Ağırlıklar tek değere çökerse başlık/gövde ayrımı kaybolur. '
            'FontWeight.bold sabiti tam olarak bunu yapardı.');
    // Sıralama da bozulmamalı.
    expect(tt.bodyMedium!.fontWeight!.value,
        lessThan(tt.headlineLarge!.fontWeight!.value));
  });
}
