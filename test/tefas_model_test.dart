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
  });
}
