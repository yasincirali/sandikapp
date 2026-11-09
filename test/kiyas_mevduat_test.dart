import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/kiyas_service.dart';
import 'package:portfoy_takip/services/kiyas_yukleyici.dart';
import 'package:portfoy_takip/services/mevduat_hesabi.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// Kıyas kartının "Mevduatta" satırı (Ar-Ge 2026-11-07 madde 1): aynı nakit
/// akışı, TCMB haftalık faiziyle, stopaj düşülmüş, bileşik. Faiz yoksa satır
/// yok (uydurma sayı yasak).
void main() {
  DateTime g(int n) => DateTime(2025, 8, 1 + n);
  int ms(int n) => g(n).millisecondsSinceEpoch;
  List<MevduatFaizNoktasi> haftalik(int adet, double faiz, {int bas = 0}) => [
        for (var i = 0; i < adet; i++)
          (hafta: g(bas + 7 * i), yillikFaiz: faiz),
      ];

  // 2025-07-09 kararı: 6 aya kadar %17,5 → net = 40 × 0,825 = 33.
  const net = 40 * (1 - 17.5 / 100);
  final hafta = 1 + net / 100 * 7 / 365;

  group('mevduatKiyasSerisi', () {
    test('hafta içinde basit, hafta sonunda bileşik; stopaj düşülür', () {
      final s = mevduatKiyasSerisi(haftalik(4, 40), son: g(28));
      expect(s[ms(0)], 1.0);
      expect(s[ms(3)], closeTo(1 + net / 100 * 3 / 365, 1e-12));
      expect(s[ms(14)], closeTo(math.pow(hafta, 2), 1e-12));
      expect(s[ms(28)], closeTo(math.pow(hafta, 4), 1e-12));
    });

    test('sabit nakit akışı listesi: kiyasla mevduat getirisini verir', () {
      final s = mevduatKiyasSerisi(haftalik(4, 40), son: g(28));
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: ms(0),
        sonTs: ms(28),
        akislar: [
          (ts: ms(14), tutar: 500.0),
          (ts: ms(21), tutar: -200.0),
        ],
        fiyatSerisi: s,
      )!;
      final beklenen = 1000 * math.pow(hafta, 4) +
          500 * math.pow(hafta, 2) -
          200 * hafta;
      expect(h.sonTRY, closeTo(beklenen, 1e-6));
      expect(h.getiriPct, greaterThan(0));
    });

    test('stopaj kararı değişince yeni haftadan itibaren yeni oran', () {
      // 2025-07-04 haftası %15 (9487), 2025-07-11 haftası %17,5 (10041).
      final s = mevduatKiyasSerisi([
        (hafta: DateTime(2025, 7, 4), yillikFaiz: 40),
        (hafta: DateTime(2025, 7, 11), yillikFaiz: 40),
      ], son: DateTime(2025, 7, 18));
      final ilk = 1 + 40 * 0.85 / 100 * 7 / 365;
      final ikinci = 1 + 40 * 0.825 / 100 * 7 / 365;
      expect(s[DateTime(2025, 7, 11).millisecondsSinceEpoch],
          closeTo(ilk, 1e-12));
      expect(s[DateTime(2025, 7, 18).millisecondsSinceEpoch],
          closeTo(ilk * ikinci, 1e-12));
    });

    test('faiz yok → boş seri → satır yok', () {
      expect(mevduatKiyasSerisi(const [], son: g(28)), isEmpty);
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: ms(0),
        sonTs: ms(28),
        akislar: const [],
        fiyatSerisi: mevduatKiyasSerisi(const [], son: g(28)),
      );
      expect(h, isNull);
    });

    test('bayat faiz bugüne taşınmaz', () {
      expect(mevduatKiyasSerisi(haftalik(2, 40), son: g(7 + 22)), isEmpty);
    });

    test('boşlukta yalnız son kesintisiz parça kalır; dönem başı kapsanmaz',
        () {
      final faiz = [...haftalik(2, 40), ...haftalik(2, 40, bas: 40)];
      final s = mevduatKiyasSerisi(faiz, son: g(50));
      expect(s.keys.reduce(math.min), ms(40));
      expect(
        KiyasService.kiyasla(
            basTRY: 1000,
            basTs: ms(0),
            sonTs: ms(50),
            akislar: const [],
            fiyatSerisi: s),
        isNull,
      );
    });

    test('stopajı bilinmeyen hafta (tablo öncesi) atılır', () {
      expect(bilinenStopaj(DateTime(2025, 1, 31), 32), isNull);
      expect(bilinenStopaj(DateTime(2025, 2, 1), 32), 15);
      final s = mevduatKiyasSerisi([
        (hafta: DateTime(2025, 1, 24), yillikFaiz: 45),
        (hafta: DateTime(2025, 1, 31), yillikFaiz: 45),
      ], son: DateTime(2025, 2, 7));
      expect(s, isEmpty);
    });
  });

  group('KiyasYukleyici mevduat', () {
    Future<Map<int, double>> fiyat(String s,
            {required int periodDays, ResolutionTier? cozunurluk}) async =>
        {1: 1.0};

    test('faiz geçmişi ay1 diliminden okunur, endekse çevrilir', () async {
      final istenen = <String>[];
      final s = await KiyasYukleyici.serileriGetir(
        SummaryPeriod.birAy,
        getir: fiyat,
        simdi: g(28),
        faizGetir: (dilim, bas) async {
          istenen.add(dilim);
          expect(bas.isBefore(g(28 - 31)), isTrue);
          return haftalik(5, 40, bas: -7);
        },
      );
      expect(istenen, [FiyatKaynagi.mevduatKiyasDilimi]);
      expect(KiyasVarligi.mevduat.sembol, 'ay1');
      expect(s[KiyasVarligi.mevduat]![ms(28)], greaterThan(1));
    });

    test('tablo yok / boş → mevduat satırı yok, diğerleri durur', () async {
      final s = await KiyasYukleyici.serileriGetir(SummaryPeriod.birAy,
          getir: fiyat,
          simdi: g(28),
          faizGetir: (_, __) async => throw StateError('relation yok'));
      expect(s.containsKey(KiyasVarligi.mevduat), isFalse);
      expect(s.containsKey(KiyasVarligi.dolar), isTrue);
    });
  });
}
