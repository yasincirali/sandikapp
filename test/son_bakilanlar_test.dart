import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/services/son_bakilanlar.dart';
import 'package:shared_preferences/shared_preferences.dart';

VarlikKimligi _k(String t) =>
    VarlikKimligi(ticker: t, name: t, type: AssetType.hisse, currency: 'TRY');

/// "Son baktıkların" — cihazda, en çok 8, tekrar yukarı taşınır.
void main() {
  test('yeni başa gelir; tekrar bakılan yukarı taşınır, çoğalmaz', () {
    var l = <VarlikKimligi>[];
    l = SonBakilanlar.ekle(l, _k('A.IS'));
    l = SonBakilanlar.ekle(l, _k('B.IS'));
    l = SonBakilanlar.ekle(l, _k('A.IS'));
    expect(l.map((k) => k.ticker), ['A.IS', 'B.IS']);
  });

  test('en çok ${SonBakilanlar.enFazla} kayıt', () {
    var l = <VarlikKimligi>[];
    for (var i = 0; i < 12; i++) {
      l = SonBakilanlar.ekle(l, _k('X$i.IS'));
    }
    expect(l, hasLength(SonBakilanlar.enFazla));
    expect(l.first.ticker, 'X11.IS');
  });

  test('kodla → çözümle kimliği korur (alt kategori, para birimi)', () {
    const altin = VarlikKimligi(
        ticker: 'ALTIN_CEYREK',
        name: 'Çeyrek Altın',
        type: AssetType.altin,
        subCategory: 'Çeyrek Altın',
        currency: 'TRY');
    final geri = SonBakilanlar.cozumle(SonBakilanlar.kodla([altin]));
    expect(geri.single.key, altin.key);
    expect(geri.single.currency, 'TRY');
  });

  test('bozuk veri ve tanınmayan tür listeyi düşürmez', () {
    expect(SonBakilanlar.cozumle('bozuk'), isEmpty);
    final l = SonBakilanlar.cozumle(
        '[{"t":"A.IS","n":"A","y":"yokboyletur","c":"TRY"},'
        '{"t":"B.IS","n":"B","y":"hisse","c":"TRY"}]');
    expect(l.map((k) => k.ticker), ['B.IS']);
  });

  test('kullanıcıya göre ayrı saklanır, temizlenir', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SonBakilanlar.instance..sifirlaTest();
    await s.kaydet('u1', _k('A.IS'));
    expect(s.liste.value.map((k) => k.ticker), ['A.IS']);

    s.sifirlaTest();
    await s.yukle('u2');
    expect(s.liste.value, isEmpty, reason: 'başka hesabın izi görünmez');

    s.sifirlaTest();
    await s.yukle('u1');
    expect(s.liste.value.map((k) => k.ticker), ['A.IS']);
    await s.temizle('u1');
    s.sifirlaTest();
    await s.yukle('u1');
    expect(s.liste.value, isEmpty);
  });
}
