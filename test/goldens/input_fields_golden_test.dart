@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/theme/sandik.dart';

/// Giriş alanları golden'ı — her alan türü × üç zemin × iki tema.
///
/// ## Neden var
///
/// "Alanın içi neden farklı renk?" şikâyeti dört kez geldi; her seferinde
/// kök neden, alanın dolgusunun bulunduğu ZEMİNE göre seçilmemesiydi
/// (sayfa `background`, diyalog `surface1`, alt sayfa `surface2`). Kaynak
/// taraması ve `InputDecorator` ölçümü (`input_fill_consistency_test`) kuralın
/// yazıldığını kanıtlar; bu dosya kuralın GÖZE nasıl göründüğünü sabitler.
/// Emülatörler Flutter'ı siyah çizdiği için (CLAUDE.md) görsel doğrulamanın
/// bu makinedeki yolu bu.
///
/// ## Kabul ölçütü (PNG'ye bakarken)
/// - Dark: hiçbir alanın içi zeminden farklı renkte değil.
/// - Çerçeve her zeminde seçilebiliyor.
/// - Light: beyaz alan krem sayfada öne çıkıyor.
///
/// ## Neden `golden` etiketi ve varsayılanda kapalı
///
/// Golden PNG'ler rasterizer'a ve font hinting'ine duyarlı: bu makinede
/// (Windows) üretilen görüntü CI'ın Linux'unda piksel piksel tutmaz ve
/// testi sahte kırar. Repoda golden düzeni yoktu; `dart_test.yaml`'daki
/// `gorsel` kalıbına uyuldu: etiket tanımlı, varsayılanda atlanır.
///
/// Güncellemek / koşmak için:
///   flutter test --run-skipped --update-goldens test/goldens/input_fields_golden_test.dart
///   flutter test --run-skipped test/goldens/input_fields_golden_test.dart
void main() {
  setUpAll(() async {
    // Test motoru varsayılanda Ahem (kutu) çizer; gerçek görünüm için
    // gömülü DM Sans ve Material ikon fontu yüklenir.
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });

  for (final b in [Brightness.dark, Brightness.light]) {
    testWidgets('giriş alanları — ${b.name}', (tester) async {
      final p = b == Brightness.light ? SandikPalette.light : SandikPalette.dark;
      tester.view.physicalSize = const Size(1000, 1180);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SandikApp.buildTheme(p, b),
        home: const Material(child: _Izgara()),
      ));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey('izgara')),
        matchesGoldenFile('input_fields_${b.name}.png'),
      );
    });
  }
}

class _Izgara extends StatelessWidget {
  const _Izgara();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final zeminler = <(String, Color)>[
      ('background (sayfa)', c.background),
      ('surface1 (diyalog)', c.surface1),
      ('surface2 (alt sayfa)', c.surface2),
    ];
    final turler = <(String, Widget Function(BuildContext))>[
      ('düz', (_) => const _Duz()),
      ('arama', (_) => const _Arama()),
      ('çok satırlı', (_) => const _CokSatir()),
      ('sayı + suffix', (_) => const _Sayi()),
      ('hata', (_) => const _Hata()),
      ('odaklı', (_) => const _Odakli()),
      ('kilitli', (_) => const _Kilitli()),
      ('OTP hücresi', (_) => const _Otp()),
      ('kutu içi arama', (_) => const _KutuIciArama()),
    ];
    return RepaintBoundary(
      key: const ValueKey('izgara'),
      child: ColoredBox(
        color: c.background,
        child: Column(
          children: [
            Row(children: [
              const SizedBox(width: 130),
              for (final z in zeminler)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(SandikSpace.sm),
                    child: Text(z.$1,
                        style: context.t.labelLarge?.copyWith(color: c.text58)),
                  ),
                ),
            ]),
            for (final t in turler)
              Row(children: [
                SizedBox(
                  width: 130,
                  child: Padding(
                    padding: const EdgeInsets.only(left: SandikSpace.sm),
                    child: Text(t.$1,
                        style: context.t.labelLarge?.copyWith(color: c.text58)),
                  ),
                ),
                for (final z in zeminler)
                  Expanded(
                    child: Container(
                      height: 120,
                      color: z.$2,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: SandikSpace.md),
                      child: Builder(builder: t.$2),
                    ),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}

// ── Alan türleri ─────────────────────────────────────────────────────────
// Her biri uygulamadaki bir gerçek kullanımın dekorasyonunu taklit eder
// (hangi ekrandan geldiği yanında). Dolgu HİÇBİRİNDE elle verilmez — kutu
// içi arama dışında her şey temadan (`sandikGirisTemasi`) gelir.

/// Controller'ı `build()` dışında tutar: her karede yenisi yaratılsa metin
/// sıfırlanır ve controller'lar sızar.
class _Metinli extends StatefulWidget {
  const _Metinli(this.metin, this.alan);
  final String metin;
  final Widget Function(BuildContext, TextEditingController) alan;
  @override
  State<_Metinli> createState() => _MetinliState();
}

class _MetinliState extends State<_Metinli> {
  late final _c = TextEditingController(text: widget.metin);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.alan(context, _c);
}

/// Hedef tutar (hedef_sheet) — dekorasyon: yalnız hint.
class _Duz extends StatelessWidget {
  const _Duz();
  @override
  Widget build(BuildContext context) =>
      const TextField(decoration: InputDecoration(hintText: '1.000.000'));
}

/// Görünüm arama (gorunum_cipi), karşılaştırma araması.
class _Arama extends StatelessWidget {
  const _Arama();
  @override
  Widget build(BuildContext context) => const TextField(
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Ara...',
          prefixIcon: Icon(Icons.search_rounded, size: 20),
        ),
      );
}

/// Geri bildirim (settings) / CSV yapıştırma.
class _CokSatir extends StatelessWidget {
  const _CokSatir();
  @override
  Widget build(BuildContext context) => _Metinli(
        'Grafikte dokununca\nfiyat görünsün',
        (_, c) => TextField(controller: c, minLines: 2, maxLines: 2),
      );
}

/// Hızlı düzeltme (quick_adjust_dialog), temettü (dividend_dialog).
class _Sayi extends StatelessWidget {
  const _Sayi();
  @override
  Widget build(BuildContext context) => _Metinli(
        '1.250,00',
        (context, c) => TextField(
          controller: c,
          decoration: InputDecoration(
            suffixText: 'TRY',
            suffixStyle:
                context.t.titleMedium?.copyWith(color: context.c.text58),
          ),
        ),
      );
}

/// Hedef fiyat hatalı (alarm_kur_sheet).
class _Hata extends StatelessWidget {
  const _Hata();
  @override
  Widget build(BuildContext context) => _Metinli(
        'abc',
        (_, c) => TextField(
          controller: c,
          decoration:
              const InputDecoration(errorText: 'Geçerli bir fiyat gir'),
        ),
      );
}

/// Odak tek alanda olabileceği için `InputDecorator(isFocused: true)` —
/// TextField'ın içte kullandığı aynı dekoratör, aynı tema birleştirmesi.
class _Odakli extends StatelessWidget {
  const _Odakli();
  @override
  Widget build(BuildContext context) => InputDecorator(
        isFocused: true,
        decoration: const InputDecoration(),
        child: Text('GARAN',
            style: context.t.bodyLarge?.copyWith(color: context.c.text90)),
      );
}

/// Kilitli ortaklık kodu (profile_screen, `enabled: false`; metin söner).
class _Kilitli extends StatelessWidget {
  const _Kilitli();
  @override
  Widget build(BuildContext context) => _Metinli(
        'K7M2P-9QX4R',
        (context, c) => TextField(
          enabled: false,
          controller: c,
          style: TextStyle(color: context.c.text36),
          decoration: context.inputDecoration('XXXXX-XXXXX'),
        ),
      );
}

/// OTP hücresi — otp_verification_screen `_buildOtpCell` dekorasyonunun
/// aynısı: dolu, boş ve kilitli (doğrulama sürerken) hücre yan yana.
class _Otp extends StatelessWidget {
  const _Otp();
  @override
  Widget build(BuildContext context) {
    Widget hucre(String s, {bool enabled = true}) => _Metinli(
          s,
          (context, c) {
            final dolu = s.isNotEmpty;
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: c,
                enabled: enabled,
                textAlign: TextAlign.center,
                style: context.t.numLarge.copyWith(
                    color: enabled ? context.c.text90 : context.c.text36),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(SandikRadius.md),
                    borderSide: BorderSide(
                      color: dolu ? context.c.amberText : context.c.hairline,
                      width: dolu ? 1.5 : 1,
                    ),
                  ),
                ),
              ),
            );
          },
        );

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      hucre('4'),
      const SizedBox(width: SandikSpace.sm),
      hucre(''),
      const SizedBox(width: SandikSpace.sm),
      hucre('7', enabled: false),
    ]);
  }
}

/// Seçici alt sayfası araması (add_asset `_PickerShell`) — dolgu ve çerçeve
/// dıştaki kutuda, alan `filled: false`.
class _KutuIciArama extends StatelessWidget {
  const _KutuIciArama();
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: SandikTouch.min),
        decoration: BoxDecoration(
          color: context.inputFill,
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(color: context.c.hairline),
        ),
        child: Row(children: [
          const SizedBox(width: SandikSpace.smd),
          Icon(Icons.search_rounded, size: 18, color: context.c.text58),
          const SizedBox(width: SandikSpace.sm),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Ara...',
                hintStyle:
                    context.t.bodyLarge?.copyWith(color: context.c.text36),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
      );
}
