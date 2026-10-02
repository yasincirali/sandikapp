import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';

import 'helpers/kaynak.dart';

/// Tanıtım turu "Zirvedeki portföyler" adımı kartı GÖSTERİR (2026-10-03,
/// kullanıcı bildirimi: "yazı yazıyor ama komponenti göstermeli").
///
/// Kart Performans'ın Grafik yüzeyinde, tembel listenin en altında; adım
/// yalnızca sekmeye geçiyordu, kart ağaçta olmadığı için tur kaydıracak hedef
/// bulamıyordu. Ekranın kendisi `PortfolioPerformanceScreen` state'inde,
/// tüm uygulamayı kurmadan sınanamıyor — kanal kaynakta kilitlenir
/// (`deep_link_native_uri_test` › `gunlukIstegi` ile aynı yöntem).
String _govde(String src, String imza) {
  final i = src.indexOf(imza);
  expect(i, greaterThan(0), reason: '$imza bulunamadı');
  return src.substring(i, src.indexOf('\n  }\n', i));
}

void main() {
  final tur = ekranKaynagiSync('lib/screens/onboarding_screen.dart');
  final ekran = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');

  test('zirve adımı ekrandan kartı göstermesini ister', () {
    final i = tur.indexOf("id: 'zirve'");
    expect(i, greaterThan(0));
    final adim = tur.substring(i, tur.indexOf('_Adim(', i));
    expect(adim, contains('_sekmeyeGec(3)'));
    expect(adim, contains('PortfolioPerformanceScreen.zirveIstegi.value = true'));
    // Kart yokken (bayrak kapalı / demo) adım gösterilmez.
    expect(adim, contains('globalLeaderboardEnabled'));
    expect(adim, contains('DemoModu.aktif'));
  });

  test('ekran isteği tüketir, Grafik yüzeyine geçer ve karta kaydırır', () {
    final govde = _govde(ekran, 'void _zirveIstegiGeldi()');
    expect(govde, contains('zirveIstegi.value = false'));
    expect(govde, contains('_ozetSekmesi = false'));
    expect(govde, contains('_zirveyeKaydir('));
    // Dönem / kapsam / filtre değişmez — kullanıcının seçimi korunur.
    expect(govde, isNot(contains('_selectedPeriodIdx')));
    expect(govde, isNot(contains('_view =')));
    expect(govde, isNot(contains('_typeFilter')));

    final kaydir = _govde(ekran, 'void _zirveyeKaydir(');
    expect(kaydir, contains('TourTargets.context(TourTarget.zirveKarti)'));
    expect(kaydir, contains('Scrollable.ensureVisible'));
    expect(kaydir, contains('deneme >= '), reason: 'kart yoksa sonsuz döngü olmamalı');
  });

  test('dinleyici bağlanır, bekleyen istek okunur ve dispose\'da bırakılır', () {
    expect(ekran, contains('zirveIstegi.addListener(_zirveIstegiGeldi)'));
    expect(ekran, contains('if (PortfolioPerformanceScreen.zirveIstegi.value)'));
    expect(ekran, contains('zirveIstegi.removeListener(_zirveIstegiGeldi)'));
  });

  testWidgets('aynı hedefin ikinci kopyası, ilki sökülünce devralır',
      (tester) async {
    // Tek yuvalı kayıtta ikinci kopya reddediliyor, ilki sökülünce hedef
    // ağaçta olduğu hâlde "yok" görünüyordu (Zirve adımı).
    Widget agac({required bool ilk, required bool ikinci}) => MaterialApp(
          home: Column(children: [
            if (ilk)
              const TourAnchor(
                  key: ValueKey('ilk'),
                  target: TourTarget.zirveKarti,
                  child: SizedBox(height: 10)),
            if (ikinci)
              const TourAnchor(
                  key: ValueKey('ikinci'),
                  target: TourTarget.zirveKarti,
                  child: SizedBox(height: 20)),
          ]),
        );
    await tester.pumpWidget(agac(ilk: true, ikinci: false));
    await tester.pumpWidget(agac(ilk: true, ikinci: true));
    expect(TourTargets.rect(TourTarget.zirveKarti)?.height, 10,
        reason: 'ilk canlı kopya kazanır');
    await tester.pumpWidget(agac(ilk: false, ikinci: true));
    expect(TourTargets.rect(TourTarget.zirveKarti)?.height, 20,
        reason: 'ilk gidince ikinci devralır');
    await tester.pumpWidget(agac(ilk: false, ikinci: false));
    expect(TourTargets.mounted(TourTarget.zirveKarti), isFalse);
  });

  test('dönem ve kapsam adımları Performans listesini başa kaydırır', () {
    // Liste tembel: sekme aşağıda bırakılmışsa (ya da Zirve adımından
    // "Geri" dönülürse) en üstteki seçiciler sökülüyor, tur metni hedefsiz
    // kalıyordu (kullanıcı bildirimi 2026-10-03).
    for (final id in ['donem', 'kapsam']) {
      final i = tur.indexOf("id: '$id'");
      expect(i, greaterThan(0), reason: id);
      final adim = tur.substring(i, tur.indexOf('_Adim(', i));
      expect(adim, contains('giris: (_) => _sekmeyeGecBasa(3)'), reason: id);
    }
    final yardimci = _govde(tur, 'void _sekmeyeGecBasa(int i)');
    expect(yardimci, contains('_sekmeyeGec(i)'));
    expect(yardimci, contains('SekmeBasaDon.yayinla(i)'));
  });
}
