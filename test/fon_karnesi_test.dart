import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/fon_karnesi.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// Fon karnesi (F4) — saf hesap. Kararlar `lib/services/fon_karnesi.dart`
/// başlığında: yarışma sırası, null getiri sıraya girmez, tek fonlu
/// kategoride karne yok, kıyas grubu = tip + kategori.
TefasFund _fon(
  String kod, {
  String? kategori = 'Hisse Senedi Şemsiye Fonu',
  String tip = 'YAT',
  double? ay1,
  double? yil1,
  double? yb,
}) =>
    TefasFund(
      code: kod,
      name: '$kod Fonu',
      price: 0,
      fundType: tip,
      managerName: '',
      return1m: ay1,
      return1y: yil1,
      returnYtd: yb,
      kategori: kategori,
    );

void main() {
  group('sıralama', () {
    final fonlar = [
      _fon('AAA', yil1: 50, ay1: 1, yb: 20),
      _fon('BBB', yil1: 40, ay1: 3, yb: 10),
      _fon('CCC', yil1: 30, ay1: 2, yb: 30),
      _fon('DDD', yil1: 10, ay1: 4, yb: 5),
      // Başka kategori — sayıya ve sıraya girmez.
      _fon('PPP', kategori: 'Para Piyasası Şemsiye Fonu', yil1: 99),
    ];

    test('büyük getiri = 1., kategori sayısı yalnız kendi kategorisi', () {
      final k = fonKarnesi('CCC', fonlar)!;
      expect(k.kategori, 'Hisse Senedi Şemsiye Fonu');
      expect(k.kategoriFonSayisi, 4);
      final y = k.donem(KarneDonemi.yil1)!;
      expect(y.sira, 3);
      expect(y.kiyasSayisi, 4);
      expect(k.donem(KarneDonemi.yilBasi)!.sira, 1);
      expect(k.donem(KarneDonemi.ay1)!.sira, 3);
    });

    test('ortanca (çift sayı → ortadaki ikisinin ortalaması) ve puan farkı',
        () {
      final y = fonKarnesi('CCC', fonlar)!.donem(KarneDonemi.yil1)!;
      expect(y.ortanca, 35); // (30 + 40) / 2
      expect(y.ortancayaFark, -5); // yüzde PUAN, yüzde değil
    });

    test('tek sayıda fon → ortadaki değer', () {
      final l = [
        _fon('A', yil1: 1),
        _fon('B', yil1: 7),
        _fon('C', yil1: 3),
      ];
      expect(fonKarnesi('A', l)!.donem(KarneDonemi.yil1)!.ortanca, 3);
    });

    test('kod büyük/küçük harf ve boşluktan bağımsız', () {
      expect(fonKarnesi(' ccc ', fonlar)?.fonKodu, 'CCC');
    });

    test('özet dönemi 1 yıl; yoksa yılbaşı', () {
      expect(fonKarnesi('AAA', fonlar)!.ozetDonemi.donem, KarneDonemi.yil1);
      final l = [_fon('A', yb: 5), _fon('B', yb: 6)];
      expect(fonKarnesi('A', l)!.ozetDonemi.donem, KarneDonemi.yilBasi);
    });
  });

  test('eşitlik: aynı getiri aynı sırayı paylaşır, sonraki atlanır', () {
    final l = [
      _fon('A', yil1: 20),
      _fon('B', yil1: 20),
      _fon('C', yil1: 10),
    ];
    expect(fonKarnesi('A', l)!.donem(KarneDonemi.yil1)!.sira, 1);
    expect(fonKarnesi('B', l)!.donem(KarneDonemi.yil1)!.sira, 1);
    expect(fonKarnesi('C', l)!.donem(KarneDonemi.yil1)!.sira, 3);
  });

  group('null getiri', () {
    test('getirisi bilinmeyen fon o dönemin sırasına ve sayısına girmez', () {
      final l = [
        _fon('A', yil1: 30, ay1: 1),
        _fon('YENI', yil1: null, ay1: 5), // 1 yıllık geçmişi yok
        _fon('C', yil1: 10, ay1: 2),
      ];
      final k = fonKarnesi('C', l)!;
      expect(k.kategoriFonSayisi, 3);
      expect(k.donem(KarneDonemi.yil1)!.kiyasSayisi, 2);
      expect(k.donem(KarneDonemi.yil1)!.sira, 2);
      expect(k.donem(KarneDonemi.ay1)!.kiyasSayisi, 3);
    });

    test('fonun kendi getirisi yoksa o dönem karnede yok', () {
      final l = [
        _fon('YENI', yil1: null, ay1: 5),
        _fon('B', yil1: 10, ay1: 2),
      ];
      final k = fonKarnesi('YENI', l)!;
      expect(k.donem(KarneDonemi.yil1), isNull);
      expect(k.donem(KarneDonemi.ay1)!.sira, 1);
    });

    test('hiçbir dönem kurulamıyorsa null', () {
      final l = [_fon('A'), _fon('B', yil1: 3)];
      expect(fonKarnesi('A', l), isNull);
    });

    test('NaN getiri bilinmeyen sayılır', () {
      final l = [_fon('A', yil1: double.nan), _fon('B', yil1: 3)];
      expect(fonKarnesi('A', l), isNull);
    });
  });

  group('uydurma yok → null', () {
    test('tek fonlu kategori', () {
      final l = [
        _fon('TEK', kategori: 'Altın Şemsiye Fonu', yil1: 40),
        _fon('B', yil1: 3),
      ];
      expect(fonKarnesi('TEK', l), isNull);
    });

    test('kategori bilinmiyor (eski önbellek kaydı)', () {
      final l = [_fon('A', kategori: null, yil1: 5), _fon('B', yil1: 3)];
      expect(fonKarnesi('A', l), isNull);
    });

    test('fon katalogda yok / katalog boş', () {
      expect(
          fonKarnesi('YOK', [_fon('A', yil1: 1), _fon('B', yil1: 2)]), isNull);
      expect(fonKarnesi('A', const []), isNull);
      expect(fonKarnesi('', [_fon('A', yil1: 1)]), isNull);
    });

    test(
        'kıyas grubu fon tipine de bağlı: emeklilik fonu yatırım fonuyla '
        'yarışmaz', () {
      final l = [
        _fon('EMK1', tip: 'EMK', yil1: 10),
        _fon('YAT1', tip: 'YAT', yil1: 20),
      ];
      expect(fonKarnesi('EMK1', l), isNull);
    });
  });

  group('fonKoduOf', () {
    test('önekli ve öneksiz kod aynı koda iner', () {
      expect(fonKoduOf(tur: AssetType.fon, ticker: 'TEFAS:ijc'), 'IJC');
      expect(fonKoduOf(tur: AssetType.fon, ticker: ' DLY '), 'DLY');
    });
    test('fon değilse ya da kod boşsa null', () {
      expect(fonKoduOf(tur: AssetType.hisse, ticker: 'THYAO.IS'), isNull);
      expect(fonKoduOf(tur: AssetType.fon, ticker: 'TEFAS:'), isNull);
      expect(fonKoduOf(tur: AssetType.fon, ticker: ''), isNull);
    });
  });
}
