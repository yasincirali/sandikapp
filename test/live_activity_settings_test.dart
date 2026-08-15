import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/settings_screen.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ayarlar → CANLI ETKİNLİK bölümü.
///
/// ## Neden bu testler var
/// Gerçek bir kullanıcı bu özelliği **hiç açamadı**: ayar "GİZLİLİK"
/// bölümünün altına gömülüydü, hiçbir yerde iOS'taki adı ("Canlı
/// Etkinlikler") geçmiyordu ve 7/24 yapmanın tek yolu iki saat kutusunu
/// elle aynı değere getirmekti — keşfedilebilir değil. Üstüne, pencere
/// dışındayken kilit ekranında hiçbir şey olmuyor ve sebebini söyleyen tek
/// bir işaret yoktu; kullanıcı özelliği bozuk sandı.
///
/// Burada kilitlenen davranışlar:
///   1. Bölüm kendi başlığı altında ve iOS'taki adıyla bulunabilir.
///   2. "Gün boyu göster" anahtarı pencereyi GERÇEKTEN 7/24 yapar
///      (start == end kuralı) ve kapatınca BIST varsayılanına döner.
///   3. Anahtar açıkken saat kutuları gizlenir.
///   4. Pencere dışındayken sebebi yazan bir durum satırı çıkar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LiveActivityService.instance.resetForTest();
  });

  /// Test gövdesini iOS platformunda koşturur.
  ///
  /// Bölüm iOS-only olduğu için override şart; ama `testWidgets` her testin
  /// sonunda foundation debug değişkenlerinin sıfırlanmış olmasını şart
  /// koşar (`debugAssertAllFoundationVarsUnset`). Bu kontrol hem
  /// `tearDown`'dan hem `addTearDown`'dan ÖNCE çalışır — ikisi de burada
  /// işe yaramaz. Tek doğru yer testin gövdesi: `finally` ile geri alınır.
  Future<void> runAsIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Widget host() => ProviderScope(
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: const SettingsScreen(),
        ),
      );

  /// "Gün boyu göster" satırındaki anahtar.
  ///
  /// Metne dokunmak İŞE YARAMAZ: `_SwitchTile` başlığı tıklanabilir
  /// değil, yalnızca `CupertinoSwitch` olayı alır. Ekranda birden fazla
  /// anahtar olduğu için de tür bazlı arama yetmez — anahtar, başlığıyla
  /// aynı satırın içinden seçilir.
  Finder allDaySwitch() => find.descendant(
        of: find.ancestor(
          of: find.text('Gün boyu göster'),
          matching: find.byType(Row),
        ).last,
        matching: find.byType(CupertinoSwitch),
      );

  /// Ayarlar uzun bir liste — hedef widget'ı görünür alana getirir.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 120,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  /// Ekranı kurar ve "Gün boyu göster" anahtarını görünür alana getirir —
  /// testlerin çoğunun ortak açılışı.
  Future<ProviderContainer> openSection(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Gün boyu göster'));
    return ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)));
  }

  group('bölüm yerleşimi', () {
    testWidgets('kendi başlığı altında ve iOS adıyla bulunur',
        (tester) async {
      await runAsIOS(() async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        // Kullanıcı iOS'ta gördüğü adla arar; başlık o adla eşleşmeli.
        expect(find.text('CANLI ETKİNLİK'), findsOneWidget,
            reason: 'GİZLİLİK altına gömülüyse kullanıcı bulamıyor');
      });
    });

    testWidgets('gün boyu anahtarı görünür', (tester) async {
      await runAsIOS(() async {
        await openSection(tester);
        expect(find.text('Gün boyu göster'), findsOneWidget);
      });
    });
  });

  group('gün boyu anahtarı', () {
    testWidgets('açınca pencere 7/24 olur', (tester) async {
      await runAsIOS(() async {
        final container = await openSection(tester);

        // Başlangıçta BIST varsayılanı.
        expect(container.read(liveActivityStartProvider),
            LiveActivityService.defaultStartMinute);

        await tester.tap(allDaySwitch());
        await tester.pumpAndSettle();

        // 7/24 kuralı: başlangıç == bitiş.
        expect(container.read(liveActivityStartProvider),
            container.read(liveActivityEndProvider),
            reason: 'servis start==end durumunu 7/24 sayar');

        // Servise de aktarılmış olmalı — bir sonraki portföy
        // güncellemesini beklemeden pencere geçerli olsun.
        final svc = LiveActivityService.instance;
        expect(svc.startMinute, svc.endMinute);
        expect(svc.isWithinWindow(DateTime(2026, 8, 16, 3, 0)), isTrue,
            reason: 'gece 03:00 da dahil olmalı');
      });
    });

    testWidgets('kapatınca BIST varsayılanına döner', (tester) async {
      await runAsIOS(() async {
        final container = await openSection(tester);

        await tester.tap(allDaySwitch());
        await tester.pumpAndSettle();
        await tester.tap(allDaySwitch());
        await tester.pumpAndSettle();

        expect(container.read(liveActivityStartProvider),
            LiveActivityService.defaultStartMinute);
        expect(container.read(liveActivityEndProvider),
            LiveActivityService.defaultEndMinute);
      });
    });

    testWidgets('açıkken saat kutuları gizlenir', (tester) async {
      await runAsIOS(() async {
        await openSection(tester);

        // Kapalıyken kutular var.
        expect(find.text('Başlangıç'), findsOneWidget);
        expect(find.text('Bitiş'), findsOneWidget);

        await tester.tap(allDaySwitch());
        await tester.pumpAndSettle();

        // Açıkken anlamsız: "bu saatler hâlâ geçerli mi?" sorusu doğar.
        expect(find.text('Başlangıç'), findsNothing);
        expect(find.text('Bitiş'), findsNothing);
      });
    });
  });

  group('durum satırı', () {
    testWidgets('pencere dışındayken sebep yazılır', (tester) async {
      await runAsIOS(() async {
        await openSection(tester);

        // Varsayılan pencere 10:00–18:10. Test saati bunun dışındaysa
        // satır çıkmalı, içindeyse çıkmamalı. İkisi de doğru davranış
        // olduğu için test saate göre dallanır — sabit bir saat varsaymak
        // testi günün yarısında kırardı.
        final visible =
            LiveActivityService.instance.isWithinWindow(DateTime.now());
        final banner = find.textContaining('Şu an görünmüyor');

        if (visible) {
          expect(banner, findsNothing,
              reason: 'pencere içindeyken uyarı gösterilmemeli');
        } else {
          expect(banner, findsOneWidget,
              reason: 'sebebi söylenmezse kullanıcı bozuk sanıyor');
        }
      });
    });

    testWidgets('gün boyu açılınca uyarı kaybolur', (tester) async {
      await runAsIOS(() async {
        await openSection(tester);

        await tester.tap(allDaySwitch());
        await tester.pumpAndSettle();

        // 7/24 açıkken her saat pencere içidir — uyarı anlamsız olur.
        expect(find.textContaining('Şu an görünmüyor'), findsNothing);
      });
    });
  });
}
