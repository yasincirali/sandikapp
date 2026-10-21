import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tazelik_ritmi.dart';

import 'helpers/kaynak.dart';

/// Piyasa kapalıyken fiyat turunun seyrelmesi (Ar-Ge 16:45 #2, 2026-10-21):
/// yalnız borsa portföyü + seans dışında tur 5 dk'da bir; dinleyiciler her
/// nabızda atmaya devam eder; karar verilemezse eski ritim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nabiz = TazelikRitmi.nabiz;
  var simdi = DateTime(2026, 10, 24, 23); // cumartesi gecesi

  setUp(() => nabiz.saat = () => simdi);
  tearDown(() => nabiz.saat = DateTime.now);

  test('sakinken tur 5 dk dolmadan tekrar atılmaz, dinleyici her nabızda atar',
      () async {
    var tur = 0, dinleyici = 0;
    final coz = nabiz.fiyatTuruBagla(() async => tur++, sakinMi: () => true);
    final b = nabiz.dinle(() => dinleyici++);
    addTearDown(() {
      coz();
      b();
    });

    await nabiz.atForTest(); // ilk nabız her zaman tur atar
    simdi = simdi.add(TazelikRitmi.yuzey);
    await nabiz.atForTest();
    simdi = simdi.add(TazelikRitmi.yuzey);
    await nabiz.atForTest();
    expect(tur, 1);
    expect(dinleyici, 3);

    simdi = simdi.add(TazelikRitmi.sakinTur);
    await nabiz.atForTest();
    expect(tur, 2);
  });

  test('sakin değilse (karışık portföy ya da seans açık) her nabızda tur',
      () async {
    var tur = 0;
    final coz = nabiz.fiyatTuruBagla(() async => tur++, sakinMi: () => false);
    addTearDown(coz);
    for (var i = 0; i < 3; i++) {
      await nabiz.atForTest();
      simdi = simdi.add(TazelikRitmi.yuzey);
    }
    expect(tur, 3);
  });

  test('karar fırlatırsa eski ritim sürer', () async {
    var tur = 0;
    final coz = nabiz.fiyatTuruBagla(() async => tur++,
        sakinMi: () => throw StateError('portföy yok'));
    addTearDown(coz);
    await nabiz.atForTest();
    simdi = simdi.add(TazelikRitmi.yuzey);
    await nabiz.atForTest();
    expect(tur, 2);
  });

  test('sakin aralık temele hizalı ve kural "BORSA KAPALI" ile aynı', () {
    expect(TazelikRitmi.hizali(TazelikRitmi.sakinTur), isTrue);
    final kabuk = ekranKaynagiSync('lib/screens/main_navigation_screen.dart');
    expect(kabuk, contains('yalnizcaBorsaVarliklardan(varliklar)'));
    expect(kabuk, contains('BugunService.seansAcikMi('));
  });
}
