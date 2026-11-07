import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/cevrimdisi_provider.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';

/// Hata ekranı bağlantı dönünce BİR KEZ kendiliğinden dener (rapor
/// 2026-11-08 02:30 #1).
///
/// Kilitlenen kurallar:
///   1. Görünüm açıkken çevrimdışı → çevrimiçi geçişi [onRetry]'ı bir kez
///      çağırır ve deneme düğmeyle aynı kayda (`HataDenemeKaydi`) yazılır.
///   2. Geçiş yoksa (görünüm hiç çevrimdışı görmedi) deneme yok.
///   3. Geçiş başına tek deneme, döngü yok; yeni deneme ancak yeni bir
///      kopma → dönüş geçişiyle.
///   4. ProviderScope kurmayan sahnede görünüm bugünkü gibi çalışır.
void main() {
  tearDown(HataDenemeKaydi.sifirlaTest);

  Future<ProviderContainer> kur(
    WidgetTester t, {
    required VoidCallback onRetry,
    bool basktaCevrimdisi = false,
  }) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    if (basktaCevrimdisi) c.read(cevrimdisiProvider.notifier).agHatasi();
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Scaffold(
          body: SandikErrorView(
            error: Exception('x'),
            onRetry: onRetry,
            ekranAdi: 'test_ekrani',
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('çevrimdışı → çevrimiçi geçişi bir kez yeniden dener', (t) async {
    var deneme = 0;
    final c = await kur(t, onRetry: () => deneme++);
    c.read(cevrimdisiProvider.notifier).agHatasi();
    await t.pump();
    expect(deneme, 0, reason: 'kopma anında deneme yok');

    c.read(cevrimdisiProvider.notifier).baglandi();
    await t.pump();
    expect(deneme, 1);
    // Düğmeyle aynı yol: deneme kaydı yazıldı, yeni hata görünümü "bize
    // yaz" bağlantısını gösterecek.
    expect(
        HataDenemeKaydi.bagGorunsunMu('test_ekrani',
            HataDenemeKaydi.now().add(const Duration(seconds: 1))),
        isTrue);
  });

  testWidgets('görünüm kurulurken zaten çevrimdışıysa dönüş de tetikler',
      (t) async {
    var deneme = 0;
    final c = await kur(t, onRetry: () => deneme++, basktaCevrimdisi: true);
    c.read(cevrimdisiProvider.notifier).baglandi();
    await t.pump();
    expect(deneme, 1);
  });

  testWidgets('geçiş olmadan kendiliğinden deneme yok', (t) async {
    var deneme = 0;
    final c = await kur(t, onRetry: () => deneme++);
    // Zaten çevrimiçi: `baglandi` durum değiştirmez, geçiş yok.
    c.read(cevrimdisiProvider.notifier).baglandi();
    await t.pump(const Duration(seconds: 5));
    expect(deneme, 0);
    expect(HataDenemeKaydi.sonradanDenendiMi('test_ekrani', DateTime(2000)),
        isFalse);
  });

  testWidgets('geçiş başına tek deneme; ikincisi yeni kopma ister', (t) async {
    var deneme = 0;
    final c = await kur(t, onRetry: () => deneme++);
    final n = c.read(cevrimdisiProvider.notifier);
    n.agHatasi();
    await t.pump();
    n.baglandi();
    await t.pump();
    // Aynı dönüşün ardından gelen çevrimiçi turlar yeni deneme açmaz.
    n.baglandi();
    await t.pump(const Duration(seconds: 5));
    expect(deneme, 1);

    // Yeni kopma → dönüş: bir deneme daha, yine yalnız bir.
    n.agHatasi();
    await t.pump();
    n.agHatasi();
    await t.pump();
    n.baglandi();
    await t.pump();
    expect(deneme, 2);
  });

  testWidgets('ProviderScope yoksa görünüm düğmeyle çalışmaya devam eder',
      (t) async {
    var deneme = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SandikErrorView(error: Exception('x'), onRetry: () => deneme++),
      ),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Tekrar dene'));
    expect(deneme, 1);
  });
}
