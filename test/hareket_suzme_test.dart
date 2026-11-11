import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';

/// Hareketler araması: süzme tek hesap (2026-11-11).
///
/// Ölçüm, aramaya bekleme eklenip eklenmeyeceğini belirledi (eşik 8 ms).
/// 2026-11-11 bulut makinesinde (test VM'i, JIT) medyan ~3,1 ms çıktı:
/// bekleme EKLENMEDİ, yalnız tek hesap (önbellek) geldi. Ölçüm testi süre
/// iddia etmez — makineye göre değişir — yalnız sayıyı yazar.
Asset _lot(int i) => Asset(
      id: 'l$i',
      userId: 'u1',
      name: 'Varlık ${i % 40}',
      ticker: 'V${i % 40}',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      // Yarısı notlu; satışlar alış notuyla karşılaştırıldığı için en
      // pahalı yol (islemNotu → defter.any) da ölçüme girer.
      notes: i.isEven ? 'Ay sonu maaştan ayırdım, kenarda dursun $i' : '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: DateTime(2024, 1, 1).add(Duration(hours: i * 7)),
      kind: i % 3 == 0 ? AssetKind.sell : AssetKind.buy,
    );

void main() {
  final defter = [for (var i = 0; i < 1500; i++) _lot(i)];

  test('ölçüm: 1500 işlemde bir süzme turu (medyan)', () {
    // Not aramasına düşen sorgu: ad/sembolde geçmez, her satırda not okunur.
    for (var i = 0; i < 3; i++) {
      hareketleriSuz(defter, sorgu: 'ikramiye');
    }
    final sureler = <int>[];
    for (var i = 0; i < 9; i++) {
      final sw = Stopwatch()..start();
      hareketleriAyir(hareketleriSuz(defter, sorgu: 'ikramiye'));
      sw.stop();
      sureler.add(sw.elapsedMicroseconds);
    }
    sureler.sort();
    // ignore: avoid_print
    print('hareket süzme medyan: ${sureler[sureler.length ~/ 2] / 1000} ms '
        '(min ${sureler.first / 1000}, max ${sureler.last / 1000})');
  });

  group('HareketSuzmeOnbellegi', () {
    test('aynı girdiyle ikinci okuma yeniden süzmez', () {
      final o = HareketSuzmeOnbellegi();
      final a = o.ayir(defter, sorgu: 'maaş');
      final b = o.ayir(List.of(defter), sorgu: ' MAAŞ ');
      expect(o.hesapSayisi, 1);
      expect(identical(a, b), isTrue);
    });

    test('girdi değişince yeniden süzer', () {
      final o = HareketSuzmeOnbellegi();
      o.ayir(defter, sorgu: 'maaş');
      o.ayir(defter, sorgu: 'maaşt');
      expect(o.hesapSayisi, 2);
      o.ayir(defter, sorgu: 'maaşt', from: DateTime(2024, 6, 1));
      expect(o.hesapSayisi, 3);
      o.ayir(defter, sorgu: 'maaşt', from: DateTime(2024, 6, 1),
          to: DateTime(2024, 9, 1));
      expect(o.hesapSayisi, 4);
      // Defterde bir kayıt yenilendi (ör. not düzenlendi → yeni nesne).
      final yeni = List.of(defter)..[5] = defter[5].copyWithNotes('ikramiye');
      final r = o.ayir(yeni, sorgu: 'maaşt', from: DateTime(2024, 6, 1),
          to: DateTime(2024, 9, 1));
      expect(o.hesapSayisi, 5);
      expect(r.aktif, isNotEmpty);
    });

    test('sonuç süzgeçsiz yolla birebir aynı', () {
      final o = HareketSuzmeOnbellegi();
      final r = o.ayir(defter, sorgu: 'maaş', from: DateTime(2024, 3, 1));
      final beklenen = hareketleriAyir(
          hareketleriSuz(defter, sorgu: 'maaş', from: DateTime(2024, 3, 1)));
      expect(r.aktif.map((a) => a.id), beklenen.aktif.map((a) => a.id));
      expect(r.silinen.map((a) => a.id), beklenen.silinen.map((a) => a.id));
    });
  });
}
