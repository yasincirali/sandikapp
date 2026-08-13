import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Açılış ekranı light mode + dar ekran davranışı.
///
/// Hata neydi: [SandikLoadingScreen] zemini `Sandik.background` (#0A1E15) ve
/// wordmark'ı `Sandik.gold` ile SABİTLENMİŞTİ. Bu ikisi dark palette
/// sabitleridir — light modda kullanıcı, uygulamanın geri kalanı aydınlıkken
/// önce koyu yeşil bir kare görüyordu. Ayrıca logo 140dp sabitti; dar
/// ekranda logo + wordmark dikeyde taşıyordu.
///
/// Burada kilitlenen değişmez: açılış ekranı renklerini `context.c`
/// üzerinden ÇÖZER, derleme zamanı sabitinden okumaz.
void main() {
  /// Splash'i verilen parlaklık ve ekran ölçüsüyle kurar.
  Widget harness({required Brightness brightness, required Size size}) {
    final palette =
        brightness == Brightness.light ? SandikPalette.light : SandikPalette.dark;
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: ThemeData(brightness: brightness, extensions: [palette]),
        home: const SandikLoadingScreen(),
      ),
    );
  }

  Color scaffoldBackground(WidgetTester tester) {
    return tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;
  }

  Color wordmarkColor(WidgetTester tester) {
    return tester.widget<Text>(find.text('sandık')).style!.color!;
  }

  /// Gerçek uygulama zinciri: cihaz parlaklığı → `ThemeMode.system` →
  /// `MaterialApp.theme/darkTheme` → splash. Yukarıdaki [harness] temayı
  /// doğrudan verdiği için bu zinciri ATLAR; asıl hata ise tam burada
  /// yaşıyordu (tema modu `system` değil `dark` sabitiydi).
  Widget systemHarness({required Brightness platformBrightness}) {
    return MediaQuery(
      data: MediaQueryData(platformBrightness: platformBrightness),
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const [SandikPalette.light],
        ),
        darkTheme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        themeMode: ThemeMode.system,
        home: const SandikLoadingScreen(),
      ),
    );
  }

  group('açılış ekranı moda duyarlı', () {
    testWidgets('light modda zemin AÇIK olmalı', (tester) async {
      await tester.pumpWidget(
        harness(brightness: Brightness.light, size: const Size(390, 844)),
      );

      expect(
        scaffoldBackground(tester),
        SandikPalette.light.background,
        reason: 'Light modda splash zemini light palette background olmalı; '
            'dark sabiti kalırsa açılışta koyu kare çakar.',
      );
    });

    testWidgets('light modda wordmark okunur tonda olmalı', (tester) async {
      await tester.pumpWidget(
        harness(brightness: Brightness.light, size: const Size(390, 844)),
      );

      expect(
        wordmarkColor(tester),
        SandikPalette.light.gold,
        reason: 'Dark `gold` (#D4A24C) açık zeminde okunmuyordu; light '
            'palette karşılığı koyu kahvedir.',
      );
    });

    testWidgets('dark modda koyu palet korunur (regresyon)', (tester) async {
      await tester.pumpWidget(
        harness(brightness: Brightness.dark, size: const Size(390, 844)),
      );

      expect(scaffoldBackground(tester), SandikPalette.dark.background);
      expect(wordmarkColor(tester), SandikPalette.dark.gold);
    });
  });

  group('cihaz seçimini takip eder (system)', () {
    testWidgets('cihaz LIGHT ise splash açık gelir', (tester) async {
      await tester.pumpWidget(
        systemHarness(platformBrightness: Brightness.light),
      );

      expect(
        scaffoldBackground(tester),
        SandikPalette.light.background,
        reason: 'Kullanıcı şikâyeti: cihaz/IDE light iken splash koyu '
            'açılıyordu. Tema modu varsayılanı `system` olmalı.',
      );
      expect(wordmarkColor(tester), SandikPalette.light.gold);
    });

    testWidgets('cihaz DARK ise splash koyu gelir', (tester) async {
      await tester.pumpWidget(
        systemHarness(platformBrightness: Brightness.dark),
      );

      expect(scaffoldBackground(tester), SandikPalette.dark.background);
      expect(wordmarkColor(tester), SandikPalette.dark.gold);
    });
  });

  group('durum çubuğu ikonları zeminle çelişmez', () {
    /// Splash'in bildirdiği overlay style — `AnnotatedRegion` üzerinden.
    SystemUiOverlayStyle declaredStyle(WidgetTester tester) {
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      return region.value;
    }

    testWidgets('light zeminde KOYU ikon istenir', (tester) async {
      await tester.pumpWidget(
        harness(brightness: Brightness.light, size: const Size(390, 844)),
      );

      expect(
        declaredStyle(tester).statusBarIconBrightness,
        Brightness.dark,
        reason: 'Açık zemin üzerinde beyaz ikon okunmaz. main.dart eskiden '
            'ikon parlaklığını global olarak `light`e sabitliyordu.',
      );
    });

    testWidgets('dark zeminde AÇIK ikon istenir', (tester) async {
      await tester.pumpWidget(
        harness(brightness: Brightness.dark, size: const Size(390, 844)),
      );

      expect(declaredStyle(tester).statusBarIconBrightness, Brightness.light);
    });
  });

  group('açılış ekranı dar ekranda taşmaz', () {
    // 320pt en dar desteklenen genişlik (iPhone SE 1. nesil sınıfı).
    for (final size in const [
      Size(320, 480),
      Size(360, 640),
      Size(390, 844),
      Size(430, 932),
    ]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()} taşmamalı',
          (tester) async {
        await tester.pumpWidget(
          harness(brightness: Brightness.light, size: size),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('logo dar ekranda küçülür, geniş ekranda tasarım ölçüsünde kalır',
        (tester) async {
      Future<double> logoBoxWidth(Size size) async {
        await tester.pumpWidget(
          harness(brightness: Brightness.light, size: size),
        );
        // Wordmark'tan önceki kare kutu — GIF yuvası.
        final box = tester.widget<SizedBox>(
          find
              .descendant(
                of: find.byType(Column),
                matching: find.byType(SizedBox),
              )
              .first,
        );
        return box.width!;
      }

      final wide = await logoBoxWidth(const Size(430, 932));
      final narrow = await logoBoxWidth(const Size(320, 480));

      expect(wide, 140,
          reason: 'Geniş ekranda tasarım ölçüsü korunmalı.');
      expect(narrow, lessThan(wide),
          reason: 'Dar ekranda logo kısa kenara göre küçülmeli.');
    });
  });

  test('splash renkleri derleme zamanı sabitine bağlanmamalı', () {
    // Kaynak taraması: `SandikLoadingScreen` gövdesinde `Sandik.` ile başlayan
    // renk sabiti kalmamalı — moda duyarlı olması gereken tek yer burası.
    final src = File('lib/theme/sandik.dart').readAsStringSync();
    final start = src.indexOf('class SandikLoadingScreen');
    expect(start, greaterThan(-1));
    final body = src.substring(start);
    // Splash iki sınıfa yayılır (widget + State); tarama State'in SONUNA
    // kadar sürmeli, yoksa asıl build gövdesi kapsam dışında kalır.
    // Anchor, State'in bildirimidir — `createState()` içindeki dönüş tipi
    // aynı adı daha erken geçirdiği için ham ad araması yanlış yer bulur.
    final stateDecl = body.indexOf('class _SandikLoadingScreenState');
    expect(stateDecl, greaterThan(-1));
    final end = body.indexOf('\nclass ', stateDecl);
    final widgetSrc = end == -1 ? body : body.substring(0, end);

    // Kapsamın gerçekten build gövdesini içerdiğini doğrula — bu satır
    // olmazsa yanlış hesaplanmış bir aralık testi sessizce yeşil yapar.
    expect(widgetSrc, contains('backgroundColor:'),
        reason: 'Tarama aralığı build gövdesini kapsamalı.');

    expect(
      RegExp(r'Sandik\.(background|gold|surface\d|text\d+)')
          .hasMatch(widgetSrc),
      isFalse,
      reason: 'Açılış ekranı renkleri `context.c` üzerinden çözülmeli.',
    );
  });
}
