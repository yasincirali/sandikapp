import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/onboarding_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İlk girişte gösterilen interaktif tanıtım turu.
///
/// Kullanıcı isteği (2026-09-10): tanıtım "her tanıttığı ekrana ve tuşlara
/// tuşları tek tek tanıtmalı", ayırt edici özellikler vurgulanmalı ve
/// "olan hiçbir akış bozulmamalı".
///
/// ## Neden bu testler
/// Bu ortamda cihaz yok; "aç ve bak" adımı yapılamıyor. Onun yerine tur
/// gerçekten pump edilip baştan sona TIKLANIYOR ve üç şey ölçülüyor:
///
///   1. **Akış bozulmadı.** `onComplete` / `userId` / `isCompleted` /
///      `markCompleted` ve analytics çağrıları yerinde mi (kaynak
///      denetimi) — bu ekran `main.dart`'ın açılış akışına bağlı, imzası
///      değişirse uygulama hiç açılmaz.
///   2. **Tuş tuş ilerliyor.** "İleri" bir sonraki EKRANA değil, aynı
///      ekranın bir sonraki TUŞUNA geçmeli; üst çubuktaki sayaç bunu
///      söylüyor.
///   3. **Taşma yok.** Minyatür şemalar dar ekranda (320pt) ve büyük
///      sistem yazı tipinde (2,0×) kırılmamalı. Turun HER adımı geziliyor,
///      yalnızca ilk sayfa değil.
Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  double height = 812,
  double textScale = 1.0,
  Brightness parlaklik = Brightness.dark,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final palet =
      parlaklik == Brightness.light ? SandikPalette.light : SandikPalette.dark;

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: parlaklik, extensions: [palet]),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: OnboardingScreen(onComplete: () {}, userId: 'u1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Turu sonuna kadar gez — SON adıma BASMADAN.
///
/// Son adımdaki "Sandığımı Aç" `markCompleted`'ı çağırır: SharedPreferences
/// ve Supabase yazımı. Testin konusu yerleşim, o yüzden orada durulur.
Future<int> _turuGez(WidgetTester tester) async {
  var adim = 0;
  while (find.text('İleri').evaluate().isNotEmpty) {
    expect(tester.takeException(), isNull, reason: '$adim. adımda taşma');
    await tester.tap(find.text('İleri'));
    await tester.pumpAndSettle();
    adim++;
    if (adim > 80) fail('Tur bitmedi — "İleri" hiç "Sandığımı Aç" olmadı.');
  }
  expect(find.text('Sandığımı Aç'), findsOneWidget);
  expect(tester.takeException(), isNull, reason: 'son adımda taşma');
  return adim;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tur — tuş tuş ilerleme', () {
    testWidgets('"İleri" ekranı değil, TUŞU ilerletir', (tester) async {
      await _pump(tester);
      // 1. sahne (karşılama) tek adımlık; ikinciye geç.
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();

      // Alt menü sahnesi 5 tuş anlatır. Sayaç ekranın adını ve kaçıncı
      // tuşta olduğumuzu birlikte söyler.
      expect(find.text('Alt menü · 1/5'), findsOneWidget);
      expect(find.text('Ana'), findsWidgets);

      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();

      expect(find.text('Alt menü · 2/5'), findsOneWidget,
          reason: '"İleri" sahneyi atladı — tuş tuş ilerlemesi gerekiyordu');
      expect(find.text('Portföy'), findsWidgets);
    });

    testWidgets('ilk adımda geri tuşu YOK, ikinciden sonra var',
        (tester) async {
      await _pump(tester);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);

      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    });

    testWidgets('geri, bir önceki TUŞA döner', (tester) async {
      await _pump(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('İleri'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Alt menü · 3/5'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Alt menü · 2/5'), findsOneWidget);
    });

    testWidgets('tur baştan sona gezilebiliyor ve bir kapanışı var',
        (tester) async {
      await _pump(tester);
      final adim = await _turuGez(tester);
      // Beş ekranın tuşları + karşılama + kapanış: tek sayfalık bir
      // "hoş geldiniz" ekranından çok daha fazlası olmalı.
      expect(adim, greaterThan(12),
          reason: 'Tur tuş tuş tanıtacak kadar uzun değil.');
    });
  });

  group('tur — ayırt edici özellikler', () {
    testWidgets('"BİZE ÖZEL" rozeti en az bir kez çıkar', (tester) async {
      await _pump(tester);
      var goruldu = 0;
      while (find.text('İleri').evaluate().isNotEmpty) {
        if (find.text('BİZE ÖZEL').evaluate().isNotEmpty) goruldu++;
        await tester.tap(find.text('İleri'));
        await tester.pumpAndSettle();
      }
      expect(goruldu, greaterThanOrEqualTo(3),
          reason: 'Bizi ayırt eden özellikler işaretlenmemiş.');
    });

    testWidgets('beş alt menü tuşu da adı adına tanıtılır', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();

      for (final beklenen in [
        'Ana',
        'Portföy',
        'Ortadaki + tuşu',
        'Performans',
        'Profil',
      ]) {
        expect(find.text(beklenen), findsWidgets,
            reason: '"$beklenen" adımı yok — tuşlar tek tek tanıtılmıyor');
        if (beklenen != 'Profil') {
          await tester.tap(find.text('İleri'));
          await tester.pumpAndSettle();
        }
      }
    });
  });

  group('taşma — dar ekran ve büyük yazı tipi', () {
    // Minyatür şemalar en kırılgan kısım: beş sütunlu alt menü, dört
    // etiketli dönem seçici, üç rozetli sinyal lejantı. Turun tamamı
    // geziliyor — yalnızca ilk sayfayı pump etmek bunları hiç açmazdı.
    for (final genislik in [320.0, 375.0, 430.0]) {
      for (final olcek in [1.0, 1.5, 2.0]) {
        testWidgets('${genislik.toInt()}pt @ $olcek× — tur boyunca taşmaz',
            (tester) async {
          await _pump(tester, width: genislik, textScale: olcek);
          await _turuGez(tester);
        });
      }
    }

    testWidgets('açık temada da taşmaz', (tester) async {
      await _pump(tester,
          width: 320, textScale: 1.5, parlaklik: Brightness.light);
      await _turuGez(tester);
    });

    testWidgets('kısa ekranda (SE boyu) taşmaz', (tester) async {
      // 4,7" iPhone SE: 375×667. Yükseklik en dar olan cihaz.
      await _pump(tester, width: 375, height: 667, textScale: 1.3);
      await _turuGez(tester);
    });
  });

  group('akış korundu — kaynak denetimi', _akisTestleri);
}

// ── Akış bozulmamalı ─────────────────────────────────────────────────────────
//
// Kullanıcının açık kısıtı: "Olan hiçbir akışı bozma. Sadece tanıtım
// ekranında görsel değişiklik yapmanı istiyorum." Bu ekranın dışa dönük
// yüzeyi `main.dart`'ın açılış akışına bağlı:
//
//   OnboardingScreen(onComplete: …, userId: …)
//   OnboardingScreen.isCompleted(uid)   → gösterilsin mi?
//   OnboardingScreen.markCompleted(uid) → bir daha gösterilmesin
//
// Bunlar widget testiyle doğrulanamıyor (Supabase + SharedPreferences
// istiyorlar), bu yüzden kaynak metni denetleniyor; projede aynı örüntü var
// (bkz. varlik_sinyal_karti_test.dart, sinyal_dagilimi_test.dart).
void _akisTestleri() {
  final kaynak = File('lib/screens/onboarding_screen.dart').readAsStringSync();

  test('dışa dönük imza aynen duruyor', () {
    expect(
      kaynak.contains(
          'const OnboardingScreen({super.key, required this.onComplete, required this.userId});'),
      isTrue,
      reason: 'Yapıcı imzası değişmiş — main.dart açılışta kırılır.',
    );
    expect(kaynak.contains('static Future<bool> isCompleted(String userId)'),
        isTrue);
    expect(kaynak.contains('static Future<void> markCompleted(String userId)'),
        isTrue);
  });

  test('tamamlama ve atlama hâlâ işaretleniyor', () {
    // Bu iki çağrı düşerse tanıtım HER açılışta tekrar gösterilir.
    expect(kaynak.contains('OnboardingScreen.markCompleted(widget.userId)'),
        isTrue);
    expect(kaynak.contains('logOnboardingCompleted()'), isTrue);
    expect(kaynak.contains('logOnboardingSkipped('), isTrue);
    expect(kaynak.contains('widget.onComplete()'), isTrue);
  });

  test('"Atla" hâlâ var — tur zorunlu değil', () {
    expect(kaynak.contains("'Atla'"), isTrue);
  });

  test('ekran okuyucu adım değişimini duyuruyor', () {
    // Adım değişince sayfa değişmiyor, yalnızca metin bloğu değişiyor;
    // liveRegion olmadan VoiceOver kullanıcısı "İleri"ye bastığında hiçbir
    // şey duymaz.
    expect(kaynak.contains('liveRegion: true'), isTrue);
  });

  test('hareket, azaltılmış hareket ayarına saygı duyuyor', () {
    // SandikMotion.of/stateOf/surfaceOf, "Hareketi Azalt" açıkken süreyi
    // sıfırlar. Çıplak SandikMotion.state kullanılırsa bu ayar yok sayılır.
    expect(kaynak.contains('SandikMotion.stateOf(context)'), isTrue);
    expect(kaynak.contains('SandikMotion.surfaceOf(context)'), isTrue);
  });
}
