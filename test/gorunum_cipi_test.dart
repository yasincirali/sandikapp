import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/widgets/gorunum_cipi.dart';

/// Görünüm seçici (2026-09-21, 2. tur): hızlı geçiş sırası, alt sayfa
/// sırası ve arama. Kimlik sözleşmesi: '' Ben, ortak id, null Birlikte.
AppUser _u(String id, String ad) =>
    AppUser(id: id, email: '$id@x', displayName: ad, createdAt: DateTime(2026));

void main() {
  final ortaklar = [_u('p1', 'Mehmet Yılmaz'), _u('p2', 'Ayşe Kaya'), _u('p3', 'Zeynep')];

  setUp(GorunumCipi.hafizayiSifirla);

  test('kaydırma sırası Ben → ortaklar → Birlikte, uçlarda sarar', () {
    expect(GorunumCipi.sira(ortaklar), ['', 'p1', 'p2', 'p3', null]);
    expect(GorunumCipi.sonraki(ortaklar, '', ileri: true), 'p1');
    expect(GorunumCipi.sonraki(ortaklar, 'p3', ileri: true), isNull);
    expect(GorunumCipi.sonraki(ortaklar, null, ileri: true), '');
    expect(GorunumCipi.sonraki(ortaklar, '', ileri: false), isNull);
    // Bilinmeyen kimlik (ortak ayrıldı): Ben'den sayılır.
    expect(GorunumCipi.sonraki(ortaklar, 'yok', ileri: true), 'p1');
  });

  test('alt sayfa: Birlikte, Ben, sonra ortaklar alfabetik', () {
    expect(GorunumCipi.listeSirasi(ortaklar, ''), [null, '', 'p2', 'p1', 'p3']);
  });

  test('arama yalnızca ortakları süzer; Ben ve Birlikte kalır', () {
    expect(GorunumCipi.listeSirasi(ortaklar, 'zey'), [null, '', 'p3']);
    expect(GorunumCipi.listeSirasi(ortaklar, 'AYŞE'), [null, '', 'p2']);
    expect(GorunumCipi.listeSirasi(ortaklar, 'q'), [null, '']);
  });

  Widget noktalar(int sayi, int secili, double ilerleme) => MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.light]),
        home: Scaffold(
          body: Center(
            child: SayfaNoktalari(
                sayi: sayi, secili: secili, ilerleme: ilerleme),
          ),
        ),
      );

  double genislik(WidgetTester t, int i) =>
      t.getSize(find.byKey(ValueKey('nokta-$i'))).width;

  testWidgets('noktalar: dörde kadar nokta, üstünde "i / n" yazısı', (t) async {
    await t.pumpWidget(noktalar(4, 1, 0));
    expect(genislik(t, 1), SandikSpace.smd, reason: 'seçili hap uzun');
    expect(genislik(t, 0), SandikSpace.xs);

    await t.pumpWidget(noktalar(5, 4, 0));
    expect(find.byKey(const ValueKey('nokta-0')), findsNothing);
    expect(find.text('5 / 5'), findsOneWidget);
  });

  testWidgets('noktalar: sürüklerken hap komşuya akar, uçta sarar', (t) async {
    // Yarı yolda: seçili ile sıradaki aynı genişlikte.
    await t.pumpWidget(noktalar(4, 1, -0.5));
    expect(genislik(t, 1), closeTo(genislik(t, 2), 0.01));
    expect(genislik(t, 0), SandikSpace.xs);
    // Sona gelmiş, geri: hedef ilk nokta değil, sondan bir önceki.
    await t.pumpWidget(noktalar(4, 0, 1.0));
    expect(genislik(t, 3), SandikSpace.smd);
    expect(genislik(t, 0), SandikSpace.xs);
  });

  test('ad yardımcıları', () {
    expect(GorunumCipi.ilkAd('Mehmet Yılmaz'), 'Mehmet');
    expect(GorunumCipi.basHarf('ayşe'), 'A');
    expect(GorunumCipi.basHarf('  '), '?');
  });
}
