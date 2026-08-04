import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yaml/yaml.dart';

/// DM Sans `assets/fonts/` altında gömülü olmalı ve google_fonts onu
/// ağa çıkmadan bulabilmeli.
///
/// **Neden pubspec'i doğrudan okuyoruz:** `flutter test` asset/font
/// manifest'ini uygulamadaki gibi yüklemez — pubspec'teki font kaydını
/// bozsanız bile `GoogleFonts.dmSans()` testte sorunsuz döner. Yani
/// "çağrı fırlatmıyor" demek burada hiçbir şey kanıtlamaz. Gerçek
/// değişmez pubspec kaydının kendisidir; onu doğruluyoruz.
///
/// `allowRuntimeFetching = false` iken google_fonts istenen aileyi asset
/// olarak bulamazsa üretimde sistem fontuna düşer. Aile adı paketin
/// beklediğiyle ("DM Sans") birebir uyuşmak zorunda.
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
        'pubspec.yaml içinde "DM Sans" font ailesi yok — google_fonts '
        'çalışma zamanında ağdan indirmeye çalışır.',
      ),
    ) as YamlMap;
  }

  test('pubspec "DM Sans" ailesini tam bu adla kaydeder', () {
    expect(dmSansEntry()['family'], 'DM Sans');
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

  test('main.dart çalışma zamanı indirmesini kapatıyor', () {
    final src = File('lib/main.dart').readAsStringSync();
    expect(src, contains('allowRuntimeFetching = false'));
  });

  test('gömülü font ile stil kurulur ve DM Sans ailesine işaret eder', () {
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = true);

    final style = GoogleFonts.dmSans(fontWeight: FontWeight.w700);
    expect(style.fontFamily, contains('DMSans'));
  });

  testWidgets('Türkçe glifler ve ₺ hata üretmeden render edilir',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text(
            'Portföy · 1.234,56 ₺ · ığşçöü İĞŞÇÖÜ',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
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
