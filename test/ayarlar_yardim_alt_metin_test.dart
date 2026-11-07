import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Ayarlar › Yardım: başlığı tekrarlayan alt metinler kalktı (Ar-Ge 7 Kas
/// 20:30 #4). "sandık'ı değerlendir / Mağazada puan ver", "Yenilikler / Bu
/// sürümde neler değişti", "Tanıtım turunu yeniden izle / Ekranların ne işe
/// yaradığını hatırla" satırları tek satır. Hub satırının alt metni
/// bölümün gerçek satırlarını sayar.
void main() {
  Map<String, dynamic> arb(String dil) =>
      jsonDecode(File('lib/l10n/app_$dil.arb').readAsStringSync())
          as Map<String, dynamic>;

  test('silinen alt metin anahtarları geri gelmez', () {
    for (final dil in ['tr', 'en']) {
      final a = arb(dil);
      for (final k in [
        'rateAppSubtitle',
        'whatsNewSubtitle',
        'replayTourSubtitle',
      ]) {
        expect(a.containsKey(k), isFalse, reason: '$dil: $k');
      }
    }
  });

  test('Yardım hub alt metni bölümün satırlarını anlatır', () {
    final tr = arb('tr')['settingsHelpSubtitle'] as String;
    expect(tr, contains('Sık sorulanlar'));
    expect(tr, contains('yasal belgeler'));
    // Tanıtım turu ve gizlilik/koşullar artık ayrı satır değil.
    expect(tr, isNot(contains('gizlilik')));
  });

  test('Yardım bölümündeki üç satır alt metinsiz kurulur', () {
    final k = ekranKaynagiSync('lib/screens/settings_screen.dart');
    final yardim = k.substring(k.indexOf('List<Widget> _yardim()'),
        k.indexOf('final yasal = _SettingsTile('));
    expect(yardim, isNot(contains('rateAppSubtitle')));
    expect(yardim, isNot(contains('whatsNewSubtitle')));
    expect(yardim, isNot(contains('replayTourSubtitle')));
  });
}
