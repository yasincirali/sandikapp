import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/deposit_service.dart';
import 'package:portfoy_takip/services/tefas_service.dart';

/// 2026-09 denetimi §7: `deposit_service` ve `tefas_service` sıfır testliydi.
/// Mevduat matematiği kullanıcının parasını gösterir; TEFAS modeli disk
/// önbelleğinden okunur — ikisi de sessizce yanlış olabilecek yerler.
void main() {
  Asset mevduat(String sub) => Asset(
        id: 'd1',
        userId: 'u',
        name: 'Mevduat',
        ticker: '',
        type: AssetType.mevduat,
        quantity: 100000,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        currentPrice: 1,
        addedDate: DateTime(2026, 1, 1),
        subCategory: sub,
      );

  group('DepositService', () {
    final start = DateTime(2026, 1, 1);
    final end = DateTime(2026, 12, 31);

    test('encode → decode round-trip', () {
      final sub = DepositService.encode(
        start: start,
        end: end,
        annualRatePct: 45,
        interestType: DepositInterestType.compound,
        taxRatePct: 17.5,
      );
      final t = DepositService.decode(mevduat(sub))!;
      expect(t.start, start);
      expect(t.end, end);
      expect(t.annualRatePct, 45);
      expect(t.interestType, DepositInterestType.compound);
      expect(t.taxRatePct, 17.5);
      expect(t.taxWasProvided, isTrue);
    });

    test('stopaj verilmemişse varsayılan ve bayrak false', () {
      final t = DepositService.decode(mevduat('mevduat|s=1|e=2|r=40'))!;
      expect(t.taxRatePct, DepositService.defaultTaxRate);
      expect(t.taxWasProvided, isFalse);
    });

    test('bozuk / mevduat olmayan kayıt null', () {
      expect(DepositService.decode(mevduat('mevduat|s=x')), isNull);
      expect(DepositService.decode(mevduat('hisse')), isNull);
    });

    test('basit faiz: 365 gün %40 → brüt 1,40; %15 stopajla net 1,34', () {
      final t = DepositTerms(
        start: start,
        end: start.add(const Duration(days: 365)),
        annualRatePct: 40,
        interestType: DepositInterestType.simple,
        taxRatePct: 15,
        taxWasProvided: true,
      );
      expect(DepositService.maturityUnitValue(t), closeTo(1.34, 1e-9));
      // Yarı vadede yarısı.
      expect(
        DepositService.currentUnitValue(t,
            now: start.add(const Duration(days: 182, hours: 12))),
        closeTo(1.0 + 0.40 * (182 / 365) * 0.85, 1e-9),
      );
    });

    test('bileşik faiz basitten büyük; vade sonrası sabit; başlangıçta 1,0', () {
      final simple = DepositTerms(
        start: start,
        end: end,
        annualRatePct: 40,
        interestType: DepositInterestType.simple,
        taxRatePct: 0,
        taxWasProvided: true,
      );
      final compound = DepositTerms(
        start: start,
        end: end,
        annualRatePct: 40,
        interestType: DepositInterestType.compound,
        taxRatePct: 0,
        taxWasProvided: true,
      );
      expect(DepositService.maturityUnitValue(compound),
          greaterThan(DepositService.maturityUnitValue(simple)));
      expect(DepositService.currentUnitValue(simple, now: start), 1.0);
      expect(
        DepositService.currentUnitValue(simple,
            now: end.add(const Duration(days: 100))),
        DepositService.maturityUnitValue(simple),
      );
      expect(DepositService.isMatured(simple, now: end), isTrue);
      expect(DepositService.daysToMaturity(simple, now: start), 364);
    });
  });

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
