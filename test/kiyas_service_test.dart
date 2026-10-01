import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/kiyas_service.dart';
import 'package:portfoy_takip/services/kiyas_yukleyici.dart';
import 'package:portfoy_takip/services/para_agirlikli_getiri.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// "Başka yere koysaydın" — kamu piyasası eşdeğeri (PME) hesabı.
///
/// Elle hesaplanan örnekler bilinçli olarak küçük sayılarla kuruldu:
/// kartın gösterdiği her rakam bir kağıt kalemle doğrulanabilmeli.
void main() {
  const gun = 24 * 60 * 60 * 1000;
  final t0 = DateTime(2026, 3, 2).millisecondsSinceEpoch;
  int g(int n) => t0 + n * gun;

  group('kiyasla — saf PME', () {
    test('akış yoksa kıyas getirisi = kıyas fiyat değişimi', () {
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(10),
        akislar: const [],
        fiyatSerisi: {g(0): 40, g(5): 44, g(10): 42},
      )!;
      expect(h.getiriPct, closeTo((42 / 40 - 1) * 100, 1e-9));
      expect(h.sonTRY, closeTo(1000 * 42 / 40, 1e-9));
      expect(h.farkPuan, isNull,
          reason: 'Kullanıcının getirisi verilmedi; fark uydurulmaz.');
    });

    test('tek alım — elle hesaplanmış örnek', () {
      // Dönem başı ₺1.000 @10 → 100 birim. 5. gün ₺1.000 alım @20 → +50
      // birim. Son fiyat 25 → 150 × 25 = ₺3.750.
      // Para ağırlıklı getiri: 1000(1+r) + 1000(1+r)^0,5 = 3750.
      // x = √(1+r): x² + x − 3,75 = 0 → x = 1,5 → r = %125.
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(10),
        akislar: [(ts: g(5), tutar: 1000)],
        fiyatSerisi: {g(0): 10, g(5): 20, g(10): 25},
        kullaniciGetiriPct: 34.0,
      )!;
      expect(h.sonTRY, closeTo(3750, 1e-6));
      expect(h.getiriPct, closeTo(125, 1e-6));
      expect(h.farkPuan, closeTo(34.0 - 125, 1e-6));
    });

    test('satış ve temettü kıyastan aynı TL tutarla çekilir', () {
      // ₺1.000 @10 = 100 birim; fiyat 5. günde 20'ye çıkar ve kalır.
      // 5. gün satış ₺500 → −25 birim; 7. gün temettü ₺200 → −10 birim.
      // Kalan 65 birim × 20 = ₺1.300.
      final akislar = <KiyasAkisi>[
        (ts: g(7), tutar: -200),
        (ts: g(5), tutar: -500), // sırasız verilse de sıralanır
      ];
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(10),
        akislar: akislar,
        fiyatSerisi: {g(0): 10, g(5): 20, g(10): 20},
      )!;
      expect(h.sonTRY, closeTo(1300, 1e-6));
      // Getiri kullanıcınınkiyle AYNI motordan, aynı ağırlıklarla.
      final beklenen = paraAgirlikliGetiriPct(bas: 1000, son: 1300, akislar: [
        (f: -500.0, w: 0.5),
        (f: -200.0, w: 0.3),
      ])!;
      expect(h.getiriPct, closeTo(beklenen, 1e-9));
      expect(h.getiriPct, greaterThan(0));
    });

    test('her şeyi satan kullanıcı: kuruş altı fark sıfıra iner', () {
      // 100 birim @10; 8. gün @20 değer ₺2.000, tamamı çekilir.
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(10),
        akislar: [(ts: g(8), tutar: -2000.004)],
        fiyatSerisi: {g(0): 10, g(8): 20, g(10): 30},
      );
      expect(h, isNotNull);
      expect(h!.sonTRY, 0);
    });

    test('çekiş kıyas değerini aşarsa null — negatif bakiye taşınmaz', () {
      // ₺1.000 @10, fiyat yarıya iner: kıyas ₺500 değerinde, ₺600 çekiş.
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(10),
        akislar: [(ts: g(5), tutar: -600)],
        fiyatSerisi: {g(0): 10, g(5): 5, g(10): 5},
      );
      expect(h, isNull);
    });

    test('dönem başı fiyatı yoksa null', () {
      // Seri dönem başından 20 gün sonra başlıyor (ileri tolerans 7 gün).
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(30),
        akislar: const [],
        fiyatSerisi: {g(20): 10, g(30): 12},
      );
      expect(h, isNull);
    });

    test('akış anı serideki bir DELİĞE düşerse null', () {
      // 1. ile 25. gün arası ölçüm yok; 20. gündeki alımın fiyatı 19 gün
      // bayat olurdu (geri tolerans 10 gün).
      final h = KiyasService.kiyasla(
        basTRY: 1000,
        basTs: g(0),
        sonTs: g(30),
        akislar: [(ts: g(20), tutar: 500)],
        fiyatSerisi: {g(0): 10, g(1): 10, g(25): 12, g(30): 12},
      );
      expect(h, isNull);
    });

    test('boş seri ya da sıfır dönem başı null', () {
      expect(
          KiyasService.kiyasla(
              basTRY: 1000,
              basTs: g(0),
              sonTs: g(5),
              akislar: const [],
              fiyatSerisi: const {}),
          isNull);
      expect(
          KiyasService.kiyasla(
              basTRY: 0,
              basTs: g(0),
              sonTs: g(5),
              akislar: const [],
              fiyatSerisi: {g(0): 1, g(5): 2}),
          isNull);
    });
  });

  group('fiyatAt — akış anındaki fiyat', () {
    final seri = {g(0): 10.0, g(3): 13.0, g(4): 14.0};

    test('o anda ya da ÖNCESİNDEKİ son ölçüm (ileriye bakmaz)', () {
      expect(KiyasService.fiyatAt(seri, g(3)), 13);
      // 3,9. gün: 4. günün fiyatı DEĞİL, 3. günün.
      expect(KiyasService.fiyatAt(seri, g(3) + gun * 9 ~/ 10), 13);
      // Hafta sonu: son seansın kapanışı.
      expect(KiyasService.fiyatAt(seri, g(6)), 14);
    });

    test('serinin sol kenarı: yakın ilk ölçüm kabul, uzak değil', () {
      expect(KiyasService.fiyatAt(seri, g(-2)), 10);
      expect(KiyasService.fiyatAt(seri, g(-8)), isNull);
    });

    test('son ölçüm 10 günden eskiyse fiyat bilinmiyor', () {
      expect(KiyasService.fiyatAt(seri, g(14)), 14);
      expect(KiyasService.fiyatAt(seri, g(15)), isNull);
    });

    test('sıfır/negatif değerler ölçüm sayılmaz', () {
      expect(KiyasService.fiyatAt({g(0): 10, g(1): 0}, g(1)), 10);
    });
  });

  group('KiyasGirdisi.kur — Özet ile aynı kurallar', () {
    final now = DateTime(2026, 6, 15, 12);

    Asset lot({
      required DateTime tarih,
      double miktar = 10,
      double fiyat = 100,
      AssetKind kind = AssetKind.buy,
      double temettu = 0,
      double? satisFiyati,
    }) =>
        Asset(
          id: '${tarih.millisecondsSinceEpoch}-${kind.name}',
          userId: 'u',
          name: 'THYAO',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: miktar,
          purchasePrice: fiyat,
          currency: 'TRY',
          notes: '',
          addedDate: tarih,
          kind: kind,
          dividendAmount: temettu,
          sellPrice: satisFiyati,
        );

    // Günlük seri: 15 Mayıs–31 Mayıs ₺1.000 → 1.100; 1 Haziran'da ₺500
    // alım; sonrası ₺1.650 → 1.700.
    Map<int, double> seri() {
      final out = <int, double>{};
      for (var d = DateTime(2026, 5, 15);
          !d.isAfter(DateTime(2026, 6, 15));
          d = d.add(const Duration(days: 1))) {
        final once = d.isBefore(DateTime(2026, 6, 1));
        final i = d.difference(DateTime(2026, 5, 15)).inDays;
        out[d.millisecondsSinceEpoch] =
            once ? 1000 + i * 100 / 17 : 1650 + (i - 17) * 50 / 14;
      }
      return out;
    }

    final lotlar = [
      lot(tarih: DateTime(2026, 1, 5)),
      lot(tarih: DateTime(2026, 6, 1, 10), miktar: 5),
    ];

    test('temettüsüz dönemde kullanıcı getirisi Özet ile BİREBİR', () {
      final s = seri();
      final g = KiyasGirdisi.kur(
        period: SummaryPeriod.birAy,
        lotlar: lotlar,
        seri: s,
        now: now,
      )!;
      final p = PeriodSummaryService.pencere(SummaryPeriod.birAy, now);
      final pe = PeriodSummaryService.piyasaEtkisi(
          seri: s, lotlar: lotlar, start: p.start, end: p.end)!;
      expect(g.basTRY, pe.ilk);
      expect(g.basTs, pe.ilkTs);
      expect(g.sonTRY, pe.son);
      expect(g.getiriPct, closeTo(pe.pct!, 1e-9),
          reason: 'Aynı akış, aynı ağırlık: kıyas kartının "senin" satırı '
              'Özet\'in getiri yüzdesiyle ayrışmamalı.');
      expect(g.akislar, [
        (ts: DateTime(2026, 6, 1, 10).millisecondsSinceEpoch, tutar: 500.0)
      ]);
      expect(g.temettuVar, isFalse);
    });

    test('canlı uç: dönem sonu "şimdi", akış penceresi gün sonu', () {
      final g = KiyasGirdisi.kur(
        period: SummaryPeriod.birAy,
        lotlar: lotlar,
        seri: seri(),
        now: now,
        canliSon: 1720,
      )!;
      expect(g.sonTRY, 1720);
      expect(g.sonTs, now.millisecondsSinceEpoch);
    });

    test('nakit temettü ÇIKIŞ olarak girer ve not bayrağını açar', () {
      final ile = [
        ...lotlar,
        lot(
            tarih: DateTime(2026, 6, 5, 9),
            kind: AssetKind.dividend,
            miktar: 0,
            temettu: 40),
      ];
      final g = KiyasGirdisi.kur(
        period: SummaryPeriod.birAy,
        lotlar: ile,
        seri: seri(),
        now: now,
      )!;
      expect(g.temettuVar, isTrue);
      expect(g.akislar.map((a) => a.tutar), [500.0, -40.0]);
      // Tek getiri dili (K3): Özet de temettüyü çıkış sayar, "senin"
      // satırı temettülü dönemde de Özet'in yüzdesiyle BİREBİR.
      final p = PeriodSummaryService.pencere(SummaryPeriod.birAy, now);
      final pe = PeriodSummaryService.piyasaEtkisi(
          seri: seri(), lotlar: ile, start: p.start, end: p.end)!;
      expect(g.getiriPct, closeTo(pe.pct!, 1e-9));
      // Temettü çekiş sayıldığı için getiri temettüsüz hâlden YÜKSEK.
      final temettusuz = KiyasGirdisi.kur(
        period: SummaryPeriod.birAy,
        lotlar: lotlar,
        seri: seri(),
        now: now,
      )!;
      expect(g.getiriPct!, greaterThan(temettusuz.getiriPct!));
    });

    test('satış ele geçen tutarla çıkış olur (flowOf kuralı)', () {
      final ile = [
        ...lotlar,
        lot(
            tarih: DateTime(2026, 6, 10, 11),
            kind: AssetKind.sell,
            miktar: 2,
            satisFiyati: 120),
      ];
      final g = KiyasGirdisi.kur(
        period: SummaryPeriod.birAy,
        lotlar: ile,
        seri: seri(),
        now: now,
      )!;
      expect(g.akislar.last.tutar, closeTo(-240, 1e-9));
    });

    test('GÜNLÜK ve serisiz dönem için null', () {
      expect(
          KiyasGirdisi.kur(
              period: SummaryPeriod.gunluk,
              lotlar: lotlar,
              seri: seri(),
              now: now),
          isNull);
      expect(
          KiyasGirdisi.kur(
              period: SummaryPeriod.birAy,
              lotlar: lotlar,
              seri: const {},
              now: now),
          isNull);
    });

    test('değer eşitliği — provider ailesinin anahtarı', () {
      KiyasGirdisi kur() => KiyasGirdisi.kur(
          period: SummaryPeriod.birAy, lotlar: lotlar, seri: seri(), now: now)!;
      expect(kur(), kur());
      expect(kur().hashCode, kur().hashCode);
    });
  });

  group('ozet', () {
    test('hesaplanamayan kıyas haritada yok; sıra korunur', () {
      final girdi = KiyasGirdisi(
        period: SummaryPeriod.birAy,
        start: DateTime.fromMillisecondsSinceEpoch(g(0)),
        end: DateTime.fromMillisecondsSinceEpoch(g(10)),
        basTRY: 1000,
        basTs: g(0),
        sonTRY: 1100,
        sonTs: g(10),
        akislar: const [],
        getiriPct: 10,
        temettuVar: false,
      );
      final o = KiyasService.ozet(girdi, {
        KiyasVarligi.bist100: {g(0): 100, g(10): 105},
        KiyasVarligi.dolar: {g(0): 40, g(10): 42},
        // altın: seri hiç yok
      })!;
      expect(o.satirlar.keys, [KiyasVarligi.dolar, KiyasVarligi.bist100]);
      expect(o.satirlar[KiyasVarligi.dolar]!.farkPuan, closeTo(5, 1e-9));
      expect(o.satirlar[KiyasVarligi.bist100]!.farkPuan, closeTo(5, 1e-9));
    });

    test('kullanıcının getirisi yoksa kart yok', () {
      final girdi = KiyasGirdisi(
        period: SummaryPeriod.birAy,
        start: DateTime(2026),
        end: DateTime(2026, 2),
        basTRY: 1000,
        basTs: g(0),
        sonTRY: 1100,
        sonTs: g(10),
        akislar: const [],
        getiriPct: null,
        temettuVar: false,
      );
      expect(KiyasService.ozet(girdi, const {}), isNull);
    });
  });

  group('KiyasYukleyici', () {
    test('haftalık katman günlüğe iner; kenar payı eklenir', () async {
      final istekler = <(String, int, ResolutionTier?)>[];
      Future<Map<int, double>> sahte(String s,
          {required int periodDays, ResolutionTier? cozunurluk}) async {
        istekler.add((s, periodDays, cozunurluk));
        return {1: 1.0};
      }

      final s = await KiyasYukleyici.serileriGetir(SummaryPeriod.birYil,
          getir: sahte);
      expect(s.keys, KiyasVarligi.values);
      expect(istekler.map((e) => e.$1),
          KiyasVarligi.values.map((v) => v.sembol));
      expect(istekler.every((e) => e.$2 == 365 + KiyasYukleyici.kenarPayiGun),
          isTrue);
      expect(istekler.every((e) => e.$3 == ResolutionTier.daily), isTrue);

      expect(KiyasYukleyici.cozunurluk(SummaryPeriod.birHafta),
          ResolutionTier.hourly,
          reason: 'Günlükten ince katman korunur.');
    });

    test('bir sembolün hatası diğerlerini düşürmez; boş seri elenir', () async {
      Future<Map<int, double>> sahte(String s,
          {required int periodDays, ResolutionTier? cozunurluk}) async {
        if (s == KiyasVarligi.dolar.sembol) throw StateError('ağ');
        if (s == KiyasVarligi.altin.sembol) return {};
        return {1: math.pi};
      }

      final s = await KiyasYukleyici.serileriGetir(SummaryPeriod.birAy,
          getir: sahte);
      expect(s.keys, [KiyasVarligi.bist100]);
    });

    test('GÜNLÜK ağa çıkmaz', () async {
      var cagri = 0;
      Future<Map<int, double>> sahte(String s,
          {required int periodDays, ResolutionTier? cozunurluk}) async {
        cagri++;
        return {1: 1.0};
      }

      expect(
          await KiyasYukleyici.serileriGetir(SummaryPeriod.gunluk,
              getir: sahte),
          isEmpty);
      expect(cagri, 0);
    });
  });

  test('kıyas sembolleri sözleşmeden gelir', () {
    expect(KiyasVarligi.dolar.sembol, FiyatKaynagi.usdTry);
    expect(KiyasVarligi.altin.sembol, FiyatKaynagi.gramAltin24);
    expect(KiyasVarligi.bist100.sembol, FiyatKaynagi.bist100);
  });
}
