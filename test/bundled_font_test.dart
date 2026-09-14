import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:yaml/yaml.dart';

/// DM Sans `assets/fonts/` altında gömülü olmalı ve kod aileye tek adla
/// işaret etmeli.
///
/// **Neden pubspec'i doğrudan okuyoruz:** `flutter test` asset/font
/// manifest'ini uygulamadaki gibi yüklemez — pubspec'teki font kaydını
/// bozsanız bile `TextStyle(fontFamily: …)` testte sorunsuz döner. Yani
/// "çağrı fırlatmıyor" demek burada hiçbir şey kanıtlamaz. Gerçek
/// değişmez pubspec kaydının kendisidir; onu doğruluyoruz.
///
/// 2026-09-14: `google_fonts` kaldırıldı. Eskiden aile adı paketin
/// beklediğiyle uyuşmak zorundaydı; şimdi `kSandikFontFamily` ile pubspec
/// kaydı birebir aynı olmalı, aksi halde üretimde sistem fontuna düşülür.
void main() {
  late YamlMap pubspec;

  setUpAll(() {
    pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  });

  YamlMap dmSansEntry() {
    final fonts = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;
    return fonts.firstWhere(
      (f) => f['family'] == 'DM Sans',
      orElse: () => throw StateError(
        'pubspec.yaml içinde "DM Sans" font ailesi yok — uygulama sistem '
        'fontuna düşer.',
      ),
    ) as YamlMap;
  }

  test('pubspec "DM Sans" ailesini tam bu adla kaydeder', () {
    expect(dmSansEntry()['family'], kSandikFontFamily);
  });

  test('kodda kullanılan tüm ağırlıklar gömülü', () {
    final declared = {
      for (final f in dmSansEntry()['fonts'] as YamlList) f['weight'] as int,
    };
    // lib/ taramasıyla bulunanlar: 400, 500, 600, 700, 800, 900
    expect(declared, containsAll([400, 500, 600, 700, 800, 900]));
  });

  test('kayıtlı her ttf dosyası gerçekten diskte var ve boş değil', () {
    for (final f in dmSansEntry()['fonts'] as YamlList) {
      final file = File(f['asset'] as String);
      expect(file.existsSync(), isTrue, reason: '${f['asset']} yok');
      expect(file.lengthSync(), greaterThan(10000),
          reason: '${f['asset']} bozuk/eksik görünüyor');
    }
  });

  test('her ttf, kaydedildiği ağırlığı taşıyor (OS/2 usWeightClass)', () {
    for (final f in dmSansEntry()['fonts'] as YamlList) {
      final bytes = File(f['asset'] as String).readAsBytesSync();
      expect(_usWeightClass(bytes), f['weight'],
          reason: '${f['asset']} yanlış ağırlıkta bir dosya');
    }
  });

  test('google_fonts geri gelmedi — aile adı tek kaynaktan', () {
    final pubspecSrc = File('pubspec.yaml').readAsStringSync();
    expect(pubspecSrc.contains('google_fonts:'), isFalse,
        reason: 'Bağımlılık kaldırıldı; geri eklemek ağ tuzağını geri getirir.');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('apply(fontFamily: kSandikFontFamily)'), isTrue,
        reason: 'Tema metin ölçeği marka ailesine bağlanmalı.');
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      expect(e.readAsStringSync().contains('GoogleFonts'), isFalse,
          reason: '${e.path} hâlâ google_fonts kullanıyor.');
    }
  });

  test('sandikFont marka ailesine işaret eder', () {
    final style = sandikFont(fontWeight: FontWeight.w700);
    expect(style.fontFamily, kSandikFontFamily);
    expect(style.fontWeight, FontWeight.w700);
  });

  testWidgets('Türkçe glifler ve ₺ hata üretmeden render edilir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text(
            'Portföy · 1.234,56 ₺ · ığşçöü İĞŞÇÖÜ',
            style: sandikFont(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

/// TTF `OS/2` tablosundaki `usWeightClass` alanını okur.
int _usWeightClass(List<int> bytes) {
  final d = ByteData.sublistView(Uint8List.fromList(bytes));
  final numTables = d.getUint16(4);
  for (var i = 0; i < numTables; i++) {
    final o = 12 + i * 16;
    final tag = ascii.decode(bytes.sublist(o, o + 4));
    if (tag == 'OS/2') return d.getUint16(d.getUint32(o + 8) + 4);
  }
  throw StateError('OS/2 tablosu yok — geçerli bir TTF değil');
}
