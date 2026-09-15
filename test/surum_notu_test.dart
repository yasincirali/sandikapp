import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/config/surum_notlari.dart';
import 'package:portfoy_takip/services/surum_notu_service.dart';

SurumNotu _not(String surum, {bool onemli = true}) => SurumNotu(
      surum: surum,
      tarih: 'Eylül 2026',
      onemli: onemli,
      yenilikler: const [Yenilik(baslik: 'X', aciklama: 'Y')],
    );

void main() {
  // En yeni önce — gerçek listeyle aynı sıralama sözleşmesi.
  final notlar = [_not('1.3.0'), _not('1.2.0'), _not('1.1.0'), _not('1.0.0')];

  test('ilk kurulumda gösterilmez — tanıtım turunun üstüne binmemeli', () {
    expect(
      yeniNotlar(notlar: notlar, calisanSurum: '1.3.0', sonGorulen: null),
      isEmpty,
    );
  });

  test('aynı sürüm ikinci kez gösterilmez', () {
    expect(
      yeniNotlar(notlar: notlar, calisanSurum: '1.3.0', sonGorulen: '1.3.0'),
      isEmpty,
    );
  });

  test('bir sürüm atlanmışsa tek not', () {
    final c = yeniNotlar(
        notlar: notlar, calisanSurum: '1.3.0', sonGorulen: '1.2.0');
    expect(c.map((n) => n.surum).toList(), ['1.3.0']);
  });

  test('atlanan sürümler BİRİKİR — aradaki sürümü açmamış olmak yenilikleri '
      'kaçırmak demek değil', () {
    final c = yeniNotlar(
        notlar: notlar, calisanSurum: '1.3.0', sonGorulen: '1.0.0');
    expect(c.map((n) => n.surum).toList(), ['1.3.0', '1.2.0', '1.1.0']);
  });

  test('çalışan sürümün notu YAZILMAMIŞSA hiçbir şey gösterilmez', () {
    // Not yazmayı unutmuş olabiliriz; yanlış sürümün notunu göstermek
    // hiç göstermemekten kötüdür.
    expect(
      yeniNotlar(notlar: notlar, calisanSurum: '9.9.9', sonGorulen: '1.0.0'),
      isEmpty,
    );
  });

  test('hiçbiri önemli değilse otomatik AÇILMAZ (yama sürümleri)', () {
    final yamalar = [_not('1.3.1', onemli: false), _not('1.3.0')];
    expect(
      yeniNotlar(notlar: yamalar, calisanSurum: '1.3.1', sonGorulen: '1.3.0'),
      isEmpty,
    );
  });

  test('birikmiş listede TEK önemli varsa hepsi gösterilir', () {
    // Kullanıcı 1.2.0'dayken 1.3.1'e atladı: arada 1.3.0 (önemli) ve
    // 1.3.1 (yama) var. Yama tek başına modal açmazdı ama önemli sürümle
    // birlikte geldiğinde o da listede görünmeli.
    final karisik = [
      _not('1.3.1', onemli: false),
      _not('1.3.0', onemli: true),
      _not('1.2.0'),
    ];
    final c = yeniNotlar(
        notlar: karisik, calisanSurum: '1.3.1', sonGorulen: '1.2.0');
    expect(c.map((n) => n.surum).toList(), ['1.3.1', '1.3.0']);
  });

  test('sonGorulen listede YOKSA tüm geçmiş dökülmez — yalnızca çalışan', () {
    // Downgrade ya da bozuk kayıt: naif "son görülene kadar topla" döngüsü
    // burada tüm listeyi döndürürdü.
    final c = yeniNotlar(
        notlar: notlar, calisanSurum: '1.2.0', sonGorulen: '0.9.0');
    expect(c.map((n) => n.surum).toList(), ['1.2.0']);
  });

  test('sonGorulen listede yok VE çalışan önemli değilse sessiz', () {
    final n = [_not('1.2.0', onemli: false), _not('1.1.0')];
    expect(
      yeniNotlar(notlar: n, calisanSurum: '1.2.0', sonGorulen: '0.9.0'),
      isEmpty,
    );
  });

  group('gerçek sürüm notları', () {
    test('liste boş değil ve en yeni önce sıralı', () {
      expect(surumNotlari, isNotEmpty);
      for (var i = 0; i < surumNotlari.length - 1; i++) {
        expect(
          _karsilastir(surumNotlari[i].surum, surumNotlari[i + 1].surum),
          greaterThan(0),
          reason: '${surumNotlari[i].surum} '
              '${surumNotlari[i + 1].surum} üstünde olmalı',
        );
      }
    });

    test('her sürümün en az bir yeniliği ve dolu alanları var', () {
      for (final n in surumNotlari) {
        expect(n.yenilikler, isNotEmpty, reason: '${n.surum} boş');
        expect(n.tarih.trim(), isNotEmpty);
        for (final y in n.yenilikler) {
          expect(y.baslik.trim(), isNotEmpty);
          expect(y.aciklama.trim(), isNotEmpty);
        }
      }
    });

    test('sürüm numaraları x.y.z biçiminde — build numarası TAŞIMAZ', () {
      // '1.2.0+7' yazılırsa PackageInfo.version ile eşleşmez ve not hiç
      // gösterilmez (sessiz arıza).
      final bicim = RegExp(r'^\d+\.\d+\.\d+$');
      for (final n in surumNotlari) {
        expect(bicim.hasMatch(n.surum), isTrue,
            reason: '${n.surum} geçersiz — build numarası eklemeyin');
      }
    });
  });
}

/// '1.10.0' > '1.9.0' — string karşılaştırma bunu yanlış yapar.
int _karsilastir(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}
