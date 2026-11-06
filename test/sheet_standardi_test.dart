import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Sheet standardının kilidi (2026-11-06; Ar-Ge 5 Kas 22:40 #1, 6 Kas
/// 08:45 #2, `docs/TASARIM_DILI.md` §4 "Yüzeyler").
///
/// Kabuk (zemin, tutamaç, başlık, klavye payı) `showSandikSheet`'ten gelir.
/// Çağrı yerinde kalan `backgroundColor:` ve elle yazılmış `SandikTutamac(`
/// yalnız bilinçli sahnelerdir (şeffaf zeminli özel şekiller, tam sayfa
/// varlık görünümü, kutlama sayfası, ekleme seçicileri). Sayılar yalnız
/// AZALABİLİR: yeni bir sheet zemin ya da tutamaç yazıyorsa standart
/// bozuluyordur. Bir sahne gerçekten istisnaysa sayıyı artırmak yerine
/// önce `TASARIM_DILI.md` §4'e gerekçe yazılır.
void main() {
  // 2026-11-06 taşımasından sonra kalanlar (öncesi: 69 zemin, 40 tutamaç).
  const zeminTavani = 18;
  const tutamacTavani = 8;

  final dosyalar = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('.dart') &&
          !f.path.contains('${Platform.pathSeparator}generated') &&
          !f.path.endsWith('theme${Platform.pathSeparator}sandik.dart'))
      .toList();

  /// Her `showSandikSheet(...)` çağrısının argüman listesi (parantez
  /// dengesiyle; builder gövdesi de içinde).
  Iterable<(String, String)> cagrilar() sync* {
    final bas = RegExp(r'showSandikSheet\s*(<[^(]*>)?\(');
    for (final f in dosyalar) {
      final k = f.readAsStringSync();
      for (final m in bas.allMatches(k)) {
        var i = m.end, d = 1;
        while (d > 0 && i < k.length) {
          final c = k[i++];
          if (c == '(') d++;
          if (c == ')') d--;
        }
        yield (f.path, k.substring(m.start, i));
      }
    }
  }

  /// Çağrının KENDİ `backgroundColor:` argümanı: `context:` ile aynı
  /// girintide. Builder içindeki düğme/çip zemini sayılmaz.
  bool kendiZemini(String cagri) {
    final ctx = RegExp(r'\n([ \t]*)context:').firstMatch(cagri);
    if (ctx == null) return false;
    return RegExp('\\n${ctx.group(1)}backgroundColor:').hasMatch(cagri);
  }

  test('çağrı yerinde zemin rengi yalnız azalabilir', () {
    final kalan = [
      for (final (yol, c) in cagrilar())
        if (kendiZemini(c)) yol,
    ];
    expect(kalan.length, lessThanOrEqualTo(zeminTavani),
        reason: 'Zemin varsayılanı surface2 (showSandikSheet). '
            'Yeni `backgroundColor:` yazma; kalanlar: $kalan');
  });

  test('elle tutamaç yalnız azalabilir (kabuk çiziyor)', () {
    final kalan = [
      for (final f in dosyalar)
        for (final _ in RegExp(r'\bSandikTutamac\(')
            .allMatches(f.readAsStringSync()))
          f.path,
    ];
    expect(kalan.length, lessThanOrEqualTo(tutamacTavani),
        reason: 'Tutamaç `showSandikSheet` kabuğunda. Kalanlar: $kalan');
  });

  test("Material'ın showDragHandle'ı kullanılmaz (çift tutamaç)", () {
    expect([
      for (final (yol, c) in cagrilar())
        if (c.contains('showDragHandle')) yol,
    ], isEmpty);
  });

  Future<void> ac(WidgetTester t,
      {String? baslik,
      String? altMetin,
      Color? zemin,
      bool icerideTutamac = false,
      double klavye = 0}) async {
    t.view.viewInsets = FakeViewPadding(bottom: klavye * t.view.devicePixelRatio);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [SandikPalette.dark]),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showSandikSheet<void>(
            context: c,
            baslik: baslik,
            altMetin: altMetin,
            backgroundColor: zemin,
            isScrollControlled: true,
            builder: (ctx) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icerideTutamac) const SandikTutamac(),
                // Payı kendisi ekleyen eski sayfa: kabuktan sonra 0 okur.
                Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(ctx).bottom),
                  child: const SizedBox(
                      key: ValueKey('icerik'), height: 100, width: 100),
                ),
              ],
            ),
          ),
          child: const Text('aç'),
        ),
      ),
    ));
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
  }

  Iterable<Container> gorunenTutamaclar(WidgetTester t) => t
      .widgetList<Container>(find.descendant(
          of: find.byType(SandikTutamac), matching: find.byType(Container)))
      .where((c) => c.constraints?.maxWidth == 36);

  testWidgets('varsayılan: surface2 zemin + tek tutamaç', (t) async {
    await ac(t);
    final sayfa = t.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sayfa.backgroundColor, SandikPalette.dark.surface2);
    expect(gorunenTutamaclar(t).length, 1);
  });

  testWidgets('içerikte kalan tutamaç çift çizilmez', (t) async {
    await ac(t, icerideTutamac: true);
    expect(gorunenTutamaclar(t).length, 1);
  });

  testWidgets('şeffaf zemin: kabuk tutamaç çizmez, sayfanınki görünür',
      (t) async {
    await ac(t, zemin: Colors.transparent, icerideTutamac: true);
    expect(gorunenTutamaclar(t).length, 1);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    await ac(t, zemin: Colors.transparent);
    expect(gorunenTutamaclar(t), isEmpty);
  });

  testWidgets('baslik: tek stil, başlık semantiği, tek satır alt metin',
      (t) async {
    await ac(t, baslik: 'Raporlar', altMetin: 'Kısa açıklama');
    final b = t.widget<Text>(find.text('Raporlar'));
    expect(b.style?.fontWeight, FontWeight.w600);
    expect(find.byType(SandikSheetBasligi), findsOneWidget);
    expect(t.widget<Text>(find.text('Kısa açıklama')).maxLines, 1);
    expect(
        t.getSemantics(find.text('Raporlar')),
        matchesSemantics(isHeader: true, label: 'Raporlar'));
  });

  testWidgets('klavye payı kabukta, içerik çift pay almaz', (t) async {
    await ac(t, klavye: 300);
    final ekran = t.view.physicalSize.height / t.view.devicePixelRatio;
    final icerik = t.getRect(find.byKey(const ValueKey('icerik')));
    // İçerik klavyenin hemen üstünde; eski sayfanın kendi payı 0 okundu
    // (okusaydı 300 + 300 pay ile ekranın dışına itilirdi).
    expect(icerik.bottom, closeTo(ekran - 300, 1));
  });
}
