// Düello arenasının lider şeridi (bayrak `yaris_duello_arena`, 2026-10-04).
//
// Kilitlenenler: iki kişi AYNI ölçüm anlarında kıyaslanır; bir kişinin
// ölçülmediği gün "bilinmiyor" (uydurma yok); yıllık dönem 12 kovaya iner
// (kova sonu durumu); yer değişimi başa baş/bilinmeyen günleri saymaz.
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/lider_seridi.dart';

const _gunMs = 24 * 60 * 60 * 1000;
final _now = DateTime.utc(2026, 10, 4, 12).millisecondsSinceEpoch;

/// Bugünden geriye [n] günlük birikim serisi (eskiden yeniye).
List<({int an, double pct})> _seri(List<double> pct) => [
      for (var i = 0; i < pct.length; i++)
        (an: _now - (pct.length - 1 - i) * _gunMs, pct: pct[i]),
    ];

void main() {
  test('hafta: gün gün, ölçüm anları hizalı', () {
    final s = liderSeridiKur(
      ben: _seri([1, 2, 1, 0.5, 2, 3, 4]),
      rakip: _seri([2, 1, 1.02, 1, 1, 1, 1]),
      gun: 7,
      nowMs: _now,
    )!;
    expect(s.aylik, isFalse);
    expect(s.cubuklar, [
      SeritLider.rakip,
      SeritLider.ben,
      SeritLider.berabere, // 0,02 puan < 0,05 eşiği
      SeritLider.rakip,
      SeritLider.ben,
      SeritLider.ben,
      SeritLider.ben,
    ]);
    // rakip → ben → (berabere atlanır) rakip → ben = 3 değişim.
    expect(s.yerDegisimi, 3);
    expect(s.baslangic.millisecondsSinceEpoch, _now - 6 * _gunMs);
  });

  test('geç başlayan kişi: başlamadan önceki günler bilinmiyor', () {
    final s = liderSeridiKur(
      ben: _seri([1, 2, 3, 4, 5, 6, 7]),
      rakip: _seri([9, 9, 9]), // yalnız son 3 gün
      gun: 7,
      nowMs: _now,
    )!;
    expect(s.cubuklar.take(4), everyElement(SeritLider.bilinmiyor));
    expect(s.cubuklar.skip(4), everyElement(SeritLider.rakip));
    expect(s.yerDegisimi, 0);
  });

  test('yıl: 12 kova, kova sonundaki lider', () {
    // 365 gün: ilk yarı ben önde, ikinci yarı rakip.
    final ben = _seri([for (var i = 0; i < 365; i++) i < 182 ? 5.0 : 0.0]);
    final rakip = _seri([for (var i = 0; i < 365; i++) 1.0]);
    final s = liderSeridiKur(ben: ben, rakip: rakip, gun: 365, nowMs: _now)!;
    expect(s.aylik, isTrue);
    expect(s.cubuklar.length, 12);
    expect(s.cubuklar.first, SeritLider.ben);
    expect(s.cubuklar.last, SeritLider.rakip);
    expect(s.yerDegisimi, 1);
  });

  test('seri yoksa ya da hiç ortak gün yoksa şerit yok', () {
    expect(
        liderSeridiKur(
            ben: null, rakip: _seri([1, 2]), gun: 7, nowMs: _now),
        isNull);
    expect(
        liderSeridiKur(
            ben: _seri([1]), rakip: const [], gun: 7, nowMs: _now),
        isNull);
    // Yalnız başa baş günler: kararlı çubuk yok → şerit bir şey anlatmaz.
    expect(
        liderSeridiKur(
            ben: _seri([1, 1, 1, 1, 1, 1, 1]),
            rakip: _seri([1, 1, 1, 1, 1, 1, 1]),
            gun: 7,
            nowMs: _now),
        isNull);
  });
}
