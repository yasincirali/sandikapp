import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/l10n/l10n.dart';

import 'helpers/kaynak.dart';

/// yasin 2 Kas 2026: fonda GÜNLÜK görünümde mum aralığı seçicisi çıkmıyor
/// (TEFAS günde tek fiyat) ve bu arıza sanılıyordu → tek satır açıklama.
/// Aynı gün fon birimi "pay" oldu; İngilizcede "units".
void main() {
  test('fon GÜNLÜK notu yalnız fonda ve gün içi dönemde', () {
    final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    final i = k.indexOf('fonGunlukTekFiyatNotu');
    expect(i, greaterThan(0));
    final once = k.substring(i - 400, i);
    expect(once, contains('isIntraday'));
    expect(once, contains('AssetType.fon'));
  });

  test('fon birimi "pay" iki dilde doğru yazılır', () {
    expect(birimMetni(AppLocalizationsTr(), 'pay'), 'pay');
    expect(birimMetni(AppLocalizationsEn(), 'pay'), 'units');
    expect(birimMetni(AppLocalizationsEn(), 'lot'), 'lot');
  });
}
