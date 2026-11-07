import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/widget_sabitleme_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar → Görünüm → "Ana ekran widget'ı" (Ar-Ge 7 Kas 14:30 #5).
///
/// Kilitlenen: Android'de satır YALNIZ launcher destekliyorsa görünür ve
/// dokununca sistemin yerleştirme isteği gider; iOS'ta düğme yok, tek satır
/// adım var. Platform kanalı yerine sahte kapı (`widgetSabitleyiciProvider`).
class _SahteSabitleyici implements WidgetSabitleyici {
  _SahteSabitleyici({required this.destek});

  final bool destek;
  int istekSayisi = 0;

  @override
  Future<bool> sabitlemeDestekleniyorMu() async => destek;

  @override
  Future<bool> sabitlemeIste() async {
    istekSayisi++;
    return true;
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Future<void> platformla(
      TargetPlatform p, Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = p;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> kur(WidgetTester tester, WidgetSabitleyici kapi,
      {double genislik = 1200, double olcek = 1}) async {
    tester.view.physicalSize = Size(genislik * 3, 4000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [widgetSabitleyiciProvider.overrideWithValue(kapi)],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const SettingsScreen(bolum: SettingsBolum.gorunum),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Android, destek var: satır görünür, dokununca istek gider',
      (tester) async {
    await platformla(TargetPlatform.android, () async {
      final kapi = _SahteSabitleyici(destek: true);
      await kur(tester, kapi);

      expect(find.text("Ana ekran widget'ı"), findsOneWidget);
      final satir = find.text('Ana ekrana widget ekle');
      expect(satir, findsOneWidget);

      // HIG: dokunma alanı ≥ 44 pt.
      final buton =
          find.ancestor(of: satir, matching: find.byType(CupertinoButton));
      expect(tester.getSize(buton.first).height,
          greaterThanOrEqualTo(SandikTouch.min));

      await tester.tap(satir);
      await tester.pump();
      expect(kapi.istekSayisi, 1);
      // iOS adımı Android'de yok.
      expect(find.textContaining('+ simgesine'), findsNothing);
    });
  });

  testWidgets('Android, destek yok: satır ve alt başlık hiç yok',
      (tester) async {
    await platformla(TargetPlatform.android, () async {
      await kur(tester, _SahteSabitleyici(destek: false));
      expect(find.text('Ana ekrana widget ekle'), findsNothing);
      expect(find.text("Ana ekran widget'ı"), findsNothing);
    });
  });

  testWidgets('iOS: düğme yok, tek satır adım var', (tester) async {
    await platformla(TargetPlatform.iOS, () async {
      final kapi = _SahteSabitleyici(destek: true);
      await kur(tester, kapi);
      expect(find.text('Ana ekrana widget ekle'), findsNothing);
      expect(
          find.text('Ana ekrana eklemek için: ana ekranda boş bir yere '
              "basılı tut → + simgesine dokun → sandık'ı seç."),
          findsOneWidget);
    });
  });

  for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('320 pt, 3.1× yazı: taşma yok (${p.name})', (tester) async {
      await platformla(p, () async {
        await kur(tester, _SahteSabitleyici(destek: true),
            genislik: 320, olcek: 3.1);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
