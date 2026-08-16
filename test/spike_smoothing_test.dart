import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Tek noktalık "V" artefaktlarının temizlenmesi.
///
/// Yahoo bazı sembollerde tek bir slotu eksik/geç döndürüyor; o slotta
/// pozisyon eksik hesaplanıyor ve seri aşağı inip hemen geri çıkıyor.
/// Gerçek bir fiyat hareketi değil, veri artefaktı.
///
/// **Neden hem günlük hem gün içi seride:** günlük seri bunu baştan beri
/// temizliyordu, gün içi seri temizlemiyordu. Artefakt ana ekran
/// widget'ının grafiğinde dikey bir sıçrama olarak görünüyordu —
/// uygulamanın GÜNLÜK sekmesinde görünmeyen bir sıçrama. İki seri aynı
/// kuralı kullanmalı, yalnızca eşikleri ölçeklerine göre farklı.
void main() {
  group('V-dip artefaktı', () {
    test('tek noktalık çukur komşuların ortalamasına çekilir', () {
      // Gerçek vaka: gün içi seri düz giderken tek slot dibe iniyor.
      final points = {
        1: 2486000.0,
        2: 2486000.0,
        3: 2470000.0, // artefakt — komşulardan ~%0,6 sapma
        4: 2486100.0,
        5: 2486200.0,
      };

      smoothSpikes(points, deviation: 0.003, neighborGap: 0.002);

      expect(points[3], closeTo((2486000.0 + 2486100.0) / 2, 0.01),
          reason: 'çukur iki komşusunun ortalamasına çekilmeli');
    });

    test('tek noktalık TEPE de temizlenir', () {
      // Artefakt her iki yöne de olabilir.
      final points = {
        1: 100000.0,
        2: 100000.0,
        3: 101000.0, // yukarı sıçrama
        4: 100050.0,
        5: 100050.0,
      };

      smoothSpikes(points, deviation: 0.003, neighborGap: 0.002);

      expect(points[3], closeTo(100025.0, 0.01));
    });

    test('GERÇEK trend korunur — düzeltme yapılmaz', () {
      // Kritik: komşular birbirinden uzaksa ortadaki nokta meşrudur.
      // Aksi halde düzeltme gerçek fiyat hareketini siler ve grafiği
      // yalan söyletir.
      final points = {
        1: 100000.0,
        2: 102000.0,
        3: 104000.0, // yükselen trendin ortası
        4: 106000.0,
        5: 108000.0,
      };
      final before = Map<int, double>.from(points);

      smoothSpikes(points, deviation: 0.003, neighborGap: 0.002);

      expect(points, before, reason: 'trend içindeki nokta düzeltilemez');
    });

    test('uçlara DOKUNULMAZ', () {
      // İlk ve son noktanın komşusu yok; artefakt olup olmadığı bilinemez.
      // Son nokta zaten canlı toplama sabitleniyor.
      final points = {1: 50000.0, 2: 100000.0, 3: 100000.0, 4: 50000.0};

      smoothSpikes(points, deviation: 0.003, neighborGap: 0.002);

      expect(points[1], 50000.0);
      expect(points[4], 50000.0);
    });

    test('küçük dalgalanma düzeltilmez', () {
      // Eşik altındaki gürültü gerçek gün içi harekettir; düzeltmek
      // grafiği yapay biçimde düzleştirirdi.
      final points = {
        1: 100000.0,
        2: 100000.0,
        3: 100100.0, // %0,1 — eşiğin (%0,3) altında
        4: 100000.0,
        5: 100000.0,
      };
      final before = Map<int, double>.from(points);

      smoothSpikes(points, deviation: 0.003, neighborGap: 0.002);

      expect(points, before);
    });

    test('günlük seri eşikleri daha gevşektir', () {
      // Günlük seride %0,5'lik bir sapma normaldir ve düzeltilmemeli;
      // aynı sapma 5 dakikalık bir slotta artefakt sayılır.
      final points = {
        1: 100000.0,
        2: 100000.0,
        3: 100500.0, // %0,5
        4: 100000.0,
        5: 100000.0,
      };
      final before = Map<int, double>.from(points);

      smoothSpikes(points, deviation: 0.015, neighborGap: 0.01);

      expect(points, before, reason: 'günlük ölçekte %0,5 gerçek harekettir');
    });

    test('sıfır/negatif komşular atlanır', () {
      // Borsa açılmadan önceki boş slotlar sıfırdır; onlara göre sapma
      // hesaplamak sıfıra bölme ve saçma sonuç üretirdi.
      final points = {1: 0.0, 2: 100000.0, 3: 0.0, 4: 100000.0};

      expect(
        () => smoothSpikes(points, deviation: 0.003, neighborGap: 0.002),
        returnsNormally,
      );
    });
  });
}
