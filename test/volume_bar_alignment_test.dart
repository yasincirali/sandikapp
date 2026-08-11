import 'package:flutter_test/flutter_test.dart';

/// İşlem hacmi (volume) çubuklarının X hizası.
///
/// Hacim paneli ile fiyat grafiği AYNI X uzayını paylaşır (ortak
/// `ChartViewport`). Çubuklar kaydığında panel "timeline ile uyumsuz" görünür.
///
/// İki ayrı hata vardı:
///
///  1. `start` bir DUVAR SAATİ damgasıdır (`DateTime.now().subtract(days)`),
///     yani içinde günün saati vardır. İşlem tarihleri ise gece yarısına
///     normalize ediliyordu. `dayMidnight.difference(start).inMinutes ~/ 1440`
///     ifadesinde fark NEGATİF-KESİRLİ çıkıyor ve `~/` sıfıra doğru kırptığı
///     için çubuk bir gün kayıyor, aynı güne düşen işlem ise `dayIdx < 0`
///     kontrolüne takılıp tamamen eleniyordu.
///
///  2. Gün indeksi gece yarısı tabanındayken grafiğin X'i `start` tabanında —
///     aradaki sabit kayma (`startOffsetDays`) geri eklenmezse tüm çubuklar
///     saatler kadar kayar.
///
/// Ekrandaki private metodu doğrudan çağıramadığımız için hesap burada birebir
/// yeniden üretiliyor; amaç aritmetiği kilitlemek.
void main() {
  /// Fiyat grafiğinin X üretimi (`_convertHistoryToSegments` ile aynı).
  double priceX(DateTime pointTs, DateTime start) =>
      pointTs.difference(start).inMinutes / (60.0 * 24.0);

  // ── Eski (hatalı) hesap ────────────────────────────────────────────────
  double? legacyBarX(DateTime txDay, DateTime start) {
    final dayMidnight = DateTime(txDay.year, txDay.month, txDay.day);
    final dayIdx = dayMidnight.difference(start).inMinutes ~/ (60 * 24);
    if (dayIdx < 0) return null; // elenirdi
    return dayIdx.toDouble() + 0.5;
  }

  // ── Yeni (düzeltilmiş) hesap ───────────────────────────────────────────
  //
  // `+0.5` (gün ortası) YOK: fiyat serisinin noktaları gece yarısına snap
  // edilir (`ResolutionTier.normalizeTs`), çubuk da aynı ana oturmalı.
  double? barX(DateTime txDay, DateTime start) {
    final startMidnight = DateTime(start.year, start.month, start.day);
    final startOffsetDays =
        startMidnight.difference(start).inMinutes / (60.0 * 24.0);
    final dayMidnight = DateTime(txDay.year, txDay.month, txDay.day);
    final dayIdx = dayMidnight.difference(startMidnight).inDays;
    if (dayIdx < 0) return null;
    return startOffsetDays + dayIdx.toDouble();
  }

  group('hacim çubuğu X hizası', () {
    // Öğleden sonra bakılıyor: start'ta 14:37 var — hatanın tetikleyicisi.
    final start = DateTime(2026, 7, 12, 14, 37);

    test('çubuk, o günün FİYAT NOKTASIYLA birebir aynı X\'e düşer', () {
      // Bu testin kilitlediği değişmez: fiyat serisinin noktaları
      // `normalizeTs` ile gece yarısına snap edilir, X ekseni tarih
      // etiketleri de oradadır. Çubuk tam olarak o ana oturmalı — yarım
      // gün bile kayarsa kullanıcı "örtüşmüyor" diye görür.
      final tx = DateTime(2026, 7, 20, 9, 15);
      final x = barX(tx, start)!;
      final priceSpotX = priceX(DateTime(2026, 7, 20), start);
      expect(x, closeTo(priceSpotX, 1e-9));
    });

    test('gün ortası (+0.5) kayması KALMADI', () {
      // Regresyon: çubuk gün ortasına konuyordu; fiyat noktası gece
      // yarısındaydı. Aradaki yarım gün ekranda net görülüyordu.
      final tx = DateTime(2026, 7, 20, 9, 15);
      final x = barX(tx, start)!;
      final noonX = priceX(DateTime(2026, 7, 20, 12), start);
      expect((noonX - x), closeTo(0.5, 1e-9),
          reason: 'gün ortası, gece yarısından tam yarım gün ileride');
      expect(x, isNot(closeTo(noonX, 1e-6)));
    });

    test('eski hesap fiyat noktasıyla örtüşmüyordu', () {
      final tx = DateTime(2026, 7, 20, 9, 15);
      final legacy = legacyBarX(tx, start)!;
      final priceSpotX = priceX(DateTime(2026, 7, 20), start);
      expect(legacy, isNot(closeTo(priceSpotX, 1e-6)));
      // Yeni hesap örtüşüyor.
      expect(barX(tx, start)!, closeTo(priceSpotX, 1e-9));
    });

    test('her gün için çubuk ile fiyat noktası ÇAKIŞIR (10 gün süpürme)', () {
      for (int i = 0; i < 10; i++) {
        final tx = DateTime(2026, 7, 13).add(Duration(days: i));
        final x = barX(tx, start)!;
        final spotX = priceX(DateTime(tx.year, tx.month, tx.day), start);
        expect(x, closeTo(spotX, 1e-9), reason: 'gün $i');
      }
    });

    test('BUGÜN yapılan işlem elenmez', () {
      // start = 30 gün önce (saatli). Bugünkü işlem son çubuk olmalı.
      final now = DateTime(2026, 8, 11, 16, 5);
      final s = now.subtract(const Duration(days: 30));
      final x = barX(now, s);
      expect(x, isNotNull, reason: 'bugünkü işlem çubuğu kaybolmamalı');
      expect(x!, greaterThan(0));
    });

    test('dönem başlangıcından ÖNCEKİ işlem elenir', () {
      final tx = DateTime(2026, 7, 1);
      expect(barX(tx, start), isNull);
    });

    test('ardışık günlerin çubukları tam 1 gün aralıklı (30 gün süpürme)', () {
      double? prev;
      for (int i = 0; i < 30; i++) {
        final tx = DateTime(2026, 7, 13).add(Duration(days: i));
        final x = barX(tx, start);
        expect(x, isNotNull, reason: 'gün $i elendi');
        if (prev != null) {
          expect(x! - prev, closeTo(1.0, 1e-9), reason: 'gün $i adımı');
        }
        prev = x;
      }
    });

    test('start gece yarısı olsa bile doğru (offset sıfır)', () {
      final s = DateTime(2026, 7, 12);
      final tx = DateTime(2026, 7, 20);
      // 12 Tem → 20 Tem = 8 tam gün, kesir yok.
      expect(barX(tx, s), closeTo(8.0, 1e-9));
      expect(barX(tx, s), closeTo(priceX(tx, s), 1e-9));
    });

    test('günün saati çubuk konumunu DEĞİŞTİRMEZ', () {
      // Aynı gün içinde farklı saatlerde yapılan işlemler tek çubuktur;
      // konum yalnızca güne bağlı olmalı.
      final a = barX(DateTime(2026, 7, 20, 0, 1), start)!;
      final b = barX(DateTime(2026, 7, 20, 23, 59), start)!;
      expect(a, closeTo(b, 1e-9));
    });
  });

  group('küçük hacimli çubuk görünürlüğü', () {
    // Tek büyük alım ölçeği belirlediğinde küçük işlemler 1px altına düşüp
    // "kırıntı" gibi görünüyordu.
    double drawY(double total, double chartMaxY) {
      final minVisible = chartMaxY * 0.06;
      return total < minVisible ? minVisible : total;
    }

    test('çok küçük çubuk taban yüksekliğine yükseltilir', () {
      const chartMaxY = 1000000 * 1.15;
      expect(drawY(500, chartMaxY), closeTo(chartMaxY * 0.06, 1e-9));
    });

    test('büyük çubuk gerçek değerinde kalır', () {
      const chartMaxY = 1000000 * 1.15;
      expect(drawY(900000, chartMaxY), 900000);
    });

    test('taban, panelin tepesini asla aşmaz', () {
      const chartMaxY = 1000000 * 1.15;
      expect(drawY(1, chartMaxY), lessThan(chartMaxY));
    });
  });
}
