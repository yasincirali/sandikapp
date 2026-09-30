import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/kaydirmali_gecis.dart';

/// Toplam kartındaki kaydırmalı geçiş: eşiği geçen sürükleme yön bildirir,
/// geçmeyen iptal olur; sürüklerken kenarda hedef adı görünür; "hareketi
/// azalt" açıkken de geçiş çalışır.
void main() {
  Widget kur({
    required ValueChanged<bool> onGecis,
    bool reduce = false,
    bool ipucu = false,
    VoidCallback? onIpucu,
  }) =>
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.light]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: KaydirmaliGecis(
                  etkin: true,
                  onGecis: onGecis,
                  ipucu: ipucu,
                  onIpucuGosterildi: onIpucu,
                  // Komşu kart: sürüklerken yanda görünen içerik.
                  komsu: (ileri) => SizedBox(
                      height: 120, child: Text(ileri ? 'Ayşe' : 'Birlikte')),
                  child: const SizedBox(height: 120, child: Text('kart')),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('eşiği geçen sola kaydırma ileri bildirir, kenarda hedef adı',
      (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    final g = await t.startGesture(t.getCenter(find.text('kart')));
    await g.moveBy(const Offset(-120, 0));
    await t.pump();
    expect(find.text('Ayşe'), findsOneWidget,
        reason: 'sürüklerken komşu kart görünür');
    await g.up();
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });

  testWidgets('eşiğin altında kalan sürükleme iptal — geri yaylanır', (t) async {
    var cagrildi = false;
    await t.pumpWidget(kur(onGecis: (_) => cagrildi = true));
    await t.drag(find.text('kart'), const Offset(-30, 0));
    await t.pumpAndSettle();
    expect(cagrildi, isFalse);
    expect(find.text('Ayşe'), findsNothing,
        reason: 'yaylanınca komşu kart pencereden çıkar');
  });

  // Animasyon denetimi 2026-10-01: eşiği geçtikten sonra TERS yöne
  // fırlatmak "vazgeçtim"dir; eskiden hızın yönüne bakılmıyordu.
  testWidgets('eşiği geçip ters yöne fırlatmak iptal eder', (t) async {
    var cagrildi = false;
    await t.pumpWidget(kur(onGecis: (_) => cagrildi = true));
    final g = await t.startGesture(t.getCenter(find.text('kart')));
    // Yavaşça eşiğin ötesine (320 × 0,3 = 96 pt).
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-10, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    // Sonra hızla sağa fiske.
    await g.moveBy(const Offset(20, 0));
    await t.pump(const Duration(milliseconds: 8));
    await g.moveBy(const Offset(20, 0));
    await t.pump(const Duration(milliseconds: 8));
    await g.up();
    await t.pumpAndSettle();
    expect(cagrildi, isFalse);
    expect(find.text('Ayşe'), findsNothing);
  });

  testWidgets('kısa hızlı fiske eşiği geçmeden de ilerletir', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    await t.fling(find.text('kart'), const Offset(-60, 0), 800);
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });

  testWidgets('bırakma animasyonunu parmakla yakalamak takılı bırakmaz',
      (t) async {
    var sayac = 0;
    await t.pumpWidget(kur(onGecis: (_) => sayac++));
    await t.drag(find.text('kart'), const Offset(-40, 0));
    await t.pump(const Duration(milliseconds: 30));
    // Geri yaylanırken yakala, bu kez eşiği geç.
    await t.drag(find.text('kart'), const Offset(-160, 0));
    await t.pumpAndSettle();
    expect(sayac, 1);
    expect(find.text('Ayşe'), findsNothing,
        reason: 'geçiş bitince kayma sıfırlanır, komşu pencereden çıkar');
  });

  testWidgets('sağa kaydırma geri yönü bildirir', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v));
    await t.drag(find.text('kart'), const Offset(160, 0));
    await t.pumpAndSettle();
    expect(yon, isFalse);
  });

  // Tek seferlik göz kırpma (2026-09-21): ilk açılışta kart sola kayıp
  // geri gelir, o an hedef adı görünür; tercih bir kez işaretlenir.
  testWidgets('ipucu: kart göz kırpar, hedef adı belirir, tercih işaretlenir',
      (t) async {
    var isaret = 0;
    await t.pumpWidget(kur(onGecis: (_) {}, ipucu: true, onIpucu: () => isaret++));
    expect(isaret, 1);
    expect(find.text('Ayşe'), findsNothing);
    // Bekleme (3× surface) + sola kayış: rozet görünür.
    await t.pump(SandikMotion.surface * 3);
    await t.pump(SandikMotion.surface);
    expect(find.text('Ayşe'), findsOneWidget);
    // Bekleme (2× surface) zamanlayıcıyla geçer; pumpAndSettle kare bekler,
    // zamanlayıcı beklemez — önce süreyi ilerlet.
    // Bekleme zamanlayıcı ile geçer, geri dönüş kare ile; ikisini de adım
    // adım ilerlet (pumpAndSettle zamanlayıcı beklemez).
    for (var i = 0; i < 12 && find.text('Ayşe').evaluate().isNotEmpty; i++) {
      await t.pump(SandikMotion.surface);
    }
    await t.pumpAndSettle();
    expect(find.text('Ayşe'), findsNothing, reason: 'geri gelince kaybolur');
    expect(isaret, 1);
  });

  testWidgets('ipucu: hareketi azalt açıkken oynamaz, yine işaretlenir',
      (t) async {
    var isaret = 0;
    await t.pumpWidget(kur(
        onGecis: (_) {}, ipucu: true, reduce: true, onIpucu: () => isaret++));
    await t.pumpAndSettle();
    expect(isaret, 1);
    expect(find.text('Ayşe'), findsNothing);
  });

  testWidgets('hareketi azalt açıkken geçiş yine çalışır', (t) async {
    bool? yon;
    await t.pumpWidget(kur(onGecis: (v) => yon = v, reduce: true));
    await t.drag(find.text('kart'), const Offset(-160, 0));
    await t.pumpAndSettle();
    expect(yon, isTrue);
  });

  // Pürüzsüzlük (2026-09-21): sürükleme karesi ne komşu kartı yeniden
  // kurmalı ne de kartın kendisini. Komşu yön başına BİR KEZ istenir; kart
  // widget'ı sürükleme boyunca aynı örnek kalır (yalnızca ötelenir).
  testWidgets('sürüklerken komşu kart bir kez kurulur, kart yeniden kurulmaz',
      (t) async {
    var komsuSayisi = 0;
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [SandikPalette.light]),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: KaydirmaliGecis(
              etkin: true,
              onGecis: (_) {},
              komsu: (ileri) {
                komsuSayisi++;
                return const SizedBox(height: 120, child: Text('Ayşe'));
              },
              child: const SizedBox(height: 120, child: Text('kart')),
            ),
          ),
        ),
      ),
    ));
    final kartOnce = t.widget(find.text('kart'));
    final g = await t.startGesture(t.getCenter(find.text('kart')));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-10, 0));
      await t.pump();
    }
    expect(find.text('Ayşe'), findsOneWidget);
    expect(komsuSayisi, 1, reason: 'Komşu her karede yeniden kurulmamalı.');
    expect(identical(t.widget(find.text('kart')), kartOnce), isTrue,
        reason: 'Kart widget\'ı sürüklerken aynı örnek kalmalı.');
    await g.up();
    await t.pumpAndSettle();
  });

  // Animasyon denetimi 2026-10-01: görünüm çipten (kaydırma dışında)
  // değişince kart yönlü kısa bir girişle gelir; kaydırmanın kendi geçişinde
  // bu giriş OYNAMAZ (karusel zaten oynadı).
  group('çipten görünüm değişimi', () {
    Widget kurSira(int sira, ValueChanged<bool> onGecis) => MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.light]),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: KaydirmaliGecis(
                  etkin: true,
                  sira: sira,
                  onGecis: onGecis,
                  komsu: (_) => const SizedBox(height: 120),
                  child: const SizedBox(height: 120, child: Text('kart')),
                ),
              ),
            ),
          ),
        );

    double kayma(WidgetTester t) {
      final tr = t.widgetList<Transform>(find.ancestor(
          of: find.text('kart'), matching: find.byType(Transform)));
      return tr.fold<double>(
          0, (m, e) => m + e.transform.getTranslation().x.abs());
    }

    testWidgets('çip sırayı değiştirince kart yandan kayarak gelir',
        (t) async {
      await t.pumpWidget(kurSira(0, (_) {}));
      await t.pumpWidget(kurSira(2, (_) {}));
      await t.pump(const Duration(milliseconds: 40));
      expect(kayma(t), greaterThan(0), reason: 'giriş oynamalı');
      await t.pumpAndSettle();
      expect(kayma(t), 0);
    });

    testWidgets('kaydırmanın kendi geçişinde giriş oynamaz', (t) async {
      var sira = 0;
      late StateSetter yenile;
      await t.pumpWidget(StatefulBuilder(builder: (c, s) {
        yenile = s;
        return kurSira(sira, (ileri) => yenile(() => sira = 1));
      }));
      await t.drag(find.text('kart'), const Offset(-200, 0));
      // Yay bitip görünüm değişene kadar ilerle (karusel kendi kaymasını
      // oynatır — o ölçülmez).
      for (var i = 0; i < 120 && sira == 0; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(sira, 1);
      await t.pump(const Duration(milliseconds: 40));
      expect(kayma(t), 0, reason: 'karusel oynadı; ikinci giriş olmamalı');
      await t.pumpAndSettle();
    });
  });
}
