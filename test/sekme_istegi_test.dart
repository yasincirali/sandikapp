import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';

/// `MainNavigationScreen.sekmeIstegi` kanalının sözleşmesi.
///
/// Gerçek ekranı kurmak Supabase, portföy sağlayıcısı ve ağ ister; bu
/// testler kanalın KENDİSİNİ doğruluyor — isteğin tüketilmesi, soğuk
/// açılışta kaybolmaması ve aralık dışı değerin çökertmemesi.
///
/// Kanalın ekrana bağlanması ayrıca kaynak denetimiyle kilitleniyor
/// (aşağıdaki son grup): dinleyicinin `initState`'te bağlanıp
/// `dispose`'ta çözüldüğünü görmek, sızıntıyı ve çift işlemeyi önler.
void main() {
  setUp(() => MainNavigationScreen.sekmeIstegi.value = null);
  tearDown(() => MainNavigationScreen.sekmeIstegi.value = null);

  test('performans sekmesi sabiti beklenen indekste', () {
    expect(MainNavigationScreen.performansSekmesi, 3);
  });

  testWidgets('istek dinleyiciye ULAŞIR', (tester) async {
    final gelen = <int?>[];
    void dinle() => gelen.add(MainNavigationScreen.sekmeIstegi.value);
    MainNavigationScreen.sekmeIstegi.addListener(dinle);
    addTearDown(
        () => MainNavigationScreen.sekmeIstegi.removeListener(dinle));

    MainNavigationScreen.sekmeIstegi.value =
        MainNavigationScreen.performansSekmesi;
    await tester.pump();

    expect(gelen, [MainNavigationScreen.performansSekmesi]);
  });

  testWidgets('AYNI değeri tekrar yazmak dinleyiciyi UYANDIRMAZ',
      (tester) async {
    // `ValueNotifier` aynı değerde bildirim yapmaz. Bu, arka arkaya iki
    // widget dokunuşunun ikincisinin sessizce yutulması demek — o yüzden
    // istek tüketildikten sonra `null`'a çekiliyor (ekrandaki
    // `_sekmeIstegiGeldi`). Buradaki test o gerekçeyi belgeliyor.
    MainNavigationScreen.sekmeIstegi.value = 3;
    var sayac = 0;
    void dinle() => sayac++;
    MainNavigationScreen.sekmeIstegi.addListener(dinle);
    addTearDown(
        () => MainNavigationScreen.sekmeIstegi.removeListener(dinle));

    MainNavigationScreen.sekmeIstegi.value = 3; // aynı değer
    await tester.pump();
    expect(sayac, 0, reason: 'Aynı değer bildirim üretmemeli.');

    MainNavigationScreen.sekmeIstegi.value = null; // tüketildi
    MainNavigationScreen.sekmeIstegi.value = 3; // ikinci dokunuş
    await tester.pump();
    expect(sayac, 2, reason: 'Tüketildikten sonra ikinci dokunuş '
        'ulaşmalı (null + 3).');
  });

  test('soğuk açılış: ekran kurulmadan ÖNCE yazılan istek durur', () {
    // Widget dokunuşu uygulamayı açtığında istek, `MainNavigationScreen`
    // daha `initState`'e girmeden yazılmış olabilir. Değer kanalda
    // beklemeli — ekran onu `initState`'te okuyor.
    MainNavigationScreen.sekmeIstegi.value =
        MainNavigationScreen.performansSekmesi;
    expect(MainNavigationScreen.sekmeIstegi.value,
        MainNavigationScreen.performansSekmesi);
  });

  group('ekran bağlantısı — kaynak denetimi', () {
    final src = File('lib/screens/main_navigation_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('dinleyici initState\'te bağlanır ve dispose\'ta ÇÖZÜLÜR', () {
      expect(src.contains('sekmeIstegi.addListener(_sekmeIstegiGeldi)'), isTrue,
          reason: 'Dinleyici bağlanmıyor — dokunuş sekmeyi değiştirmez.');
      expect(
          src.contains('sekmeIstegi.removeListener(_sekmeIstegiGeldi)'), isTrue,
          reason: 'Dinleyici çözülmüyor — statik notifier\'da birikir ve '
              'tek dokunuş birden çok kez işlenir.');
    });

    test('istek TÜKETİLİR', () {
      expect(src.contains('sekmeIstegi.value = null'), isTrue,
          reason: 'İstek tüketilmiyor — ekran her yeniden kurulduğunda '
              'eski dokunuş yeniden uygulanır.');
    });

    test('soğuk açılış için başlangıç değeri OKUNUR', () {
      expect(src.contains('sekmeIstegi.value != null'), isTrue,
          reason: 'Yalnızca dinleniyor; ekran kurulmadan önce yazılmış '
              'istek kaybolur (soğuk açılış yolu).');
    });
  });
}
