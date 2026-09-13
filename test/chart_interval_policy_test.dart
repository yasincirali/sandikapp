import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/chart_interval_policy.dart';

/// Uygulamada fiilen kullanılan dönemler (`_periods`, portfolio_performance).
/// GÜNLÜK `days: 0` taşır — takvim günü, kayan pencere değil.
const _donemler = [0, 7, 30, 180, 365];

void main() {
  group('gecerliBarlar', () {
    test('hiçbir dönem boş liste döndürmez', () {
      for (final d in _donemler) {
        expect(ChartIntervalPolicy.gecerliBarlar(d), isNotEmpty,
            reason: '$d günlük dönemde hiç bar yok — grafik çizilemez');
      }
    });

    test('listeler ince → kaba sıralı', () {
      for (final d in _donemler) {
        final barlar = ChartIntervalPolicy.gecerliBarlar(d);
        for (var i = 1; i < barlar.length; i++) {
          expect(barlar[i].barSuresi, greaterThan(barlar[i - 1].barSuresi),
              reason: '$d günlük dönemde sıralama bozuk');
        }
      }
    });

    test('GÜNLÜK yalnızca dakikalık barlar sunar', () {
      // 1sa BIST seansında (~8 saat) 8 nokta üretir: çizgi değil merdiven.
      expect(ChartIntervalPolicy.gecerliBarlar(0), const [
        ResolutionTier.oneMin,
        ResolutionTier.fiveMin,
        ResolutionTier.fifteenMin,
      ]);
    });

    test('1dk YALNIZCA GÜNLÜK dönemde sunulur — Yahoo 8 gün duvarı', () {
      for (final d in _donemler.where((d) => d > 0)) {
        expect(ChartIntervalPolicy.gecerliBarlar(d),
            isNot(contains(ResolutionTier.oneMin)),
            reason: '$d gün: 1dk 8 günlük duvarı aşar');
      }
    });

    test('3A+ dönemlerde intraday bar sunulmaz — Yahoo reddediyor', () {
      // `5m`/`15m` + `3mo` → Unprocessable Entity (ölçüldü 2026-09-13).
      const intraday = {
        ResolutionTier.oneMin,
        ResolutionTier.fiveMin,
        ResolutionTier.fifteenMin,
        ResolutionTier.hourly,
      };
      for (final d in [90, 180, 365, 1000]) {
        final barlar = ChartIntervalPolicy.gecerliBarlar(d);
        expect(barlar.where(intraday.contains), isEmpty,
            reason: '$d gün: intraday veri fiziksel olarak yok');
      }
    });
  });

  group('varsayilanBar', () {
    test('her dönemde KENDİ geçerli listesinde bulunur', () {
      // İki merdiven (gecerliBarlar + varsayilanBar) ayrışırsa, seçici
      // listede olmayan bir barı seçili gösterirdi.
      for (final d in [...(_donemler), 1, 5, 14, 60, 90, 200, 500]) {
        final v = ChartIntervalPolicy.varsayilanBar(d);
        expect(ChartIntervalPolicy.gecerliBarlar(d), contains(v),
            reason: '$d gün: varsayılan $v geçerli listede yok');
      }
    });
  });

  group('uyarla', () {
    test('geçerli seçim KORUNUR — kullanıcı tercihi ezilmez', () {
      // 1H'de 15dk seçen kullanıcı 1A'ya geçince 15dk'da kalmalı.
      expect(ChartIntervalPolicy.uyarla(ResolutionTier.fifteenMin, 30),
          ResolutionTier.fifteenMin);
      expect(ChartIntervalPolicy.uyarla(ResolutionTier.daily, 365),
          ResolutionTier.daily);
    });

    test('geçersiz seçim en yakın geçerliye düşer', () {
      // 1A'da 15dk → 6A'ya geçiş: intraday yok, günlüğe düşmeli.
      expect(ChartIntervalPolicy.uyarla(ResolutionTier.fifteenMin, 180),
          ResolutionTier.daily);
      // GÜNLÜK'e haftalık bar ile gelinirse en kabaya (15dk) düşer.
      expect(ChartIntervalPolicy.uyarla(ResolutionTier.weekly, 0),
          ResolutionTier.fifteenMin);
    });

    test('DEĞİŞMEZ: sonuç her zaman o dönemde geçerlidir', () {
      for (final d in [...(_donemler), 1, 5, 14, 60, 90, 200, 500]) {
        for (final t in ResolutionTier.values) {
          final sonuc = ChartIntervalPolicy.uyarla(t, d);
          expect(ChartIntervalPolicy.gecerliBarlar(d), contains(sonuc),
              reason: '$d gün + $t → $sonuc geçerli listede yok');
        }
      }
    });

    test('idempotent — uyarlanmış değer yeniden uyarlanınca değişmez', () {
      for (final d in _donemler) {
        for (final t in ResolutionTier.values) {
          final bir = ChartIntervalPolicy.uyarla(t, d);
          expect(ChartIntervalPolicy.uyarla(bir, d), bir);
        }
      }
    });
  });

  group('degisimAciklamasi', () {
    test('seçim korunduysa mesaj YOK', () {
      expect(
          ChartIntervalPolicy.degisimAciklamasi(
              ResolutionTier.daily, ResolutionTier.daily),
          isNull);
    });

    test('düşüş olduysa her iki etiketi de içerir', () {
      final m = ChartIntervalPolicy.degisimAciklamasi(
          ResolutionTier.fifteenMin, ResolutionTier.daily);
      expect(m, isNotNull);
      expect(m, contains('15dk'));
      expect(m, contains('1G'));
    });
  });

  group('ResolutionTier meta', () {
    test('barSuresi enum sırasıyla artar', () {
      const v = ResolutionTier.values;
      for (var i = 1; i < v.length; i++) {
        expect(v[i].barSuresi, greaterThan(v[i - 1].barSuresi),
            reason: '${v[i]} sırası bozuk — uyarla() mesafe hesabı bozulur');
      }
    });

    test('normalizeTs idempotent — bucket sınırına oturur', () {
      final ts = DateTime(2026, 9, 14, 13, 47, 23).millisecondsSinceEpoch;
      for (final t in ResolutionTier.values) {
        final bir = t.normalizeTs(ts);
        expect(t.normalizeTs(bir), bir, reason: '$t idempotent değil');
      }
    });

    test('normalizeTs dakikalık tier\'larda doğru bucket\'a snap eder', () {
      final ts = DateTime(2026, 9, 14, 13, 47).millisecondsSinceEpoch;
      expect(DateTime.fromMillisecondsSinceEpoch(
              ResolutionTier.oneMin.normalizeTs(ts)).minute, 47);
      expect(DateTime.fromMillisecondsSinceEpoch(
              ResolutionTier.fiveMin.normalizeTs(ts)).minute, 45);
      expect(DateTime.fromMillisecondsSinceEpoch(
              ResolutionTier.fifteenMin.normalizeTs(ts)).minute, 45);
    });

    test('her tier benzersiz etiket taşır — seçicide ikizlenmesin', () {
      final etiketler = ResolutionTier.values.map((t) => t.etiket).toList();
      expect(etiketler.toSet().length, etiketler.length);
    });
  });
}
