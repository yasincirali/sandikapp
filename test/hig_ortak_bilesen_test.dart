import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_app_bar.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

/// Apple HIG kontrol listesinin ölçülebilir kısmı (`docs/TASARIM_DILI.md`
/// §5, yasin 2026-10-10: "bişey değiştirirken bunu standart olarak
/// sorgulayalım").
///
/// `touch_target_size_test` kaynak tarar ve yalnız sabit sayıları görür;
/// burada ortak bileşenler GERÇEKTEN çizilir ve Flutter'ın kendi erişilebilirlik
/// kılavuzlarıyla ölçülür: iOS 44×44 pt, her dokunulabilir öğenin ekran
/// okuyucu etiketi, metin kontrastı (WCAG AA), yazı ×2'de taşma. Material'in
/// 48 dp önerisi (`androidTapTargetGuideline`) bilerek kilitlenmedi: tek eşik
/// `SandikTouch.min` 44; segment ve satırlar 44'te kalır, Material düğmeleri
/// zaten 48 alır (karar: TASARIM_DILI.md §7). Ekranlar bu
/// bileşenlerden kurulduğu için buradaki bir gerileme her ekrana yayılır.
/// Yeni ortak bileşen eklenince `vitrin`'e de eklenir.
void main() {
  Widget vitrin({required Brightness parlaklik, double yaziOlcegi = 1}) {
    final palet =
        parlaklik == Brightness.dark ? SandikPalette.dark : SandikPalette.light;
    return MaterialApp(
      theme: SandikApp.buildTheme(palet, parlaklik),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 1400),
          textScaler: TextScaler.linear(yaziOlcegi),
        ),
        child: Builder(builder: (context) {
          return Scaffold(
            appBar: SandikAppBar(
              title: 'Başlık',
              onBack: () {},
              actions: [
                IconButton(
                  tooltip: 'Yenile',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {},
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(SandikSpace.md),
              children: [
                SandikAsyncButton(
                  onPressed: () async {},
                  child: const Text('Kaydet'),
                ),
                const SizedBox(height: SandikSpace.md),
                SandikAsyncButton.kompakt(
                  onPressed: () async {},
                  child: const Text('Onayla'),
                ),
                const SizedBox(height: SandikSpace.md),
                SandikAsyncTap(
                  onTap: () async {},
                  semanticLabel: 'Fiyatları yenile',
                  child: const SizedBox(
                    width: SandikTouch.min,
                    height: SandikTouch.min,
                    child: Icon(Icons.sync_rounded),
                  ),
                ),
                const SizedBox(height: SandikSpace.md),
                FilledButton(onPressed: () {}, child: const Text('Devam')),
                OutlinedButton(onPressed: () {}, child: const Text('Vazgeç')),
                TextButton(onPressed: () {}, child: const Text('Ayrıntı')),
                const SizedBox(height: SandikSpace.md),
                SandikSegment(
                  adet: 3,
                  secili: 0,
                  onSec: (_) {},
                  oge: (c, i, s) => Center(child: Text(['1H', '1A', '1Y'][i])),
                ),
                const SizedBox(height: SandikSpace.md),
                SandikTappable(
                  onTap: () {},
                  semanticLabel: 'Varlık satırı',
                  child: const SizedBox(
                    height: SandikTouch.min,
                    child: Text('THYAO'),
                  ),
                ),
                // Anahtar etiketsiz tek başına durmaz: satır metniyle
                // birleşir (ya da `SwitchListTile.adaptive`).
                MergeSemantics(
                  child: Row(children: [
                    const Expanded(child: Text('Bildirimler')),
                    Switch.adaptive(value: true, onChanged: (_) {}),
                  ]),
                ),
                const SizedBox(height: SandikSpace.md),
                SandikSectionHeader(title: 'Bölüm'),
                SizedBox(
                  height: 260,
                  child: SandikErrorView(
                    error: Exception('x'),
                    onRetry: () async {},
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  for (final parlaklik in Brightness.values) {
    final ad = parlaklik == Brightness.dark ? 'koyu' : 'açık';

    testWidgets('ortak bileşenler HIG dokunma hedefi ve etiket ($ad)',
        (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(vitrin(parlaklik: parlaklik));
      await t.pump();
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('ortak bileşenler metin kontrastı ($ad)', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(vitrin(parlaklik: parlaklik));
      await t.pump();
      await expectLater(t, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('yazı ×2 (Dynamic Type) ortak bileşenleri taşırmıyor', (t) async {
    await t.pumpWidget(vitrin(parlaklik: Brightness.dark, yaziOlcegi: 2));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  test('ikon düğmesinde ekran okuyucu etiketi (tooltip) var', () {
    // HIG "Accessibility": yalnız ikondan oluşan düğme VoiceOver'da "düğme"
    // diye okunur, ne yaptığı söylenmez. `IconButton.tooltip` hem uzun
    // basma ipucu hem semantik etikettir. 2026-10-10 denetiminde 11 düğme
    // etiketsizdi, hepsi etiketlendi; yeni IconButton etiketsiz girmez.
    // `IconButton.styleFrom(` bir stil yardımcısıdır, düğme değil.
    final etiketsiz = <String>[];
    final desen =
        RegExp(r'\bIconButton(\.(filled|filledTonal|outlined))?\s*\(');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in desen.allMatches(src)) {
        var derinlik = 0;
        var son = m.end - 1;
        for (var j = m.end - 1; j < src.length; j++) {
          if (src[j] == '(') derinlik++;
          if (src[j] == ')' && --derinlik == 0) {
            son = j;
            break;
          }
        }
        if (!src.substring(m.end, son).contains('tooltip:')) {
          final satir = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          etiketsiz.add('${f.path}:$satir');
        }
      }
    }
    expect(etiketsiz, isEmpty,
        reason: 'IconButton\'a `tooltip:` ver (l10n\'lu ekranda '
            'context.l10n).\n${etiketsiz.join('\n')}');
  });
}
