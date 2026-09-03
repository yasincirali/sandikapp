import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';
import 'package:portfoy_takip/services/live_activity_service.dart';
import 'package:portfoy_takip/utils/theme_resolution.dart';

/// **Uygulama dışı yüzeyler uygulamanın SEÇİLİ temasını izlemeli.**
///
/// ## Ne oluyordu
/// | yüzey | renge kim karar veriyordu | uygulama temasını izler miydi |
/// |---|---|---|
/// | iOS kilit ekranı / Dynamic Island | `SandikTheme.swift` sabitleri | ❌ hep koyu |
/// | Android ana ekran widget'ı | `values` ↔ `values-night` | ⚠️ SİSTEMİN modunu |
/// | widget sparkline PNG'si (Dart'ta çizilir) | sabit dark tonlar | ❌ |
///
/// Kullanıcı uygulamayı "Açık" yapıp cihazı koyu bıraktığında üçü de koyu
/// kalıyordu. Sparkline PNG'si ayrıca XML renkleriyle senkron bile değildi:
/// açık modda `widget_gain` `#0F7A4E` iken çizgi `#3DB77F` çiziliyordu.
///
/// ## Neden karar Dart'ta veriliyor
/// Uzantı ve widget uygulamanın `ThemeMode` tercihini GÖREMEZ; görebildikleri
/// tek şey cihazın görünümüdür. "Sistem"in ne anlama geldiğini yalnızca Dart
/// tarafı bilir, bu yüzden native'e ÇÖZÜLMÜŞ bir bool gider.
///
/// ## Bu testin sınırı
/// iOS Live Activity bu ortamda render edilemez (emülatörler Flutter'ı bile
/// render edemiyor — bkz. CLAUDE.md). Burada doğrulanan: çözüm cebiri, Dart
/// payload'ı ve native tarafın bayrağı gerçekten okuduğu. Görsel doğrulama
/// gerçek cihazda yapılır.
String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') &&
          !t.startsWith('///') &&
          !t.startsWith('*') &&
          !t.startsWith('<!--');
    }).join('\n');

void main() {
  // `resolveThemeIsLightNow` binding üzerinden platformu okuyor; düz bir
  // `test()` bloğunda binding kendiliğinden kurulmaz.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tema çözümü', () {
    test('Açık ve Koyu doğrudan çözülür', () {
      expect(resolveThemeIsLightWith(ThemeMode.light, Brightness.dark), isTrue,
          reason: 'uygulama tercihi cihazın görünümünü EZER');
      expect(
          resolveThemeIsLightWith(ThemeMode.dark, Brightness.light), isFalse);
    });

    test('Sistem cihazın görünümüne düşer', () {
      expect(
          resolveThemeIsLightWith(ThemeMode.system, Brightness.light), isTrue);
      expect(
          resolveThemeIsLightWith(ThemeMode.system, Brightness.dark), isFalse);
    });

    test('bağlamsız çözüm platformdan okur', () {
      // `resolveThemeIsLightNow` iki çağrı yerinde de build DIŞINDAN
      // çalışıyor; MediaQuery bağımlılığı kaydetmemesi bilinçli.
      final beklenen =
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.light;
      expect(resolveThemeIsLightNow(ThemeMode.system), beklenen);
      expect(resolveThemeIsLightNow(ThemeMode.light), isTrue,
          reason: 'açık tercih platformdan bağımsız');
      expect(resolveThemeIsLightNow(ThemeMode.dark), isFalse);
    });
  });

  group('servisler tercihi taşıyor', () {
    test('LiveActivityService varsayılanı KOYU', () {
      // Tercih henüz itilmemişken bugüne kadarki davranış korunmalı.
      expect(LiveActivityService.instance.themeIsLight, isFalse);
    });

    test('HomeWidgetService varsayılanı KOYU', () {
      expect(HomeWidgetService.instance.themeIsLight, isFalse);
    });
  });

  group('payload bayrağı taşıyor', () {
    late String servis;

    setUpAll(() async {
      servis = _yorumsuz(
          await File('lib/services/live_activity_service.dart').readAsString());
    });

    test('isLightTheme her iki dalda da gönderilir', () {
      // Gizli (bakiye maskeli) dal da çizilir; o da temayı izlemeli.
      expect("'isLightTheme': themeIsLight".allMatches(servis).length, 2,
          reason: 'hem gizli hem normal payload bayrağı taşımalı');
    });

    test('şema sürümü YÜKSELTİLMEDİ', () {
      // Yeni bir alan eklemek mevcut alanların ANLAMINI değiştirmez.
      // Yükseltmek DB'de v6 yazan bütün oturumları `skippedStale` yapıp
      // kullanıcı yeni sürümü kurana kadar push'u tümden keserdi
      // (dosyanın kendi dokümantasyonundaki gerekçe).
      expect(LiveActivityService.summarySchemaVersion, 6);
    });
  });

  group('native taraf bayrağı okuyor', () {
    test('Swift ContentState alanı tanıyor', () async {
      final attrs = _yorumsuz(
          await File('ios/SandikWidget/SandikAttributes.swift').readAsString());
      expect(attrs.contains('var isLightTheme: Bool = false'), isTrue,
          reason: 'eski oturumlar alanı taşımaz — varsayılan koyu olmalı');
    });

    test('Swift paleti bayraktan seçiliyor', () async {
      final tema = _yorumsuz(
          await File('ios/SandikWidget/SandikTheme.swift').readAsString());
      final view = _yorumsuz(
          await File('ios/SandikWidget/SandikLiveActivity.swift')
              .readAsString());

      expect(tema.contains('static let light = SandikPalette('), isTrue,
          reason: 'açık palet tanımlı olmalı');
      expect(tema.contains('static let dark = SandikPalette('), isTrue);
      expect(view.contains('SandikPalette.resolved(isLight:'), isTrue,
          reason: 'görünüm paleti bayraktan seçmeli');
    });

    test('Swift SİSTEM görünümünü sormuyor', () {
      // `@Environment(\.colorScheme)` yanlış cevabı verir: cihazın
      // görünümünü söyler, uygulamanın tercihini değil.
      // (Doğrudan dosya okuması — yorumlar ayıklanır.)
      final dosyalar = Directory('ios/SandikWidget')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.swift'));
      for (final f in dosyalar) {
        final src = _yorumsuz(f.readAsStringSync());
        expect(src.contains('colorScheme'), isFalse,
            reason: '${f.path} sistem görünümünü soruyor');
      }
    });

    test('Android widget uygulama tercihini okuyor', () async {
      final provider = _yorumsuz(await File(
              'android/app/src/main/kotlin/com/sandik/app/SandikWidgetProvider.kt')
          .readAsString());

      expect(provider.contains('sandik_is_light_theme'), isTrue,
          reason: 'sistemin gece modu değil, uygulamanın tercihi');
      expect(provider.contains('R.color.widget_gain_light'), isTrue,
          reason: 'palet moddan bağımsız kaynaklardan seçilmeli');
      // Moda duyarlı eski kaynak adları artık kullanılmamalı: onlar
      // `values-night` üzerinden SİSTEMİ izliyor.
      expect(provider.contains('R.color.widget_gain)'), isFalse);
      expect(provider.contains('R.color.widget_text_muted)'), isFalse);
    });

    test('moddan bağımsız palet kaynağı var', () async {
      final xml =
          await File('android/app/src/main/res/values/widget_palette.xml')
              .readAsString();
      for (final ad in const [
        'widget_bg_light',
        'widget_bg_dark',
        'widget_gain_light',
        'widget_gain_dark',
        'widget_loss_light',
        'widget_loss_dark',
      ]) {
        expect(xml.contains('name="$ad"'), isTrue, reason: '$ad eksik');
      }
    });
  });

  group('sparkline PNG i de temaya bağlı', () {
    test('sabit dark tonlar kaldırıldı', () async {
      final src = _yorumsuz(
          await File('lib/services/home_widget_service.dart').readAsString());
      expect(src.contains('_sparkPalette'), isTrue,
          reason: 'renkler paletten gelmeli');
      // Çizim kodunda ham sabit kalmamalı; sabitler yalnızca paletin
      // tanımında bulunur.
      final cizim = src.substring(src.indexOf('final palet = _sparkPalette'));
      expect(cizim.contains('const Color(0xFF3DB77F)'), isFalse,
          reason: 'çizim ham sabit kullanmamalı');
    });
  });
}
