import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/onboarding_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İlk girişte gösterilen interaktif tanıtım.
///
/// 2026-09-14 yeniden yazımı: minyatür şema + 22 açıklama kartı yerine
/// uygulamanın gerçek görünümünde yedi sayfa ve her sayfada tek bir küçük
/// görev (tutarı gizle, cümleyle ekle, dönem seç, bildirimi aç, Birlikte'ye
/// geç). Kullanıcının kısıtı aynı: "olan hiçbir akış bozulmamalı".
///
/// ## Neden bu testler
/// Bu ortamda cihaz yok; "aç ve bak" adımı yapılamıyor. Onun yerine tur
/// gerçekten pump edilip baştan sona GEZİLİYOR, görevler YAPILIYOR ve üç şey
/// ölçülüyor:
///
///   1. **Akış bozulmadı.** `onComplete` / `userId` / `isCompleted` /
///      `markCompleted` ve analytics çağrıları yerinde mi (kaynak denetimi).
///   2. **Görevler çalışıyor.** Göz simgesi tutarı gizliyor, örnek cümle
///      karta dönüşüyor, anahtar bildirimi açıyor, "Birlikte" ortak toplamı
///      gösteriyor; görev şeridi onaya dönüyor.
///   3. **Taşma yok.** Yüzeyler dar ekranda (320pt) ve büyük sistem yazı
///      tipinde (2,0×) kırılmamalı; hareket azaltılmışken de aynı.
Future<void> _pump(
  WidgetTester tester, {
  double width = 375,
  double height = 812,
  double textScale = 1.0,
  Brightness parlaklik = Brightness.dark,
  bool hareketiAzalt = false,
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
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: hareketiAzalt,
        ),
        child: OnboardingScreen(onComplete: () {}, userId: 'u1'),
      ),
    ),
  );
  await _bekle(tester);
}

/// `pumpAndSettle` KULLANILMAZ: karşılama halkaları ve nabız işareti
/// sonsuz döngüdür, settle hiç bitmez. Sabit bir süre ilerletilir — en uzun
/// tek seferlik hareket (sayaç/grafik, ~1s) bu sürede biter.
Future<void> _bekle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

Finder get _ileri => find.text('Devam').evaluate().isNotEmpty
    ? find.text('Devam')
    : find.text('Başlayalım');

/// Turu sonuna kadar gez — SON adıma BASMADAN.
///
/// Son sayfadaki "Sandığımı Aç" `markCompleted`'ı çağırır: SharedPreferences
/// ve Supabase yazımı. Testin konusu yerleşim, o yüzden orada durulur.
Future<int> _turuGez(WidgetTester tester) async {
  var sayfa = 0;
  while (find.text('Sandığımı Aç').evaluate().isEmpty) {
    expect(tester.takeException(), isNull, reason: '$sayfa. sayfada taşma');
    await tester.tap(_ileri);
    await _bekle(tester);
    sayfa++;
    if (sayfa > 20) fail('Tur bitmedi — "Sandığımı Aç" hiç gelmedi.');
  }
  expect(tester.takeException(), isNull, reason: 'son sayfada taşma');
  return sayfa;
}

/// Yüzeyler kaydırılabilir; hedef ekranın altında kalabilir. Önce görünür
/// yap, sonra dokun — aksi halde dokunuş boşa gider ve test yalan söyler.
Future<void> _dokun(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<void> _sayfayaGit(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(_ileri);
    await _bekle(tester);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('akış', () {
    testWidgets('karşılama → altı sayfa → kapanış', (tester) async {
      await _pump(tester);
      expect(find.text('Başlayalım'), findsOneWidget);
      expect(find.text('Atla'), findsOneWidget);
      // İlk sayfada geri tuşu yok.
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);

      final sayfa = await _turuGez(tester);
      expect(sayfa, 6, reason: 'Tur yedi sayfa olmalı (6 geçiş).');
      expect(find.text('Hazırsın'), findsOneWidget);
    });

    testWidgets('geri, bir önceki sayfaya döner', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 2);
      expect(find.text('Cümleyle varlık ekle'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await _bekle(tester);
      expect(find.text('Ana ekranın'), findsOneWidget);
    });

    testWidgets('görev zorunlu değil — "Devam" görev yapılmadan da açık',
        (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 1);
      expect(find.textContaining('Dene:'), findsOneWidget);
      expect(find.text('Devam'), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await _bekle(tester);
      expect(find.text('Cümleyle varlık ekle'), findsOneWidget);
    });
  });

  group('görevler — gerçek yüzeyde etkileşim', () {
    testWidgets('ana ekran: göz simgesi tutarları gizler', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 1);
      expect(find.text('TOPLAM NET VARLIK'), findsOneWidget);
      expect(find.text('••••••'), findsNothing);

      await _dokun(tester, find.byIcon(Icons.visibility_rounded));
      await _bekle(tester);

      expect(find.text('••••••'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
      expect(find.textContaining('Tutarları gizledin'), findsOneWidget,
          reason: 'Görev şeridi onaya dönmedi.');
      expect(find.textContaining('Dene:'), findsNothing);
    });

    testWidgets('hızlı giriş: örnek cümle karta dönüşür', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 2);
      expect(find.text('Hızlı Giriş'), findsOneWidget);
      expect(find.text('Gram altın'), findsNothing);

      await _dokun(tester, find.text('"10 gram altın 4500 lira"'));
      // Daktilo yazsın, kart belirsin.
      await _bekle(tester);
      await _bekle(tester);

      expect(find.text('Gram altın'), findsOneWidget);
      expect(find.text('₺4.500 / gram'), findsOneWidget);
      expect(find.textContaining('Cümleyle varlık ekledin'), findsOneWidget);
    });

    testWidgets('hızlı giriş: fiyatsız cümle "güncel fiyat çekilecek" der',
        (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 2);
      await _dokun(tester, find.text('"GARAN 500 adet"'));
      await _bekle(tester);
      await _bekle(tester);
      expect(find.text('Güncel fiyat çekilecek'), findsOneWidget);
    });

    testWidgets('performans: dönem seçimi + grafiğe basma görevi bitirir',
        (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 3);
      expect(find.text('1A GETİRİ'), findsOneWidget);

      await _dokun(tester, find.text('1Y'));
      await _bekle(tester);
      expect(find.text('1Y GETİRİ'), findsOneWidget);
      // Yalnızca dönem seçmek yetmez; grafiğe de dokunulmalı.
      expect(find.textContaining('Dene:'), findsOneWidget);

      final grafik = find.byType(CustomPaint).last;
      await tester.ensureVisible(grafik);
      await tester.pump();
      final basi = await tester.startGesture(tester.getCenter(grafik));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('SEÇİLİ NOKTA'), findsOneWidget,
          reason: 'Basılı tutunca imleç değeri gösterilmeli.');
      await basi.up();
      await _bekle(tester);

      expect(find.textContaining('Grafiği keşfettin'), findsOneWidget);
      expect(find.text('1A GETİRİ'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('performans: Simülasyon açıklaması değişir', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 3);
      await _dokun(tester, find.text('Simülasyon'));
      await _bekle(tester);
      expect(find.textContaining('Simülasyon: bugünkü'), findsOneWidget);
    });

    testWidgets('sinyal: anahtar bildirim önizlemesini açar', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 4);
      expect(find.text('TEKNİK SİNYALLER'), findsOneWidget);
      expect(find.text('THYAO · AL sinyali'), findsNothing);

      await _dokun(tester, find.byType(CupertinoSwitch));
      await _bekle(tester);

      expect(find.text('THYAO · AL sinyali'), findsOneWidget);
      expect(find.textContaining('Sinyal bildirimini açtın'), findsOneWidget);
    });

    testWidgets('ortaklık: "Birlikte" ortak toplamı ve ikinci payı gösterir',
        (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 5);
      expect(find.text('TOPLAM NET VARLIK'), findsOneWidget);
      expect(find.text('Elif'), findsNothing);

      await _dokun(tester, find.text('Birlikte'));
      await _bekle(tester);

      expect(find.text('ORTAK NET VARLIK'), findsOneWidget);
      expect(find.text('Elif'), findsOneWidget);
      expect(find.textContaining('Ortak portföyü gördün'), findsOneWidget);
    });

    testWidgets('ortaklık: Kopyala → Kopyalandı', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 5);
      await _dokun(tester, find.text('Kopyala'));
      await _bekle(tester);
      expect(find.text('Kopyalandı'), findsOneWidget);
    });

    testWidgets('kapanış, denenen görevleri sayar', (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 1);
      await _dokun(tester, find.byIcon(Icons.visibility_rounded));
      await _bekle(tester);
      await _sayfayaGit(tester, 5);

      expect(find.text('Hazırsın'), findsOneWidget);
      expect(find.text('1 / 5'), findsOneWidget);
      expect(find.text('Tutarları gizledin'), findsOneWidget);
      expect(find.textContaining('yeniden izle'), findsOneWidget,
          reason: 'Denemeyene turu tekrar açabileceği söylenmeli.');
    });
  });

  group('ayırt edici özellikler', () {
    testWidgets('"BİZE ÖZEL" rozeti en az üç sayfada çıkar', (tester) async {
      await _pump(tester);
      var goruldu = 0;
      while (find.text('Sandığımı Aç').evaluate().isEmpty) {
        if (find.text('BİZE ÖZEL').evaluate().isNotEmpty) goruldu++;
        await tester.tap(_ileri);
        await _bekle(tester);
      }
      expect(goruldu, greaterThanOrEqualTo(3),
          reason: 'Bizi ayırt eden özellikler işaretlenmemiş.');
    });

    testWidgets('alt menü kopyası gerçek ekranla aynı beş tuşu taşır',
        (tester) async {
      await _pump(tester);
      await _sayfayaGit(tester, 1);
      for (final etiket in ['Ana', 'Portföy', 'Performans', 'Profil']) {
        expect(find.text(etiket), findsWidgets, reason: '"$etiket" yok');
      }
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });
  });

  group('taşma — dar ekran ve büyük yazı tipi', () {
    // Yüzeyler en kırılgan kısım: beş sütunlu alt menü, beş etiketli dönem
    // seçici, hero tutar. Turun tamamı geziliyor — yalnızca ilk sayfayı
    // pump etmek bunları hiç açmazdı.
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

    testWidgets('"hareketi azalt" açıkken tur çalışır ve görevler yapılır',
        (tester) async {
      // Süreler sıfırken sonsuz döngüler durur, tek seferlikler anında biter;
      // hiçbir görev animasyonun bitmesine bağlı kalmamalı.
      await _pump(tester, hareketiAzalt: true);
      await _sayfayaGit(tester, 2);
      await _dokun(tester, find.text('"10 gram altın 4500 lira"'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Gram altın'), findsOneWidget);
      await _turuGez(tester);
    });
  });

  group('akış korundu — kaynak denetimi', _akisTestleri);
}

// ── Akış bozulmamalı ─────────────────────────────────────────────────────────
//
// Bu ekranın dışa dönük yüzeyi `main.dart`'ın açılış akışına bağlı:
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
    expect(kaynak.contains('logOnboardingStep('), isTrue);
    expect(kaynak.contains('widget.onComplete()'), isTrue);
  });

  test('"Atla" hâlâ var — tur zorunlu değil', () {
    expect(kaynak.contains("'Atla'"), isTrue);
  });

  test('ekran okuyucu sayfa değişimini duyuruyor', () {
    expect(kaynak.contains('liveRegion: true'), isTrue);
  });

  test('hareket, azaltılmış hareket ayarına saygı duyuyor', () {
    // SandikMotion.of/stateOf/surfaceOf, "Hareketi Azalt" açıkken süreyi
    // sıfırlar. Sonsuz döngüler (nabız, halka, imleç) ayrıca
    // `disableAnimationsOf` ile durdurulur.
    expect(kaynak.contains('SandikMotion.stateOf(context)'), isTrue);
    expect(kaynak.contains('SandikMotion.surfaceOf(context)'), isTrue);
    expect(kaynak.contains('disableAnimationsOf(context)'), isTrue);
  });

  test('yüzeyler servis katmanına dokunmuyor', () {
    // Tanıtım sabit örnek veriyle çalışır; fiyat çekmez, Supabase okumaz
    // (markCompleted dışında). Gerçek ayrıştırıcı/servis bağlanırsa tanıtım
    // ağ hatasıyla kırılır.
    expect(kaynak.contains('PriceService'), isFalse);
    expect(kaynak.contains('portfolioProvider'), isFalse);
    expect(kaynak.contains("import 'package:http"), isFalse);
  });
}
