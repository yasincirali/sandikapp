import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/custom_loading_indicator.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

/// Tek yükleniyor davranışı (yasin, 2026-10-08: "arkasında istek giden
/// buton kliklerini tespit edelim ve hepsinde aynı loading aksiyonu
/// alınsın").
///
/// İstek atan düğme `SandikAsyncButton` / `SandikAsyncTap`'ten geçer:
/// iş sürerken pasif, etiketin yerinde tek küçük gösterge, ikinci dokunuş
/// yutulur, boy değişmez, titreşim bileşenin varsayılanı. Bu test (1)
/// bileşenin sözleşmesini, (2) ekranların kendi döneni yazmadığını kilitler.
void main() {
  group('bileşen sözleşmesi', () {
    testWidgets('çift dokunuş tek istek, gösterge, boy sabit', (t) async {
      final c = Completer<void>();
      var n = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SandikAsyncButton.kompakt(
              onPressed: () {
                n++;
                return c.future;
              },
              child: const Text('Kaydet'),
            ),
          ),
        ),
      ));
      final once = t.getSize(find.byType(SandikAsyncButton));
      await t.tap(find.text('Kaydet'));
      await t.pump();
      await t.tap(find.text('Kaydet'), warnIfMissed: false);
      await t.pump();
      expect(n, 1);
      expect(find.byType(CustomLoadingIndicator), findsOneWidget);
      expect(t.getSize(find.byType(SandikAsyncButton)), once);
      c.complete();
      await t.pumpAndSettle();
      expect(find.byType(CustomLoadingIndicator), findsNothing);
    });

    testWidgets('mesgul: düğmeden geçmeyen tetikte de aynı gösterge',
        (t) async {
      var n = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SandikAsyncButton(
            mesgul: true,
            onPressed: () async => n++,
            child: const Text('Giriş'),
          ),
        ),
      ));
      expect(find.byType(CustomLoadingIndicator), findsOneWidget);
      await t.tap(find.byType(SandikAsyncButton), warnIfMissed: false);
      await t.pump();
      expect(n, 0, reason: 'meşgulken dokunuş yutulur');
    });

    for (final tur in SandikAsyncTur.values) {
      testWidgets('tür $tur meşgulken pasif', (t) async {
        final c = Completer<void>();
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SandikAsyncButton.kompakt(
              tur: tur,
              onPressed: () => c.future,
              child: const Text('Tamam'),
            ),
          ),
        ));
        await t.tap(find.text('Tamam'));
        await t.pump();
        final b = t.widget<ButtonStyleButton>(find.byWidgetPredicate(
            (w) => w is ButtonStyleButton));
        expect(b.onPressed, isNull);
        c.complete();
        await t.pumpAndSettle();
      });
    }
  });

  group('ekranlar kendi döneni yazmaz', () {
    final dosyalar = [
      ...Directory('lib/screens').listSync(recursive: true),
      ...Directory('lib/widgets').listSync(recursive: true),
      ...Directory('lib/utils').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));

    test('platform döneni yok (tek gösterge CustomLoadingIndicator)', () {
      final ihlal = [
        for (final f in dosyalar)
          if (!f.path.endsWith('custom_loading_indicator.dart') &&
              RegExp(r'CircularProgressIndicator\(|CupertinoActivityIndicator\(')
                  .hasMatch(f.readAsStringSync()))
            f.path,
      ];
      expect(ihlal, isEmpty);
    });

    // `bayrak ? const CustomLoadingIndicator(...) : Etiket` — düğme
    // içinde elle meşgul hâli. Kalanlar bilinçli istisna, her biri kaynakta
    // gerekçeli: varlık ekleme önizleme kutusu (düğme değil), CSV "Okunuyor…"
    // aşaması, Ayarlar satırı (`_SettingsTile.onTapAsync`) ve hesap silme.
    // Sayı YALNIZCA azalabilir.
    test('elle meşgul hâli ratchet', () {
      final desen = RegExp(
          r'\?\s*(const\s+)?CustomLoadingIndicator\(',
          multiLine: true);
      final sayim = <String, int>{};
      for (final f in dosyalar) {
        final k = desen.allMatches(f.readAsStringSync()).length;
        if (k > 0) sayim[f.path.replaceAll(r'\', '/')] = k;
      }
      const izin = {
        'lib/screens/add_asset_screen.dart': 1,
        'lib/screens/csv_import_screen.dart': 1,
        'lib/screens/settings_screen.dart': 2,
      };
      for (final e in sayim.entries) {
        expect(e.value, lessThanOrEqualTo(izin[e.key] ?? 0),
            reason: '${e.key}: düğmeyi SandikAsyncButton/SandikAsyncTap '
                'yap; düğmeden geçmeyen tetik için `mesgul:` ver.');
      }
    });

    test('async düğmede titreşim tek kural (bileşen varsayılanı)', () {
      // 2026-10-08 taşımasında üç grup farklı titreşim seçmişti (none /
      // selection / medium). İstek atan dokunuş kalıcı sonuçludur →
      // `SandikHaptic.medium` (bileşen varsayılanı); çağıran ezmez.
      final ihlal = <String>[];
      final desen = RegExp(r'SandikAsync(Button|Tap)[\w.]*\(');
      for (final f in dosyalar) {
        final s = f.readAsStringSync();
        for (final m in desen.allMatches(s)) {
          var d = 0;
          for (var i = m.end - 1; i < s.length; i++) {
            if (s[i] == '(') d++;
            if (s[i] == ')' && --d == 0) {
              final govde = s.substring(m.end, i);
              if (govde.contains('haptic:') &&
                  !f.path.endsWith('sandik_async_button.dart')) {
                ihlal.add(f.path);
              }
              break;
            }
          }
        }
      }
      expect(ihlal, isEmpty);
    });
  });
}
