// Ar-Ge 22 Kas 1703: karşılaştırma ve ekstre ekranında paywall dönüşü okunur.
// Kaynak taraması: ekranlar ağ/Premium durumu ister; kapı davranışı kodda kilitlenir.
import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

void main() {
  final kiyas = ekranKaynagiSync('lib/screens/comparison_screen.dart');
  final ekstre = ekranKaynagiSync('lib/screens/csv_import_screen.dart');

  test('1: karşılaştırma satın alınca aynı seriyi ekler', () {
    expect(kiyas, contains('Future<bool> _paywallAc()'));
    expect(kiyas, contains('aldi == true'));
    expect(kiyas, contains('Future<void> _satinAlinca(SymbolHit hit)'));
    expect(kiyas, contains('_kilitliOnizleme = null'));
    expect(kiyas, contains('_add(hit, satinAlindi: true)'));
    // Tavan: Premium'da bile en fazla kKarsilastirmaEnFazla.
    expect(kiyas, contains('_selected.length >= kKarsilastirmaEnFazla'));
    // Ham paywall çağrısı artık yalnız _paywallAc içinde.
    expect(RegExp('PaywallScreen.show').allMatches(kiyas).length, 1);
  });

  test('2: ekran görüntüsü satın alınca seçici açılır', () {
    expect(ekstre, contains("source: 'ekran_goruntusu') !="));
    expect(ekstre, contains('pickMultiImage'));
  });

  test('3: kilitliyken simge kilit ve okuyucu etiketi var', () {
    expect(ekstre, contains('Icons.lock_outline_rounded'));
    expect(ekstre, contains('semanticLabel: context.l10n.alarmPremiumGerekli'));
  });

  test('4: AI eşleme sunucu kilidi bir kez yeniden dener, yoksa mesaj', () {
    expect(ekstre, contains('{bool yenidenDeneme = false}'));
    expect(ekstre, contains('aldi && !yenidenDeneme'));
    expect(ekstre, contains('_aiIleEsle(yenidenDeneme: true)'));
    expect(ekstre, contains('_kartMesaji = l.prmKilitEkstreAi'));
  });

  test('5: eşleme kartı başlığı w600 tavanında', () {
    final i = ekstre.indexOf('importMappingTitle');
    expect(ekstre.substring(i, i + 200), contains('FontWeight.w600'));
  });
}
