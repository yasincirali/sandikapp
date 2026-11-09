import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/ekstre/ekran_goruntusu.dart';
import 'package:portfoy_takip/services/ekstre/ekran_goruntusu_sepeti.dart';

/// Ekran görüntüsünden Toplu Ekle sepetine (yasin 2026-10-19): maliyeti
/// okunmayan satır DÜŞMEZ, "sonra girilecek" işaretlenir; adedi okunmayan
/// eklenmez ama adıyla söylenir; tanınmayan fon eklenmez.
void main() {
  final bugun = DateTime(2026, 10, 19);

  test('maliyeti okunan ve okunmayan varlık birlikte sepete girer', () {
    final s = ekranVarliklarindanSepet([
      const EkranVarligi(kod: 'THYAO', tur: 'Hisse', adet: 100, maliyet: 250),
      const EkranVarligi(kod: 'ASELS', tur: 'Hisse', adet: 1250),
    ], bugun: bugun);
    expect(s.kalemler.map((k) => k.quantity), [100, 1250]);
    final thy = s.kalemler[0], asl = s.kalemler[1];
    expect(thy.price, 250);
    expect(thy.maliyetSonra, isFalse);
    expect(thy.type, AssetType.hisse);
    expect(asl.price, 0, reason: 'uydurma maliyet yok');
    expect(asl.maliyetSonra, isTrue);
    expect(s.maliyetiSonraGirilecek, 1);
    expect(s.adediOkunamayan, isEmpty);
  });

  test('adedi okunmayan eklenmez, adıyla listelenir; tanınmayan fon da', () {
    final s = ekranVarliklarindanSepet([
      const EkranVarligi(kod: 'THYAO', tur: 'Hisse', maliyet: 250),
      const EkranVarligi(ad: 'Bilinmez Portföy Fonu', tur: 'Fon', adet: 10),
    ], bugun: bugun);
    expect(s.kalemler, isEmpty);
    expect(s.adediOkunamayan, ['THYAO']);
    expect(s.taninmayanFonlar, ['Bilinmez Portföy Fonu']);
  });

  test('fiyat girilince "sonra" işareti düşer, fiyatsız düzenlemede kalır', () {
    final k = ekranVarliklarindanSepet([
      const EkranVarligi(kod: 'ASELS', tur: 'Hisse', adet: 10),
    ], bugun: bugun).kalemler.single;
    expect(k.copyWith(quantity: 20).maliyetSonra, isTrue);
    expect(k.copyWith(price: 41.5).maliyetSonra, isFalse);
  });

  test('iki görüntüde aynı varlık tek satır olur', () {
    final s = ekranVarliklarindanSepet(ekranVarliklariniBirlestir([
      [const EkranVarligi(kod: 'THYAO', tur: 'Hisse', adet: 100)],
      [const EkranVarligi(kod: 'THYAO', tur: 'Hisse', adet: 100, maliyet: 250)],
    ]), bugun: bugun);
    expect(s.kalemler.length, 1);
    expect(s.kalemler.single.price, 250);
    expect(s.kalemler.single.maliyetSonra, isFalse);
  });
}
