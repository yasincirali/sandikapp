// Fon geçmişi tek istekte (2026-10-23, yasin: AFT/DLY'de 6A·1Y·5Y "%0").
//
// Varlık sayfası yedi dönemi aynı anda ister; fon için bu TEFAS'a 8 POST
// demekti ve sınır aşımında son dönemler boş kalıyordu. Kilit: aynı
// kovadaki dönemler TEK ağ çekimini paylaşır, boş yanıt önbelleğe girmez.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

void main() {
  final tefas = TefasService.instance;

  tearDown(() {
    TefasService.gecmisCekici = TefasService.varsayilanGecmisCekici;
    tefas.gecmisOnbeleginiTemizle();
  });

  test('kova: 3 aya kadar 3, üstü 60', () {
    expect([1, 3, 6, 12, 36, 60].map(tefasGecmisKovasi),
        [3, 3, 60, 60, 60, 60]);
  });

  test('6A, 1Y ve 5Y aynı anda istenince TEFAS\'a tek istek gider', () async {
    final cagrilar = <int>[];
    TefasService.gecmisCekici = (kod, periyod) async {
      cagrilar.add(periyod);
      return [(1, 10.0), (2, 12.0)];
    };
    final sonuc = await Future.wait([
      tefas.fetchHistory('AFT', periyod: 6),
      tefas.fetchHistory('AFT', periyod: 12),
      tefas.fetchHistory('AFT', periyod: 60),
      tefas.fetchHistory('AFT', periyod: 1),
      tefas.fetchHistory('AFT', periyod: 3),
    ]);
    expect(cagrilar..sort(), [3, 60]);
    expect(sonuc.every((s) => s.length == 2), isTrue);
    // Önbellekten: yeni istek yok.
    await tefas.fetchHistory('AFT', periyod: 12);
    expect(cagrilar.length, 2);
  });

  test('boş yanıt önbelleğe girmez, sonraki istek yeniden dener', () async {
    var n = 0;
    TefasService.gecmisCekici = (kod, periyod) async =>
        ++n == 1 ? const [] : [(1, 10.0), (2, 11.0)];
    expect(await tefas.fetchHistory('DLY', periyod: 12), isEmpty);
    expect(await tefas.fetchHistory('DLY', periyod: 12), hasLength(2));
    expect(n, 2);
  });

  test('satırlar: fiyat yoksa birimPayDegeri, sıfır fiyat düşer, sıralı', () {
    final p = tefasGecmisSatirlari('{"resultList":['
        '{"tarih":"2026-10-22T00:00:00","fiyat":"2,5"},'
        '{"tarih":"2026-10-21T00:00:00","birimPayDegeri":1.5},'
        '{"tarih":"2026-10-20T00:00:00","fiyat":0},'
        '{"tarih":"2026-10-23T00:00:00","fiyat":3.25}'
        ']}');
    expect(p.map((e) => e.$2).toList(), [1.5, 3.25]);
  });
}
