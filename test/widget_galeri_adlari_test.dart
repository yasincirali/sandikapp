// iOS widget galerisinde her widget'ın adı ayrı ve işini söyler.
//
// Ar-Ge 2026-10-30 #3 (yasin "yap"): portföy widget'ı ile kilit ekranı
// widget'ının ikisi de "sandık" adını taşıyordu; galeride sekiz sayfa
// kayarken aynı başlık iki ayrı şeyi anlatıyordu. Uygulama adı galeride
// zaten üstte yazdığı için ad işi söyler. `kind` değişmez: kurulu widget'lar
// yerinde kalır.
import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

void main() {
  const dosyalar = [
    'ios/SandikWidget/SandikHomeWidget.swift',
    'ios/SandikWidget/SandikVarlikWidget.swift',
    'ios/SandikWidget/SandikVitrinWidget.swift',
  ];

  List<String> adlar() => [
        for (final d in dosyalar)
          for (final m in RegExp(r'\.configurationDisplayName\("([^"]*)"\)')
              .allMatches(ekranKaynagiSync(d)))
            m.group(1)!,
      ];

  test('galeri adları tekil ve uygulama adını tekrarlamıyor', () {
    final a = adlar();
    expect(a, hasLength(4));
    expect(a.toSet(), hasLength(a.length), reason: 'aynı adlı iki widget: $a');
    expect(a, isNot(contains('sandık')));
    expect(
      a,
      containsAll(['Portföy', 'Portföy · kilit ekranı', 'Tek varlık', 'Vitrin']),
    );
  });

  test('kind değişmedi: kurulu widget\'lar yerinde kalır', () {
    final ana = ekranKaynagiSync('ios/SandikWidget/SandikHomeWidget.swift');
    expect(ana, contains('let kind = "SandikWidget"'));
    expect(ana, contains('let kind = "SandikKilitWidget"'));
  });
}
