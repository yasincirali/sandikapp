
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/screens/portfolio_performance_screen.dart';
import 'package:portfoy_takip/services/period_summary_service.dart' show SummaryPeriod;
import 'helpers/kaynak.dart';

/// Aylık dönemler TAKVİMDEN hesaplanır — sabit gün sayısıyla değil.
///
/// ## Kullanıcı isteği (2026-09-12)
/// "1 ay 6 ay göstergeleri için gün sayısı ile değil de, 1 aylık grafik
/// bir önceki ay aynı günden başlamalı, 6 ayda da 6 ay önce aynı günden."
///
/// Eski davranış sabit gün sayısıydı (30/180/365). Ayların uzunluğu
/// değiştiği için pencere kullanıcının kurduğu cümleyle uyuşmuyordu:
/// 31 günlük aylarda bir gün eksik, Şubat'ta iki-üç gün fazla.
///
/// ## Ölçülen tuzak — ay sonu TAŞMASI
/// 31 Mart'tan bir ay geri 31 Şubat olmaz. `DateTime(2026, 2, 31)` Dart'ta
/// hata vermez, sessizce **3 Mart'a taşar** — yani İLERİ bir tarihe.
/// Dönem başı bitişten sonraya düşerdi ve grafik boş kalırdı. Hedef ayın
/// gün sayısına kırpma tam bunun için.
void main() {
  DateTime d(int y, int m, int g) => DateTime(y, m, g);

  group('normal aylar — aynı gün', () {
    test('1 ay geri', () {
      expect(
        PortfolioPerformanceScreen.donemBaslangici(d(2026, 9, 12), 1),
        d(2026, 8, 12),
      );
    });

    test('6 ay geri', () {
      expect(
        PortfolioPerformanceScreen.donemBaslangici(d(2026, 9, 12), 6),
        d(2026, 3, 12),
      );
    });

    test('12 ay geri — yıl değişir', () {
      expect(
        PortfolioPerformanceScreen.donemBaslangici(d(2026, 9, 12), 12),
        d(2025, 9, 12),
      );
    });

    test('yıl sınırını geçen 6 ay', () {
      expect(
        PortfolioPerformanceScreen.donemBaslangici(d(2026, 2, 15), 6),
        d(2025, 8, 15),
      );
    });
  });

  group('ay sonu — TAŞMA yok', () {
    test('31 Mart → 1 ay geri = 28 Şubat (2026 artık yıl değil)', () {
      final r = PortfolioPerformanceScreen.donemBaslangici(d(2026, 3, 31), 1);
      expect(r.month, 2);
      expect(r.day, 28, reason: '31 Şubat\'a taşmış olmalı değil.');
    });

    test('29 Mart → 1 ay geri = 28 Şubat', () {
      final r = PortfolioPerformanceScreen.donemBaslangici(d(2026, 3, 29), 1);
      expect(r, d(2026, 2, 28));
    });

    test('31 Mayıs → 1 ay geri = 30 Nisan', () {
      expect(
        PortfolioPerformanceScreen.donemBaslangici(d(2026, 5, 31), 1),
        d(2026, 4, 30),
      );
    });

    test('31 Ağustos → 6 ay geri = 28 Şubat', () {
      final r = PortfolioPerformanceScreen.donemBaslangici(d(2026, 8, 31), 6);
      expect(r.month, 2);
      expect(r.day, 28);
    });

    test('artık yıl: 29 Şubat korunur', () {
      // 2028 artık yıl. 29 Mart 2028 → 1 ay geri = 29 Şubat 2028.
      final r = PortfolioPerformanceScreen.donemBaslangici(d(2028, 3, 29), 1);
      expect(r, d(2028, 2, 29));
    });
  });

  test('sonuç HER ZAMAN bitişten önce', () {
    // Asıl değişmez: dönem başı bitişten sonraya düşerse pencere ters
    // döner ve grafik boşalır. Kaba tarama — her ayın her günü.
    for (var ay = 1; ay <= 12; ay++) {
      for (final gun in [1, 15, 28, 29, 30, 31]) {
        final sonGun = DateTime(2026, ay + 1, 0).day;
        if (gun > sonGun) continue;
        final bitis = DateTime(2026, ay, gun);
        for (final geri in [1, 6, 12]) {
          final bas = PortfolioPerformanceScreen.donemBaslangici(bitis, geri);
          expect(bas.isBefore(bitis), isTrue,
              reason: '$bitis − $geri ay → $bas (bitişten sonra!)');
        }
      }
    }
  });

  group('ekran bağlantısı', () {
    final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll('\r\n', '\n');

    test('1A/3A/6A/1Y/5Y takvim kullanır, 1H gün sayısı', () {
      // 2026-09-28: `_periods` tek dönem kümesinden ([SummaryPeriod])
      // türetiliyor; ayGeri enum'da, ekran onu aynen taşıyor.
      expect(
          kaynak.contains('for (final p in SummaryPeriod.values)') &&
              kaynak.contains('ayGeri: p.ayGeri'),
          isTrue,
          reason: 'Performans dönemleri tek kümeden türetilmiyor.');
      expect(SummaryPeriod.birAy.ayGeri, 1);
      expect(SummaryPeriod.ucAy.ayGeri, 3);
      expect(SummaryPeriod.altiAy.ayGeri, 6);
      expect(SummaryPeriod.birYil.ayGeri, 12);
      expect(SummaryPeriod.besYil.ayGeri, 60);
      // Haftalık takvim ayı DEĞİL: "1 hafta" zaten tam 7 gündür.
      expect(SummaryPeriod.birHafta.ayGeri, isNull);
      expect(SummaryPeriod.birHafta.days, 7);
    });

    test('startDate takvim dalını KULLANIR', () {
      // Satır kırılmasına dayanıklı: boşlukları tek boşluğa indir.
      //
      // Parantezden SONRAKİ boşluk da esnek olmalı. Önce
      // `donemBaslangici( endDate` literali aranıyordu — yani `dart format`
      // çağrıyı tek satıra topladığı anda (dosya büyüyüp sarma noktası
      // kaydığında olur) test, mantık hiç değişmemiş olmasına rağmen
      // kırılıyordu. Kovalanan şey çağrının VARLIĞI; biçimi değil.
      final tek = kaynak.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        tek.contains(
            'PortfolioPerformanceScreen.donemBaslangici(endDate, donem.ayGeri!)') ||
            tek.contains(
                'PortfolioPerformanceScreen.donemBaslangici( endDate, donem.ayGeri!)'),
        isTrue,
        reason: 'Hesap bağlanmamış — hâlâ sabit gün sayısı.',
      );
    });
  });

  test('dönem başı için dikey KESİKLİ çizgi YOK', () {
    // Kullanıcı isteği: "başlangıcın dikine kesikli çizgilerle
    // gösterilmesini istemiyorum, tüm grafikler aynı deneyimi sunmalı."
    final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll('\r\n', '\n');

    expect(kaynak.contains('x: primarySeg.spots.first.x'), isFalse,
        reason: 'Başlangıç dikey işareti geri gelmiş.');
    // "ŞİMDİ" çizgisi KALIR — son noktanın yerini gösterir. 2026-09-28'den
    // beri ortak grafik stilinden gelir (`GrafikStili.simdiCizgisi`).
    expect(kaynak.contains('GrafikStili.simdiCizgisi('), isTrue,
        reason: 'Son nokta işareti de silinmiş; istenen bu değildi.');
    // Aynı kural artık üç grafikte: hiçbiri dönem başına DİKEY işaret
    // koymaz; dönem başı yatay çizginin etiketinde (tarih + değer).
    for (final yol in [
      'lib/screens/asset_detail_screen.dart',
      'lib/widgets/fiyat_grafigi.dart',
    ]) {
      final k = ekranKaynagiSync(yol);
      expect(k.contains('x: anchorSpot.x') || k.contains('x: tam.first.x'),
          isFalse,
          reason: '$yol: dönem başı dikey işareti geri gelmiş.');
    }
  });
}
