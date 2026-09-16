import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

/// "Bu hafta" çipinde yüzde işareti BİR KEZ yazılır (2026-09-16).
///
/// Ölçülen arıza: `fmtPct` "%1,2" döndürüyor, `pctDown` şablonu da
/// "%{pct} eksi" — ikisi birleşince ekranda "%%1,2 eksi", ekran okuyucuda
/// "yüzde %1,2 ekside" çıkıyordu. Sayıyı biçimlendiren taraf ile cümleyi
/// kuran taraf aynı işareti iki kez ekliyordu.
void main() {
  test('şablonlar yüzde işaretini KENDİLERİ taşıyor', () {
    final tr = AppLocalizationsTr();
    // Çip ham sayı veriyor; şablon "%" ekliyor.
    expect(tr.pctDown('1,2'), '%1,2 eksi');
    expect(tr.pctUp('1,2'), '%1,2 artı');
    // Erişilebilirlik cümlesi "yüzde" KELİMESİNİ taşıyor.
    expect(tr.weeklyDownSemantics('1,2').contains('yüzde 1,2'), isTrue);
    expect(tr.weeklyUpSemantics('1,2').contains('yüzde 1,2'), isTrue);
  });

  test('fmtPct şablona verilirse ÇİFT işaret olur — bu yüzden fmtNum', () {
    // Arızanın kendisi: kayıt olarak duruyor ki biri geri değiştirmesin.
    final yanlis = fmtPct(1.2278.abs(), digits: 1); // "%1,2"
    expect(AppLocalizationsTr().pctDown(yanlis), '%%1,2 eksi');

    final dogru = fmtNum(1.2278.abs(), digits: 1); // "1,2"
    expect(AppLocalizationsTr().pctDown(dogru), '%1,2 eksi');
  });

  test('çip kaynağı fmtNum kullanır', () {
    // Kaynak taraması: `fmtPct` geri sızarsa çift işaret döner.
    final src = File('lib/widgets/weekly_summary_chip.dart').readAsStringSync();
    expect(src.contains('fmtNum(pct.abs(), digits: 1)'), isTrue);
    expect(src.contains('fmtPct(pct.abs()'), isFalse,
        reason: 'şablon zaten % taşıyor');
  });
}
