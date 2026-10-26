import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/services/son_bakilanlar.dart';
import 'package:shared_preferences/shared_preferences.dart';

VarlikKimligi _k(String t) =>
    VarlikKimligi(ticker: t, name: t, type: AssetType.hisse, currency: 'TRY');

/// "Son baktıkların" — cihazda, en çok 8 (genel aramada görünen 5),
/// tekrar yukarı taşınır, hesaba bağlı, çıkışta silinir.
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

  test('genel arama: süzülen ayrılır, en çok ${SonBakilanlar.gosterimSiniri}, '
      'sıra korunur', () {
    final l = [for (var i = 0; i < 8; i++) _k('X$i.IS')];
    final haric = {l[0].key, l[2].key};
    final g = SonBakilanlar.gorunenler(l, haric);
    expect(g, hasLength(SonBakilanlar.gosterimSiniri));
    expect(g.map((k) => k.ticker),
        ['X1.IS', 'X3.IS', 'X4.IS', 'X5.IS', 'X6.IS'],
        reason: 'süzülenler beş yeri eritmez');
    expect(SonBakilanlar.gorunenler(const [], haric), isEmpty);
  });

  test('tek kaldırma diske yazılır, ötekiler kalır', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SonBakilanlar.instance..sifirlaTest();
    await s.kaydet('u1', _k('A.IS'));
    await s.kaydet('u1', _k('B.IS'));
    await s.kaldir('u1', _k('A.IS'));
    expect(s.liste.value.map((k) => k.ticker), ['B.IS']);
    s.sifirlaTest();
    await s.yukle('u1');
    expect(s.liste.value.map((k) => k.ticker), ['B.IS']);
  });

  test('sil (çıkış): yalnız o hesabın kaydı gider', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SonBakilanlar.instance..sifirlaTest();
    await s.kaydet('u2', _k('C.IS'));
    s.sifirlaTest();
    await s.kaydet('u1', _k('A.IS'));
    await s.sil('u1');
    expect(s.liste.value, isEmpty, reason: 'bellekteki liste de boşalır');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('son_bakilanlar_v1_u1'), isNull);
    await s.yukle('u2');
    expect(s.liste.value.map((k) => k.ticker), ['C.IS']);
  });

  test('bozuk diskteki değer yok sayılır', () async {
    SharedPreferences.setMockInitialValues({'son_bakilanlar_v1_u1': '{x'});
    final s = SonBakilanlar.instance..sifirlaTest();
    await s.yukle('u1');
    expect(s.liste.value, isEmpty);
    expect(SonBakilanlar.cozumle('{"t":"A"}'), isEmpty, reason: 'liste değil');
  });
}
