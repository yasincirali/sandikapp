import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/main_navigation_screen.dart';

/// Sekme isteğinin GERÇEKTEN uygulandığı — `IndexedStack` davranışı.
///
/// Diğer iki dosya (`sekme_istegi_test`, `deep_link_router_test`) kanalı
/// ve eşlemeyi ölçüyor; burada eksik kalan halka kapatılıyor: istek
/// geldiğinde görünen çocuk gerçekten değişiyor mu?
///
/// `MainNavigationScreen`'in kendisi kurulamıyor — Supabase, portföy
/// sağlayıcısı ve ağ ister. Bu yüzden ekranın KULLANDIĞI mekanizmanın
/// aynısı (statik `ValueNotifier` → `setState` → `IndexedStack.index`)
/// birebir kurulup doğrulanıyor. Emülatör Flutter'ı render edemediği için
/// (bkz. CLAUDE.md) gözle doğrulamanın başka yolu yok.
class _SahteKabuk extends StatefulWidget {
  const _SahteKabuk();

  @override
  State<_SahteKabuk> createState() => _SahteKabukState();
}

class _SahteKabukState extends State<_SahteKabuk> {
  int _index = 0;

  // `MainNavigationScreen._screens` ile AYNI uzunluk — aralık denetimi
  // gerçekçi olsun.
  static const _ekranSayisi = 5;

  @override
  void initState() {
    super.initState();
    MainNavigationScreen.sekmeIstegi.addListener(_geldi);
    if (MainNavigationScreen.sekmeIstegi.value != null) {
      Future.microtask(_geldi);
    }
  }

  @override
  void dispose() {
    MainNavigationScreen.sekmeIstegi.removeListener(_geldi);
    super.dispose();
  }

  void _geldi() {
    final hedef = MainNavigationScreen.sekmeIstegi.value;
    if (hedef == null) return;
    MainNavigationScreen.sekmeIstegi.value = null;
    if (hedef < 0 || hedef >= _ekranSayisi) return;
    if (!mounted) return;
    setState(() => _index = hedef);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _ekranSayisi; i++) Text('ekran-$i'),
          ],
        ),
      );
}

/// `IndexedStack` tüm çocukları ağaçta tutar; görünen olanı bulmak için
/// `Visibility`/`Offstage` durumuna bakmak gerekir.
int _gorunenIndeks(WidgetTester tester) {
  final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
  return stack.index ?? -1;
}

void main() {
  setUp(() => MainNavigationScreen.sekmeIstegi.value = null);
  tearDown(() => MainNavigationScreen.sekmeIstegi.value = null);

  testWidgets('uygulama AÇIKKEN gelen istek sekmeyi değiştirir',
      (tester) async {
    await tester.pumpWidget(const _SahteKabuk());
    expect(_gorunenIndeks(tester), 0, reason: 'Başlangıç sekmesi Ana olmalı.');

    MainNavigationScreen.sekmeIstegi.value =
        MainNavigationScreen.performansSekmesi;
    await tester.pumpAndSettle();

    expect(_gorunenIndeks(tester), MainNavigationScreen.performansSekmesi,
        reason: 'Widget/Canlı Etkinlik dokunuşu performans sekmesini '
            'açmalı.');
  });

  testWidgets('SOĞUK açılış: ekran kurulmadan önce yazılan istek uygulanır',
      (tester) async {
    // Gerçek senaryo: uygulama kapalıyken widget'a dokunulur. URI,
    // `MainNavigationScreen` daha kurulmadan okunur.
    MainNavigationScreen.sekmeIstegi.value =
        MainNavigationScreen.performansSekmesi;

    await tester.pumpWidget(const _SahteKabuk());
    await tester.pumpAndSettle();

    expect(_gorunenIndeks(tester), MainNavigationScreen.performansSekmesi,
        reason: 'Soğuk açılışta dokunuş kayboluyor — yalnızca dinlemek '
            'yetmez, mevcut değer de okunmalı.');
  });

  testWidgets('istek TÜKETİLİR — kullanıcı sonra başka sekmeye geçebilir',
      (tester) async {
    await tester.pumpWidget(const _SahteKabuk());
    MainNavigationScreen.sekmeIstegi.value =
        MainNavigationScreen.performansSekmesi;
    await tester.pumpAndSettle();

    expect(MainNavigationScreen.sekmeIstegi.value, isNull,
        reason: 'İstek tüketilmemiş; ekran yeniden kurulduğunda eski '
            'dokunuş tekrar uygulanır ve kullanıcı sekmede kilitlenir.');
  });

  testWidgets('aralık dışı hedef ÇÖKERTMEZ ve sekmeyi bozmaz',
      (tester) async {
    await tester.pumpWidget(const _SahteKabuk());

    for (final kotu in [-1, 99, 5]) {
      MainNavigationScreen.sekmeIstegi.value = kotu;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$kotu çökertiyor.');
      expect(_gorunenIndeks(tester), 0,
          reason: '$kotu sekmeyi değiştirmemeli.');
    }
  });
}
