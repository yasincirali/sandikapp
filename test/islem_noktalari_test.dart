import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/utils/islem_noktalari.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı bildirimi (2026-09-24, 5556 emülatörü, 1H grafiği):
///   * *"Düğüm noktalarından kontrol ettiğimde − ya da + yaratmasına rağmen
///     sıçrama / dik düşüş yaşanmıyor."*
///   * *"Alım satım noktaları ile alttaki hacim çizgileri timeline'da tam
///     eşleşmeli."*
///   * *"Düğümlerde karışık bilgi yazmamalı; hem alım hem satım varsa net
///     artış ya da azalış bilgisi yer almalı."*
///
/// Kilitlenen kural: işlem, motorun onu seriye kattığı noktaya bağlanır
/// (ham anından büyük-eşit İLK nokta; gün içinde 5 dk'ya yuvarlanmış an).
/// İşaret, crosshair ve hacim aynı haritadan okur.
void main() {
  Asset lot({
    required DateTime tarih,
    double tutar = 1000,
    AssetKind kind = AssetKind.buy,
    DateTime? silindi,
    String id = 'l',
  }) =>
      Asset(
        id: id,
        userId: 'u',
        name: 'X',
        ticker: 'X',
        type: AssetType.hisse,
        quantity: 1,
        purchasePrice: tutar,
        currency: 'TRY',
        notes: '',
        addedDate: tarih,
        kind: kind,
        sellPrice: kind == AssetKind.sell ? tutar : null,
        deletedAt: silindi,
      );

  final start = DateTime(2026, 9, 17); // 1H penceresi başı, 00:00
  double gunX(DateTime t) =>
      t.difference(start).inMilliseconds / (60000.0 * 60 * 24);

  group('saatlik seri (1H)', () {
    // Pzt–Cum 00:00..23:00, hafta sonu YOK (motor Cts/Paz slotlarını atlar).
    final spots = <FlSpot>[
      for (var g = 0; g < 8; g++)
        if (start.add(Duration(days: g)).weekday <= 5)
          for (var h = 0; h < 24; h++)
            FlSpot(gunX(start.add(Duration(days: g, hours: h))), 100.0),
    ];

    test('17:08 satışı 18:00 noktasına bağlanır — basamağın göründüğü yer', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [
          lot(tarih: DateTime(2026, 9, 22, 17, 8), kind: AssetKind.sell)
        ],
        startDate: start,
        intraday: false,
      );
      expect(m.keys.single, closeTo(gunX(DateTime(2026, 9, 22, 18)), 1e-9),
          reason: 'motor lot\'u addedDate <= slot başı olan İLK slota katar; '
              '17:00 noktası satışı henüz içermez');
      expect(m.values.single.satis, 1000);
      expect(m.values.single.alim, 0);
    });

    test('hafta sonu alımı pazartesi 00:00 noktasına bağlanır', () {
      // 19 Eyl Cumartesi 21:07 — seride Cts/Paz noktası yok.
      final m = islemNoktalari(
        spots: spots,
        lotlar: [lot(tarih: DateTime(2026, 9, 19, 21, 7))],
        startDate: start,
        intraday: false,
      );
      expect(m.keys.single, closeTo(gunX(DateTime(2026, 9, 21)), 1e-9),
          reason: 'eski kural (kapsayan nokta) Cuma 23:00\'e bağlıyor, '
              'basamak ise Pazartesi\'de çıkıyordu');
    });

    test('son noktadan sonraki işlem son noktaya (canlı uç) bağlanır', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [lot(tarih: DateTime(2026, 9, 30, 12))],
        startDate: start,
        intraday: false,
      );
      expect(m.keys.single, spots.last.x);
    });

    test('pencere öncesi işlem, temettü ve silinmiş lot nokta üretmez', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [
          lot(tarih: DateTime(2026, 9, 10)),
          lot(tarih: DateTime(2026, 9, 22, 10), kind: AssetKind.dividend),
          lot(tarih: DateTime(2026, 9, 22, 10), silindi: DateTime(2026, 9, 23)),
        ],
        startDate: start,
        intraday: false,
      );
      expect(m, isEmpty);
    });

    test('aynı noktada alım + satış → NET ve karışık bayrağı', () {
      // 23 Eyl 00:08 +10, 00:19 −20, 00:27 +10 → hepsi 01:00 noktasında.
      final m = islemNoktalari(
        spots: spots,
        lotlar: [
          lot(id: 'a', tarih: DateTime(2026, 9, 23, 0, 8), tutar: 108000),
          lot(id: 'b', tarih: DateTime(2026, 9, 23, 0, 19), tutar: 216000,
              kind: AssetKind.sell),
          lot(id: 'c', tarih: DateTime(2026, 9, 23, 0, 27), tutar: 108000),
        ],
        startDate: start,
        intraday: false,
      );
      final n = m.values.single;
      expect(n.x, closeTo(gunX(DateTime(2026, 9, 23, 1)), 1e-9));
      expect(n.karisik, isTrue);
      expect(n.net, closeTo(0, 1e-9), reason: 'üçlü birbirini götürür');
      expect(n.alimSayisi, 2);
      expect(n.satisSayisi, 1);
    });
  });

  group('günlük seri (1A)', () {
    final spots = [
      for (var g = 0; g < 30; g++) FlSpot(g.toDouble(), 100.0),
    ];
    test('gün içi işlem ERTESİ günün noktasına bağlanır', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [lot(tarih: DateTime(2026, 9, 22, 17, 8))],
        startDate: start,
        intraday: false,
      );
      expect(m.keys.single, 6.0,
          reason: '22 Eyl 17:08 > 22 Eyl 00:00 slot başı → 23 Eyl (x=6)');
    });
    test('00:00 girilen işlem (tarih seçici) AYNI günün noktasında', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [lot(tarih: DateTime(2026, 9, 22))],
        startDate: start,
        intraday: false,
      );
      expect(m.keys.single, 5.0);
    });
  });

  group('gün içi seri (GÜNLÜK, X = dakika)', () {
    final gun = DateTime(2026, 9, 23);
    final spots = [
      for (var dk = 600; dk <= 1080; dk += 5) FlSpot(dk.toDouble(), 100.0),
    ];
    test('14:32 alımı 14:30 kovasına — motorun aşağı yuvarlaması', () {
      final m = islemNoktalari(
        spots: spots,
        lotlar: [lot(tarih: DateTime(2026, 9, 23, 14, 32))],
        startDate: gun,
        intraday: true,
      );
      expect(m.keys.single, 870.0, reason: '14:30 = 870. dakika');
    });
  });

  test('kaynak: işaret, crosshair ve hacim AYNI haritadan', () {
    final src = ekranKaynagiSync(
            'lib/screens/portfolio_performance/grafik_kabi.dart')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('candidates: noktalar.keys.toList(),'), isTrue);
    expect(src.contains('final n = noktalar[snapped.x];'), isTrue);
    expect(src.contains('_computeVolumeBars(noktalar)'), isTrue);
    expect(src.contains('if (addMid != spotDayMs) continue;'), isFalse,
        reason: 'crosshair takvim gününe değil noktaya bakmalı');
    expect(src.contains('crosshairNetBuy'), isTrue,
        reason: 'karışık noktada NET yazılmalı');
  });
}
