import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Portföy sıfırlandığında grafik DÜŞÜŞÜ ÇİZER (2026-09-16).
///
/// ## Ölçülen arıza
/// Kullanıcı: "grafiklerde varlığımın 0'a indiğini görmüyorum."
///
/// Tamamı satılan bir portföyde çizgi son değerde asılı kalıyordu. Üç ayrı
/// yerde aynı hata vardı ve üçü birden düzeltildi:
///
///   1. Uzun dönem serisi: `anyCovered` yalnızca `qty != 0` olan varlık
///      bulunca true oluyordu. Hepsi satılmışsa slot seriye HİÇ girmiyordu
///      — ölçüldü: seri 14.09'da ₺330.804'te bitmiş, satışın yapıldığı
///      16.09 slotu yok.
///   2. Gün içi serisi: aynı kapı (`if (!anyCovered) continue`).
///   3. Çizim: `if (y <= 0) continue` borsa öncesi boş slotlarla gerçek
///      sıfırları aynı sayıyordu; satış sonrası noktalar çizimden düşüyordu.
///
/// Sıfır bir ÖLÇÜMDÜR, ölçüm yokluğu değil. `DailySummary.isFlat` ve
/// `PeriodSummary.isFlat` aynı ayrımı zaten yapıyor.
void main() {
  String oku(String yol) => File(yol).readAsStringSync();

  group('seri üretimi', () {
    test('uzun dönem: defterde kayıt varsa slot sıfır değerle girer', () {
      final src = oku('lib/services/history_service.dart');
      expect(src.contains('anyCovered || anyLedger'), isTrue,
          reason: 'net miktar sıfırken de slot seriye girmeli');
    });

    test('gün içi: aynı kapı', () {
      final src = oku('lib/services/history_service.dart');
      expect(src.contains('if (!anyCovered && !anyLedger) continue;'), isTrue);
    });

    test('silinmiş ve miktar-nötr satırlar anyLedger SAYMAZ', () {
      // Silinen "hiç olmamış" sayılır; temettü/mezar taşı miktar taşımaz.
      // İkisi de tek başına bir slotu ayakta tutmamalı.
      final src = oku('lib/services/history_service.dart');
      expect(src.contains('!a.isDeleted &&'), isTrue);
      expect(src.contains('!a.isQuantityNeutral &&'), isTrue);
    });
  });

  group('çizim', () {
    test('BAŞTAKİ sıfırlar atlanır, sonrakiler çizilir', () {
      final src = oku('lib/screens/portfolio_performance/seriler.dart');
      expect(src.contains('ilkDegerGoruldu'), isTrue,
          reason: 'veri yokluğu ile gerçek sıfır ayrılmalı');
      // Koşulsuz eleme geri gelmemeli. Yorum satırları çıkarılır —
      // gerekçe metninde kalıbın kendisi geçiyor.
      final kod = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(kod.contains('if (y <= 0) continue;'), isFalse,
          reason: 'satış sonrası noktalar çizimden düşerdi');
    });
  });
}
