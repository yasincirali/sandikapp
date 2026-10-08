import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/eurobond.dart';

void main() {
  final tahvil = EurobondSozlesmesi(
    isin: 'US900123DF45',
    ad: 'Türkiye %6 2030',
    paraBirimi: 'USD',
    kuponOrani: 0.06,
    vade: DateTime.utc(2030, 3, 15),
    ihracTarihi: DateTime.utc(2020, 3, 15),
    ihracci: EurobondIhracci.hazine,
  );

  group('ISIN', () {
    test('kontrol hanesi doğru olanlar geçer', () {
      expect(isinGecerli('US900123DF45'), isTrue); // Türkiye 9,875% 2028
      expect(isinGecerli('US0378331005'), isTrue); // Apple
      expect(isinGecerli('XS0503454166'), isTrue);
    });
    test('tek hane hatası yakalanır', () {
      // Araştırmada örnek verilen hatalı ISIN.
      expect(isinGecerli('US900123DF46'), isFalse);
      expect(isinGecerli('US900123DF4'), isFalse);
      expect(isinGecerli(''), isFalse);
    });
    test('sembol önekiyle gidip gelir', () {
      expect(eurobondSembolu('us900123df45'), 'EUROBOND:US900123DF45');
      expect(eurobondIsin('EUROBOND:us900123df45'), 'US900123DF45');
      expect(eurobondIsin('EUROBOND:US900123DF46'), isNull);
      expect(eurobondIsin('AAPL'), isNull);
    });
  });

  group('kupon takvimi', () {
    test('vadeye hizalı yarı yıllık', () {
      final t = tahvil.kuponTarihleri();
      expect(t.first, DateTime.utc(2020, 9, 15));
      expect(t.last, DateTime.utc(2030, 3, 15));
      expect(t.length, 20);
    });
    test('ay sonu kısalır (31 → 30/28)', () {
      final b = EurobondSozlesmesi(
        isin: 'US900123DF45',
        ad: 'x',
        paraBirimi: 'USD',
        kuponOrani: 0.05,
        vade: DateTime.utc(2027, 8, 31),
        ihracTarihi: DateTime.utc(2025, 8, 31),
        ihracci: EurobondIhracci.hazine,
      );
      expect(b.kuponTarihleri(), [
        DateTime.utc(2026, 2, 28),
        DateTime.utc(2026, 8, 31),
        DateTime.utc(2027, 2, 28),
        DateTime.utc(2027, 8, 31),
      ]);
    });
  });

  group('işlemiş faiz (30/360)', () {
    test('kupon gününde sıfır', () {
      expect(tahvil.islemisFaiz(DateTime.utc(2026, 3, 15)), 0);
    });
    test('dönemin yarısında yarım kupon', () {
      // 15 Mart → 15 Haziran = 90/180 gün; yarım kupon 3 × 0,5 = 1,5 puan.
      expect(tahvil.islemisFaiz(DateTime.utc(2026, 6, 15)), closeTo(1.5, 1e-9));
      expect(tahvil.kirliFiyat(98, DateTime.utc(2026, 6, 15)), closeTo(99.5, 1e-9));
    });
    test('vadeden sonra sıfır', () {
      expect(tahvil.islemisFaiz(DateTime.utc(2031, 1, 1)), 0);
    });
  });

  group('kupon stopajı', () {
    test('Hazine sıfır', () => expect(tahvil.kuponStopajOrani, 0));
    EurobondSozlesmesi kurumsal(int yil) => EurobondSozlesmesi(
          isin: 'XS0503454166',
          ad: 'banka',
          paraBirimi: 'USD',
          kuponOrani: 0.07,
          vade: DateTime.utc(2025 + yil, 1, 1),
          ihracTarihi: DateTime.utc(2025, 1, 1),
          ihracci: EurobondIhracci.ozelSektor,
        );
    test('kurumsal: <1 yıl %7, 1–3 yıl %3, ≥3 yıl %0', () {
      final kisa = EurobondSozlesmesi(
        isin: 'XS0503454166',
        ad: 'banka',
        paraBirimi: 'USD',
        kuponOrani: 0.07,
        vade: DateTime.utc(2025, 9, 1),
        ihracTarihi: DateTime.utc(2025, 1, 1),
        ihracci: EurobondIhracci.ozelSektor,
      );
      expect(kisa.kuponStopajOrani, 0.07);
      expect(kurumsal(2).kuponStopajOrani, 0.03);
      expect(kurumsal(5).kuponStopajOrani, 0);
    });
  });

  group('vadeye getiri', () {
    test('kupon gününde parite fiyatı ≈ kupon oranı', () {
      final y = tahvil.vadeyeGetiri(100, DateTime.utc(2026, 3, 15))!;
      expect(y, closeTo(0.06, 0.002));
    });
    test('iskontolu fiyatta getiri kupondan yüksek', () {
      final y = tahvil.vadeyeGetiri(95, DateTime.utc(2026, 3, 15))!;
      expect(y, greaterThan(0.07));
    });
    test('vadesi geçmişse null', () {
      expect(tahvil.vadeyeGetiri(100, DateTime.utc(2031, 1, 1)), isNull);
    });
  });

  test('kupon tutarı', () {
    expect(tahvil.kuponTutari(10000), 300);
  });
}
