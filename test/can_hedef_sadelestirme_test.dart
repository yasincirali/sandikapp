import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/hedef_sheet.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Çan ve hedef sayfası (Ar-Ge 2 Kas 08:45 #1-#3, müşteri raporu 09:15 YAP).
///
/// Kilitlenenler:
/// 1. Hazır hedefler portföyün ÜSTÜNDEN gelir; bakiye gizliyken ya da değer
///    bilinmiyorken sabit dört (türetilmiş çip toplamı ele verirdi).
/// 2. Önizleme Bugün kartıyla aynı oranı yazar; gizliyken tutar yok.
/// 3. Çanda "hepsini sil" kapsam sorusu yok; boş çan alarm kurdurur; yasal
///    uyarı listenin sonunda, tam metin.
void main() {
  group('hazirHedefler', () {
    test('portföyün üstündeki ilk dört basamak', () {
      expect(hazirHedefler(484020), [500000, 750000, 1000000, 1500000]);
      expect(hazirHedefler(60000), [100000, 250000, 500000, 750000]);
    });

    test('geçilmiş tutar önerilmez; merdiven sonunda kalanlar', () {
      expect(hazirHedefler(20000000), [25000000, 50000000]);
      expect(hazirHedefler(60000000), isEmpty);
    });

    test('gizli ya da bilinmeyen değer: sabit dört', () {
      expect(hazirHedefler(484020, gizli: true),
          [250000, 500000, 1000000, 2500000]);
      expect(hazirHedefler(null), [250000, 500000, 1000000, 2500000]);
      expect(hazirHedefler(0), [250000, 500000, 1000000, 2500000]);
    });
  });

  group('hedef sayfası', () {
    Future<void> ac(WidgetTester tester, {bool gizli = false}) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    showHedefSheet(context, ref, deger: 484020, gizli: gizli),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    testWidgets('çip seçilince önizleme oranı ve kalanı yazar', (tester) async {
      await ac(tester);
      expect(find.text('₺250K'), findsNothing); // geçilmiş tutar yok
      await tester.tap(find.text('₺750K'));
      await tester.pumpAndSettle();
      final cip = tester.widget<SandikFiltreCipi>(find.ancestor(
          of: find.text('₺750K'), matching: find.byType(SandikFiltreCipi)));
      expect(cip.secili, isTrue);
      expect(find.textContaining('%65 tamam'), findsOneWidget);
      expect(find.textContaining('kaldı'), findsOneWidget);
    });

    testWidgets('bakiye gizliyken önizlemede tutar yok', (tester) async {
      await ac(tester, gizli: true);
      await tester.tap(find.text('₺1M'));
      await tester.pumpAndSettle();
      expect(find.text('%48 tamam'), findsOneWidget);
      expect(find.textContaining('484'), findsNothing);
    });

    testWidgets('geçilmiş hedef yazılınca "zaten geçtin"', (tester) async {
      await ac(tester);
      await tester.enterText(find.byType(TextField), '100.000');
      await tester.pumpAndSettle();
      expect(find.textContaining('zaten geçtin'), findsOneWidget);
    });
  });

  group('çan sayfası (kaynak)', () {
    final k = ekranKaynagiSync('lib/screens/home_screen.dart');

    test('kapsam sorusu ve "hepsini sil" yolu yok', () {
      expect(k.contains('_kapsamSor'), isFalse);
      expect(k.contains('onDeleteAll'), isFalse);
      expect(k.contains("'Hepsini sil"), isFalse);
    });

    test('boş çan alarm kurdurur, aday listesi Alarmlarım ile ortak', () {
      expect(k, contains('alarmKurAkisi(context, ref,'));
      expect(k, contains('adaylar: alarmAdaylari(ref)'));
      expect(k.contains('check_circle_outline_rounded'), isFalse,
          reason: 'boş çanda yeşil onay yok');
    });

    // 2026-11-10: tam kutu yerine kısa biçim (tek satır + "Ayrıntı"; tam
    // metin alt sayfada). Sabitlenmeme kuralı aynı.
    test('yasal uyarı kısa biçimde, sayfanın dibine sabit değil', () {
      expect(k, contains('const DisclaimerWidget(kisa: true)'));
      expect(
          k.contains(
              'child: DisclaimerWidget(kisa: true),\n              ),\n            ],'),
          isFalse);
    });
  });
}
