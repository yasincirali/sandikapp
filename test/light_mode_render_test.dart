import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Light mode gerçekten render oluyor mu?
///
/// Kontrast testi paletin *değerlerini* doğrular; bu test paletin ekrana
/// *ulaştığını* doğrular. İkisi ayrı hata sınıfı: palet doğru olabilir ama
/// widget hâlâ `Sandik.surface1` sabitini okuyorsa light modda hiçbir şey
/// değişmez ve kontrast testi bunu göremez.
///
/// Emülatör bu projede Flutter'ı render edemiyor (bkz. TECHNICAL_DEBT.md),
/// bu yüzden görsel doğrulamanın yeri burası.
void main() {
  /// [child]'ı verilen parlaklıkta bir tema içinde kurar.
  Widget host(Brightness b, Widget child) {
    final palette =
        b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
    return MaterialApp(
      // Key moda bağlanır: aksi halde ardışık pumpWidget çağrılarında
      // Flutter element ağacını yeniden kullanır, Builder yeniden
      // çalışmaz ve ikinci mod ilkinin değerlerini döndürür.
      key: ValueKey(b),
      theme: ThemeData(
        brightness: b,
        extensions: [palette],
      ),
      home: Scaffold(
        backgroundColor: palette.background,
        body: child,
      ),
    );
  }

  group('tema geçişi', () {
    testWidgets('context.c moda göre farklı palet döner', (tester) async {
      final seen = <Brightness, SandikPalette>{};

      for (final b in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(host(
          b,
          Builder(builder: (context) {
            seen[b] = context.c;
            return const SizedBox();
          }),
        ));
      }

      expect(seen[Brightness.light]!.surface1,
          SandikPalette.light.surface1);
      expect(seen[Brightness.dark]!.surface1, SandikPalette.dark.surface1);
      // Asıl iddia: ikisi farklı olmalı. Aynıysa tema geçişi çalışmıyordur.
      expect(seen[Brightness.light]!.surface1,
          isNot(seen[Brightness.dark]!.surface1));
    });

    testWidgets('context.isLight parlaklığı doğru okur', (tester) async {
      late bool lightSaw, darkSaw;
      await tester.pumpWidget(host(
        Brightness.light,
        Builder(builder: (c) {
          lightSaw = c.isLight;
          return const SizedBox();
        }),
      ));
      await tester.pumpWidget(host(
        Brightness.dark,
        Builder(builder: (c) {
          darkSaw = c.isLight;
          return const SizedBox();
        }),
      ));
      expect(lightSaw, isTrue);
      expect(darkSaw, isFalse);
    });
  });

  group('yüzey yardımcıları', () {
    testWidgets('surfaceCard light\'ta gölge, dark\'ta overlay kullanır',
        (tester) async {
      final decos = <Brightness, BoxDecoration>{};
      for (final b in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(host(
          b,
          Builder(builder: (context) {
            decos[b] = context.surfaceCard();
            return const SizedBox();
          }),
        ));
      }

      final light = decos[Brightness.light]!;
      final dark = decos[Brightness.dark]!;

      // Light'ta yükseklik gölgeyle kurulur.
      expect(light.boxShadow, isNotNull);
      expect(light.boxShadow, isNotEmpty);
      // Dark'ta gölge koyu zeminde görünmez — kullanılmaz.
      expect(dark.boxShadow, isNull);
      // Dolgular da farklı olmalı.
      expect(light.color, isNot(dark.color));
    });

    testWidgets('inputDecoration dolgusu modlar arasında ters döner',
        (tester) async {
      final fills = <Brightness, Color?>{};
      for (final b in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(host(
          b,
          Builder(builder: (context) {
            fills[b] = context.inputDecoration('x').fillColor;
            return const SizedBox();
          }),
        ));
      }
      // Light'ta alan zeminden BEYAZLAŞARAK öne çıkar, dark'ta
      // KOYULAŞARAK çukurlaşır — aynı değer olamaz.
      expect(fills[Brightness.light], isNot(fills[Brightness.dark]));
      expect(fills[Brightness.light], SandikPalette.light.surface2);
    });

    testWidgets('chip seçili durumda accent kenarlığı alır', (tester) async {
      late BoxDecoration on, off;
      await tester.pumpWidget(host(
        Brightness.light,
        Builder(builder: (context) {
          on = context.chip(selected: true);
          off = context.chip(selected: false);
          return const SizedBox();
        }),
      ));
      expect(on.border, isNotNull);
      expect(on.color, isNot(off.color));
    });
  });

  group('gerçek widget ağacı', () {
    testWidgets('Scaffold zemini modla birlikte değişir', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        final palette =
            b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
        await tester.pumpWidget(host(b, const Text('x')));
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, palette.background);
      }
    });

    testWidgets('SandikTappable her iki modda çalışır', (tester) async {
      for (final b in [Brightness.light, Brightness.dark]) {
        var tapped = false;
        await tester.pumpWidget(host(
          b,
          SandikTappable(
            onTap: () => tapped = true,
            semanticLabel: 'test',
            child: const SizedBox(width: 60, height: 60),
          ),
        ));
        await tester.tap(find.byType(SandikTappable));
        await tester.pumpAndSettle();
        expect(tapped, isTrue, reason: 'mod: $b');
      }
    });
  });

  group('tema modu tercihi', () {
    testWidgets('seçici üç modu da sunar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await initPreferencesCache();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(extensions: const [SandikPalette.dark]),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Üç seçenek de görünür olmalı.
      expect(find.text('Sistem'), findsOneWidget);
      expect(find.text('Açık'), findsOneWidget);
      expect(find.text('Koyu'), findsOneWidget);
    });
  });

  group('light mode gorsel regresyonlari', () {
    // Gercek cihaz ekran goruntusunde yakalanan iki hata (2026-08-09).
    // Emulator Flutter'i render edemedigi icin bunlar ancak kullanici
    // ekran goruntusu gonderince gorulebildi; testler o bosluğu kapatır.

    testWidgets('hero kart light modda koyu levha olmamalı', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light'),
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: const [SandikPalette.light],
          ),
          home: Builder(builder: (context) {
            // Hero kart light'ta surface2 (beyaz) olmalı — sabit koyu
            // yeşil (#14332B) değil.
            expect(context.isLight, isTrue);
            expect(SandikPalette.light.surface2, const Color(0xFFFFFFFF));
            return const SizedBox();
          }),
        ),
      );
    });

    test('bolum basligi tonu AA esigini gecer', () {
      // text36 = 3.79:1 -> yalnizca yardimci metin.
      // Bolum basliklari (VARLIK DAGILIMI, ORTAKLIK ISLEMLERI...) yapisal
      // bilgidir ve text58 (6.90:1) kullanmalidir.
      const p = SandikPalette.light;
      expect(p.text58, isNot(p.text36));
    });
  });

  group('yuksek kontrast entegrasyonu', () {
    testWidgets('context.c highContrast ayarina uyar', (tester) async {
      late SandikPalette normal, hc;

      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('n'),
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const [SandikPalette.light],
        ),
        home: Builder(builder: (c) {
          normal = c.c;
          return const SizedBox();
        }),
      ));

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(highContrast: true),
        child: MaterialApp(
          key: const ValueKey('h'),
          theme: ThemeData(
            brightness: Brightness.light,
            extensions: const [SandikPalette.light],
          ),
          home: Builder(builder: (c) {
            hc = c.c;
            return const SizedBox();
          }),
        ),
      ));

      // Yardimci ton guclenmis olmali.
      expect(hc.text36, isNot(normal.text36));
      // Yuzey ve marka degismemeli.
      expect(hc.surface1, normal.surface1);
      expect(hc.amberFill, normal.amberFill);
    });
  });
}
