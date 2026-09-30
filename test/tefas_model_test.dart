import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// 2026-09 denetimi §7: `tefas_service` sıfır testliydi. TEFAS modeli disk
/// önbelleğinden okunur — sessizce yanlış olabilecek bir yer. (Aynı dosyadaki
/// DepositService testleri, vadeli mevduat 2026-09-14'te kaldırılınca gitti.)
void main() {
  group('TefasFund JSON', () {
    test('toJson → fromJson round-trip, eksik alanlar toleranslı', () {
      const f = TefasFund(
        code: 'TCD',
        name: 'Test Fonu',
        price: 12.345,
        fundType: 'EMK',
        managerName: 'X Portföy',
        return1m: 1.5,
        riskLevel: 4,
      );
      final back = TefasFund.fromJson(f.toJson())!;
      expect(back.code, 'TCD');
      expect(back.price, 12.345);
      expect(back.return1m, 1.5);
      expect(back.return1y, isNull);
      expect(back.riskLevel, 4);
      expect(TefasFund.fromJson({'n': 'kodsuz'}), isNull);
      expect(TefasFund.fromJson({'c': 'A', 'n': 'B'})!.fundType, 'YAT');
    });

    // F4 fon karnesi (2026-09-29): kategori katalog kaydına eklendi.
    test('kategori round-trip; v1 kaydında (anahtar yok) null', () {
      const f = TefasFund(
        code: 'AFA',
        name: 'A Fonu',
        price: 0,
        fundType: 'YAT',
        managerName: '',
        kategori: 'Hisse Senedi Şemsiye Fonu',
      );
      expect(TefasFund.fromJson(f.toJson())!.kategori,
          'Hisse Senedi Şemsiye Fonu');
      // v1 dosyasındaki kayıt biçimi: `k` yok.
      final v1 = TefasFund.fromJson(
          {'c': 'AFA', 'n': 'A Fonu', 'p': 0, 't': 'YAT', 'm': '', 'rl': 5})!;
      expect(v1.kategori, isNull);
      expect(v1.riskLevel, 5);
      expect(TefasFund.fromJson({'c': 'A', 'n': 'B', 'k': '  '})!.kategori,
          isNull);
    });

    test('risk değeri JSON\'da ondalıklı gelse de okunur', () {
      expect(TefasFund.fromJson({'c': 'A', 'n': 'B', 'rl': 3.0})!.riskLevel,
          3);
    });
  });
}
