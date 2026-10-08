import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/bes_hesabi.dart';
import 'package:portfoy_takip/services/sozlesme_deposu.dart';

/// Mevduat/BES emülatör testi bulguları (2026-10-01) — kalan maddelerin
/// saf hesapları. Varlık sayfası sınaması `mevduat_varlik_sayfasi_test`.
void main() {
  group('BES hak ediş: sonraki basamağa kalan süre', () {
    test('15.05.2020 giriş, 2026-10-01: %60 eşiğine 3 yıl 7 ay', () {
      // Eski satır "4 yıl sonra %60" yazıyordu (tam yıl farkı).
      final s = BesHesabi.sonrakiBasamakSuresi(
          DateTime(2020, 5, 15), DateTime(2026, 10, 1))!;
      expect((s.yil, s.ay, s.oran), (3, 7, 60.0));
    });

    test('ay günü geçilmişse o ay sayılmaz (aşağı yuvarlama)', () {
      final s = BesHesabi.sonrakiBasamakSuresi(
          DateTime(2020, 5, 15), DateTime(2026, 10, 20))!;
      expect((s.yil, s.ay), (3, 6));
    });

    test('eşiğe bir aydan az kala 0 yıl 0 ay', () {
      final s = BesHesabi.sonrakiBasamakSuresi(
          DateTime(2020, 5, 15), DateTime(2023, 5, 1))!;
      expect((s.yil, s.ay, s.oran), (0, 0, 15.0));
    });

    test('son basamakta null', () {
      expect(
          BesHesabi.sonrakiBasamakSuresi(
              DateTime(2010, 1, 1), DateTime(2026, 10, 1)),
          isNull);
    });
  });

  group('mevduat dönem yüzdesi sözleşmeden', () {
    const id = '587b6d74-64b8-4c46-bbee-5946db29cf4f';
    final sym = mevduatSembolu(id);
    final s = Sozlesme(
      id: id,
      userId: 'u1',
      tur: SozlesmeTuru.mevduat,
      kurum: 'Enpara',
      baslangic: DateTime(2025, 3, 1),
    );
    // %48 brüt, %12 stopaj, 365 gün → net %42,24; vade 2026-03-01.
    final d = MevduatDonemi(
      id: 'd1',
      sozlesmeId: id,
      baslangic: DateTime(2025, 3, 1),
      vadeSonu: DateTime(2026, 3, 1),
      yillikFaiz: 48,
      stopaj: 12,
    );
    setUp(() => SozlesmeDeposu.instance.yaz([s], [d]));
    tearDown(SozlesmeDeposu.instance.temizle);

    test('pencere sözleşmeden uzunsa pozisyonun ömrünün getirisi', () {
      // Seri haftalık örneklendiği için 5Y eskiden ilk noktayı açılıştan
      // günler sonra alıyor ve pozisyondan ~0,8 puan düşük yazıyordu.
      final p = SozlesmeDeposu.instance.mevduatDegisimi(
          sym, DateTime(2021, 10, 1), DateTime(2026, 10, 1))!;
      expect(p, closeTo(42.24, 1e-9));
    });

    test('vade dolduktan sonraki pencere düz: %0', () {
      final p = SozlesmeDeposu.instance.mevduatDegisimi(
          sym, DateTime(2026, 9, 1), DateTime(2026, 10, 1))!;
      expect(p, closeTo(0, 1e-12));
    });

    test('bugün açılan günlük faizli hesap: gün içi düz, gün sonunda faiz', () {
      const id2 = 'aaaaaaaa-0000-0000-0000-000000000001';
      final bugun = DateTime(2026, 10, 1);
      SozlesmeDeposu.instance.yaz([
        Sozlesme(
            id: id2,
            userId: 'u1',
            tur: SozlesmeTuru.mevduat,
            kurum: 'X',
            baslangic: bugun),
      ], [
        MevduatDonemi(
            id: 'd2',
            sozlesmeId: id2,
            baslangic: bugun,
            vadeSonu: null,
            yillikFaiz: 40,
            stopaj: 17.5),
      ]);
      final sym2 = mevduatSembolu(id2);
      // Günlük faizli hesapta faiz gün sonunda eklenir (2026-10-02): açılış
      // günü içinde değişim sıfır, gece yarısından sonra bir günlük net.
      final gunIci = SozlesmeDeposu.instance.mevduatDegisimi(
          sym2, bugun, bugun.add(const Duration(hours: 19)))!;
      expect(gunIci, closeTo(0, 1e-12));
      // Eskiden gün içi seri tek noktadan kaldığı için ertesi gün de %0,00
      // yazıyordu; yüzde sözleşmeden ölçülür.
      final ertesi = SozlesmeDeposu.instance.mevduatDegisimi(
          sym2, bugun, bugun.add(const Duration(hours: 25)))!;
      expect(ertesi, closeTo(40 * 0.825 / 365, 1e-9));
    });
  });

  group('BES satırının kurumu', () {
    Asset bes(String ad) => Asset(
          id: 'b',
          userId: 'u1',
          name: ad,
          ticker: '${tefasOneki}AEI',
          type: AssetType.bes,
          quantity: 1,
          purchasePrice: 1,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
        );

    test('lot adından kurum okunur', () {
      expect(bes('Anadolu Hayat · AEI · Devlet').besKurumu, 'Anadolu Hayat');
      expect(bes('Anadolu Hayat · AH5').besKurumu, 'Anadolu Hayat');
    });

    test('biçim dışı adda null', () {
      expect(bes('AEI').besKurumu, isNull);
    });
  });
}
