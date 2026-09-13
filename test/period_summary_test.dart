import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/recap_service.dart';

/// Dönem Özeti — katkı/piyasa ayrımının kilidi.
///
/// ## Bu dosyanın kovaladığı tek hata
/// **"Değer değişimi" ≠ "getiri".** Kullanıcı ₺12.000'lik alım yaptığında
/// portföy değeri ₺12.000 zıplar. Bu zıplama bir kazanç DEĞİLDİR — ama ham
/// uçtan uca farkta kazançtan ayırt edilemez. Özet sekmesinin var olma
/// sebebi bu ayrımı görünür kılmak; ayrım kırılırsa ekranın anlamı kalmaz.
///
/// Grafik sekmesindeki `_buildPeriodChangeCard` bilinçli olarak HAM
/// "birikim" değişimini gösteriyor (kullanıcı kararı, 2026-08-31). Özet
/// sekmesi aynı veriyi KAYNAĞINA AYIRARAK gösterir. İkisi çelişmiyor, farklı
/// soruları yanıtlıyor — ve bu dosya ikincisinin doğru soruyu yanıtladığını
/// kilitler.
///
/// ## İkinci kilit: üç yüzey parite
/// GÜNLÜK dönemin rakamı `DailySummary.from()` ile BİREBİR aynı olmak
/// zorunda (widget + Live Activity + üst kart). Ortak katman zaten var;
/// Özet sekmesi ikinci bir günlük hesap KURMAZ, ona delege eder. Delegasyon
/// sessizce koparsa kullanıcı aynı anda dört yüzeyde iki farklı rakam görür.

Asset _lot({
  required String id,
  required double qty,
  required double cur,
  required DateTime added,
  AssetKind kind = AssetKind.buy,
  double purchase = 100,
  double? sellPrice,
  String ticker = 'THYAO',
  AssetType type = AssetType.hisse,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: purchase,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: cur,
      addedDate: added,
      kind: kind,
      sellPrice: sellPrice,
    );

PortfolioState _state(List<Asset> a) =>
    PortfolioState(assets: a, usdTry: 42, eurTry: 46, gbpTry: 54);

/// Günlük kapanış serisi kurar — `daily` çözünürlük dalının şekli.
Map<int, double> _gunluk({
  required DateTime bas,
  required int gunSayisi,
  required double Function(int i) deger,
}) {
  final out = <int, double>{};
  for (var i = 0; i < gunSayisi; i++) {
    final d = DateTime(bas.year, bas.month, bas.day + i, 18);
    out[d.millisecondsSinceEpoch] = deger(i);
  }
  return out;
}

/// 5 dakikalık gün içi seans serisi.
Map<int, double> _seans({
  required DateTime gun,
  required int baslaDk,
  required int bitDk,
  required double Function(int i) deger,
}) {
  final out = <int, double>{};
  var i = 0;
  for (var dk = baslaDk; dk <= bitDk; dk += 5) {
    out[gun.add(Duration(minutes: dk)).millisecondsSinceEpoch] = deger(i++);
  }
  return out;
}

PortfolioHistoryBreakdown _bd(
  Map<int, double> total, {
  Map<AssetType, Map<int, double>>? byType,
  Map<String, Map<int, double>>? byPosition,
  Map<String, AssetType>? positionType,
  DateTime? seansGunu,
}) =>
    PortfolioHistoryBreakdown(
      total: total,
      byType: byType ?? {AssetType.hisse: total},
      byPosition: byPosition ?? const {},
      positionType: positionType ?? const {},
      seansGunu: seansGunu,
    );

void main() {
  // ══════════════════════════════════════════════════════════════════════
  // 1. Katkı / piyasa ayrımı — dosyanın ana sebebi
  // ══════════════════════════════════════════════════════════════════════
  group('katkı ile piyasa ayrımı', () {
    test('dönem içinde ₺12.000 alım varken getiri YALNIZCA piyasadan', () {
      final now = DateTime(2026, 9, 13, 15);
      // 30 gün: 168.774 → 185.684. Ham fark 16.910.
      // Bunun 12.000'i kullanıcının parası, 4.910'u piyasa.
      final bas = DateTime(2026, 8, 14);
      final total = _gunluk(
        bas: bas,
        gunSayisi: 31,
        deger: (i) =>
            i == 0 ? 168774.0 : (i < 15 ? 169000.0 + i * 50 : 185684.0),
      );

      final assets = [
        // Dönem BAŞINDAN önce alınmış taban pozisyon — akışa girmez.
        _lot(id: 'taban', qty: 1000, cur: 168.774, added: DateTime(2026, 1, 5)),
        // Dönem İÇİNDE ₺12.000'lik alım.
        _lot(
          id: 'yeni',
          qty: 100,
          cur: 120,
          purchase: 120,
          added: DateTime(2026, 8, 25),
        ),
      ];

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: assets,
        breakdown: _bd(total),
        now: now,
      );

      expect(s.katkiTRY, closeTo(12000, 0.01),
          reason: 'alım tutarı katkı olarak ayrılmalı');
      expect(s.piyasaTRY, closeTo(185684 - 168774 - 12000, 0.01),
          reason: 'saf getiri = (son − baş) − katkı');

      // Yüzde payda: başlangıç + POZİTİF katkı.
      const beklenenPct = 4910 / (168774 + 12000) * 100;
      expect(s.getiriPct, closeTo(beklenenPct, 0.001));

      // En kritik iddia: ham değişim yüzdesi (%10,02) ile saf getiri
      // yüzdesi (%2,72) ARASINDA kapanmayan bir fark var. Katkı ayrımı
      // kırılsaydı bu iki sayı eşitlenirdi.
      const hamPct = (185684 - 168774) / 168774 * 100;
      expect(s.getiriPct!, lessThan(hamPct - 5),
          reason: 'katkı ayrılmazsa getiri şişer — ayrım kırılmış olurdu');
    });

    test('net SATIŞ tabana eklenmez — satılan para piyasada değil', () {
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 8, 14);
      final total = _gunluk(
        bas: bas,
        gunSayisi: 31,
        deger: (i) => i == 0 ? 100000.0 : 95000.0,
      );

      final assets = [
        _lot(id: 'taban', qty: 1000, cur: 100, added: DateTime(2026, 1, 5)),
        // Dönem içinde ₺10.000'lik satış → katkı NEGATİF.
        _lot(
          id: 'satis',
          qty: 100,
          cur: 100,
          purchase: 80,
          sellPrice: 100,
          kind: AssetKind.sell,
          added: DateTime(2026, 8, 25),
        ),
      ];

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: assets,
        breakdown: _bd(total),
        now: now,
      );

      expect(s.katkiTRY, closeTo(-10000, 0.01),
          reason: 'satışta ele geçen tutar ÇIKIŞ (−sellProceedsTRY)');
      // Ham fark −5.000; bunun −10.000'i para çıkışı → piyasa +5.000.
      expect(s.piyasaTRY, closeTo(5000, 0.01));
      // Payda yalnızca başlangıç — negatif katkı EKLENMEZ.
      expect(s.getiriPct, closeTo(5000 / 100000 * 100, 0.001));
      expect(s.isNegative, isFalse,
          reason: 'portföy değeri düştü ama piyasa artıda');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 6. Katkının maskelediği kayıp — ayrımın en değerli olduğu senaryo
  // ══════════════════════════════════════════════════════════════════════
  group('katkı kaybı maskeliyor', () {
    test('portföy değeri ARTMIŞ ama piyasa EKSİDE', () {
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 8, 14);
      // 100.000 → 108.000: değer ARTTI. Ama içine 12.000 girdi,
      // yani piyasa −4.000 kaybetti.
      final total = _gunluk(
        bas: bas,
        gunSayisi: 31,
        deger: (i) => i == 0 ? 100000.0 : 108000.0,
      );

      final assets = [
        _lot(id: 'taban', qty: 1000, cur: 108, added: DateTime(2026, 1, 5)),
        _lot(
          id: 'yeni',
          qty: 100,
          cur: 120,
          purchase: 120,
          added: DateTime(2026, 8, 25),
        ),
      ];

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: assets,
        breakdown: _bd(total),
        now: now,
      );

      expect(s.sonTRY! > s.baslangicTRY!, isTrue,
          reason: 'portföy değeri gerçekten arttı');
      expect(s.piyasaTRY, closeTo(-4000, 0.01));
      expect(s.getiriPct!, lessThan(0));
      expect(s.isNegative, isTrue,
          reason: 'isNegative PİYASAYA bakar, portföy değerine değil — '
              'kullanıcı değer artışını kazanç sanmasın');
    });

    test('kayıp döneminde kutlama metni SEÇİLMEZ', () {
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 8, 14);
      final total = _gunluk(
        bas: bas,
        gunSayisi: 31,
        deger: (i) => i == 0 ? 100000.0 : 92000.0,
      );

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: [
          _lot(id: 'taban', qty: 1000, cur: 92, added: DateTime(2026, 1, 5)),
        ],
        breakdown: _bd(total),
        now: now,
      );

      expect(s.isNegative, isTrue);

      // Ton anahtarı (RETENTION_STRATEJISI §8): kutlama YOK, uyarı da YOK.
      final cumle = PeriodSummaryService.tonCumlesi(s, uzunDonemPct: 31.8);
      expect(cumle, 'Bu ay ekside. Daha uzun pencerede hâlâ +%31,8.');

      const yasakli = [
        'Tebrikler', 'tebrikler', 'Harika', 'harika', 'Muhteşem',
        '🎉', '🔥', '📈', '!', // ünlem = uyarı/kutlama tonu
        'düştü', 'Dikkat', 'Kaybettin', 'Al ', 'Sat ',
      ];
      for (final k in yasakli) {
        expect(cumle.contains(k), isFalse,
            reason: 'kayıp döneminde "$k" kullanılmamalı');
      }
    });

    test('uzun dönem bağlamı yoksa yalnızca nötr durum cümlesi', () {
      final now = DateTime(2026, 9, 13, 15);
      final total = _gunluk(
        bas: DateTime(2026, 8, 14),
        gunSayisi: 31,
        deger: (i) => i == 0 ? 100000.0 : 92000.0,
      );
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: [
          _lot(id: 't', qty: 1000, cur: 92, added: DateTime(2026, 1, 5)),
        ],
        breakdown: _bd(total),
        now: now,
      );
      expect(PeriodSummaryService.tonCumlesi(s), 'Bu ay ekside.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 2. Boş / eksik seri → null, 0 DEĞİL
  // ══════════════════════════════════════════════════════════════════════
  group('eksik veri null döner', () {
    test('boş seride her alan null', () {
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: [
          _lot(id: 'a', qty: 10, cur: 100, added: DateTime(2026, 1, 1)),
        ],
        breakdown: _bd(const {}),
        now: DateTime(2026, 9, 13),
      );

      expect(s.baslangicTRY, isNull);
      expect(s.sonTRY, isNull);
      expect(s.piyasaTRY, isNull);
      expect(s.getiriPct, isNull);
      expect(s.katkiTRY, isNull,
          reason: 'seri yoksa katkı da anlamsız — sıfır UYDURULMAZ');
      expect(s.isMeaningful, isFalse);
      // `isNegative` sıfıra düşer ama `isMeaningful` false olduğu için
      // ekran hiç çizmez.
      expect(s.isNegative, isFalse);
    });

    test('yalnızca sıfır/negatif slotlar varsa uçlar null', () {
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: const [],
        breakdown: _bd({
          DateTime(2026, 9, 1).millisecondsSinceEpoch: 0,
          DateTime(2026, 9, 2).millisecondsSinceEpoch: 0,
        }),
        now: DateTime(2026, 9, 13),
      );
      expect(s.baslangicTRY, isNull,
          reason: 'y<=0 slotlar atlanır — dönem başı sıfır sanılmasın');
      expect(s.getiriPct, isNull);
    });

    test('dönem başı değer 0 ise yüzde null (sonsuza gitmez)', () {
      final now = DateTime(2026, 9, 13);
      // Tüm slotlar pencere DIŞINDA kalırsa uçlar bulunamaz.
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: const [],
        breakdown: _bd({
          DateTime(2020, 1, 1).millisecondsSinceEpoch: 5000,
        }),
        now: now,
      );
      expect(s.getiriPct, isNull);
    });

    test('TÜFE endeksi yoksa tufeFarki null', () {
      final total = _gunluk(
        bas: DateTime(2026, 8, 14),
        gunSayisi: 31,
        deger: (i) => 100000.0 + i * 100,
      );
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: const [],
        breakdown: _bd(total),
        now: DateTime(2026, 9, 13),
      );
      expect(s.tufeFarki, isNull);

      final s2 = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: const [],
        breakdown: _bd(total),
        now: DateTime(2026, 9, 13),
        inflationPct: 2.1,
      );
      expect(s2.tufeFarki, closeTo(s2.getiriPct! - 2.1, 0.0001));
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 5. GÜNLÜK ≡ DailySummary.from() — üç yüzey paritesi
  // ══════════════════════════════════════════════════════════════════════
  group('GÜNLÜK dönem DailySummary ile birebir', () {
    test('changeTRY ve changePct aynı — piyasa açık, taze seri', () {
      final gun = DateTime(2026, 9, 10); // Perşembe
      final now = DateTime(2026, 9, 10, 14, 2);
      final series = _seans(
        gun: gun,
        baslaDk: 600,
        bitDk: 840,
        deger: (i) => 1000000 + i * 500.0,
      );

      final assets = [
        _lot(id: 'taban', qty: 10000, cur: 102.5, added: DateTime(2026, 1, 5)),
      ];
      final state = _state(assets);

      final gunluk = DailySummary.from(
          state: state, series: series, now: now, seansGunu: gun);

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.gunluk,
        assets: assets,
        breakdown: _bd(series, seansGunu: gun),
        now: now,
        gunlukOzet: gunluk,
      );

      expect(s.piyasaTRY, gunluk.changeTRY,
          reason: 'GÜNLÜK ikinci bir hesap KURMAZ, ortak katmana delege eder');
      expect(s.getiriPct, gunluk.changePct);
      expect(s.sparkline, gunluk.sparkline);
    });

    test('gün içinde ALIM varken de birebir', () {
      // Paritenin en kolay koptuğu yer: nakit akışı arındırması.
      final gun = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 10, 16, 0);
      final series = _seans(
        gun: gun,
        baslaDk: 600,
        bitDk: 960,
        deger: (i) => i < 20 ? 1000000 + i * 200.0 : 1170000 + i * 200.0,
      );

      final assets = [
        _lot(id: 'taban', qty: 10000, cur: 117, added: DateTime(2026, 1, 5)),
        // BUGÜN girilen ₺170.000'lik alım.
        _lot(
          id: 'bugun',
          qty: 1000,
          cur: 170,
          purchase: 170,
          added: DateTime(2026, 9, 10, 12, 30),
        ),
      ];
      final state = _state(assets);

      final gunluk = DailySummary.from(
          state: state, series: series, now: now, seansGunu: gun);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.gunluk,
        assets: assets,
        breakdown: _bd(series, seansGunu: gun),
        now: now,
        gunlukOzet: gunluk,
      );

      expect(s.piyasaTRY, gunluk.changeTRY);
      expect(s.getiriPct, gunluk.changePct);
      expect(s.katkiTRY, closeTo(170000, 0.01),
          reason: 'Özet katkıyı AYRICA gösterir — köprü bloğu bunu çizer');
    });

    test('HAFTA SONU: seri Cuma\'nın, pencere de Cuma\'nın', () {
      // Pazar günü açılan ekran Cuma seansını çizer. Pencere bugüne
      // kurulursa Cumartesi/Pazar girilen alım Cuma'nın hareketinden
      // düşülür — ölçülmüş hata (₺9.800 → ₺8.800).
      final cuma = DateTime(2026, 9, 11);
      final pazar = DateTime(2026, 9, 13, 11);
      final series = _seans(
        gun: cuma,
        baslaDk: 600,
        bitDk: 1090,
        deger: (i) => 1000000 + i * 100.0,
      );

      final assets = [
        _lot(id: 'taban', qty: 10000, cur: 100, added: DateTime(2026, 1, 5)),
        // PAZAR girilen alım — Cuma seansında henüz YOKTU.
        _lot(
          id: 'pazar',
          qty: 10,
          cur: 100,
          purchase: 100,
          added: DateTime(2026, 9, 13, 10),
        ),
      ];

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.gunluk,
        assets: assets,
        breakdown: _bd(series, seansGunu: cuma),
        now: pazar,
        gunlukOzet: DailySummary.from(
          state: _state(assets),
          series: series,
          now: pazar,
          seansGunu: cuma,
        ),
      );

      expect(s.start, DateTime(2026, 9, 11),
          reason: 'pencere ÇİZİLEN seansın günü — bugün değil');
      expect(s.katkiTRY, 0,
          reason: 'Pazar girilen alım Cuma penceresine girmez');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // 4. Dönem sınırları — takvim, ay başı, yıl başı, TR saat dilimi
  // ══════════════════════════════════════════════════════════════════════
  group('dönem sınırları', () {
    test('1A takvimden: 30 gün DEĞİL, önceki ayın aynı günü', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.birAy,
        DateTime(2026, 3, 31, 14),
      );
      // 31 Şubat yok → ayın son gününe kırpılır.
      expect(p.start, DateTime(2026, 2, 28));
    });

    test('artık yıl: 31 Mart − 1 ay → 29 Şubat', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.birAy,
        DateTime(2024, 3, 31, 14),
      );
      expect(p.start, DateTime(2024, 2, 29));
    });

    test('yıl sınırını geçen 6A doğru yıla düşer', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.altiAy,
        DateTime(2026, 3, 15, 9),
      );
      expect(p.start, DateTime(2025, 9, 15));
    });

    test('1Y tam bir yıl geri', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.birYil,
        DateTime(2026, 9, 13, 9),
      );
      expect(p.start, DateTime(2025, 9, 13));
    });

    test('1H sabit yedi gün — takvim ayına bağlı değil', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.birHafta,
        DateTime(2026, 9, 13, 23, 30),
      );
      expect(p.start, DateTime(2026, 9, 6));
    });

    test('ay başında 1A bir önceki ayın 1\'ine düşer', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.birAy,
        DateTime(2026, 1, 1, 8),
      );
      expect(p.start, DateTime(2025, 12, 1),
          reason: 'Ocak\'ın 1\'inde 1A → Aralık\'ın 1\'i');
    });

    test('TR saat dilimi (UTC+3): gün sınırı yerel 00:00', () {
      // 00:30 TR'de açılan ekran bugüne ait olmalı; UTC'ye göre
      // hesaplanırsa dün sanılırdı.
      final geceYarisi = DateTime(2026, 9, 13, 0, 30);
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.gunluk,
        geceYarisi,
      );
      expect(p.start, DateTime(2026, 9, 13),
          reason: 'yerel gün başı — UTC kaydırması uygulanmaz');
      expect(p.end.day, 13);
      expect(p.end.hour, 23);
    });

    test('GÜNLÜK pencere seansGunu verilince ONA kurulur', () {
      final p = PeriodSummaryService.pencere(
        SummaryPeriod.gunluk,
        DateTime(2026, 9, 13, 11),
        seansGunu: DateTime(2026, 9, 11),
      );
      expect(p.start, DateTime(2026, 9, 11));
      expect(p.end, DateTime(2026, 9, 11, 23, 59, 59));
    });

    test('donemBaslangici 12 ay geri = tam yıl', () {
      expect(
        PeriodSummaryService.donemBaslangici(DateTime(2026, 9, 13), 12),
        DateTime(2025, 9, 13),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Dönem sırası — iki sekme aynı indeksi paylaşıyor
  // ══════════════════════════════════════════════════════════════════════
  group('dönem dizisi grafik sekmesiyle hizalı', () {
    test('sıra ve etiketler _periods ile birebir', () {
      expect(
        SummaryPeriod.values.map((e) => e.label).toList(),
        ['GÜNLÜK', '1H', '1A', '6A', '1Y'],
        reason: 'iki sekme tek _selectedPeriodIdx paylaşıyor — sıra kayarsa '
            'Grafik\'te 6A seçen kullanıcı Özet\'te başka pencere görür',
      );
      expect(SummaryPeriod.values.map((e) => e.days).toList(),
          [0, 7, 30, 180, 365]);
      expect(SummaryPeriod.values.length, 5,
          reason: '3A EKLENMEYECEK — kilitli karar');
    });

    test('fromIndex sınır dışını kırpar', () {
      expect(SummaryPeriod.fromIndex(0), SummaryPeriod.gunluk);
      expect(SummaryPeriod.fromIndex(4), SummaryPeriod.birYil);
      expect(SummaryPeriod.fromIndex(99), SummaryPeriod.birYil);
      expect(SummaryPeriod.fromIndex(-1), SummaryPeriod.gunluk);
    });

    test('yalnızca GÜNLÜK intraday', () {
      expect(SummaryPeriod.gunluk.intraday, isTrue);
      for (final p in SummaryPeriod.values.skip(1)) {
        expect(p.intraday, isFalse);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // En iyi / en zayıf varlık
  // ══════════════════════════════════════════════════════════════════════
  group('dönemin en iyi / en zayıf varlığı', () {
    test('DÖNEME ait yüzde ölçülür, ömürlük getiri değil', () {
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 9, 6);
      final total = _gunluk(
        bas: bas,
        gunSayisi: 8,
        deger: (i) => 100000.0 + i * 1000,
      );

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: const [],
        breakdown: _bd(
          total,
          byPosition: {
            'hisse|AAA|TRY': _gunluk(
                bas: bas, gunSayisi: 8, deger: (i) => 50000.0 + i * 1500),
            'hisse|BBB|TRY': _gunluk(
                bas: bas, gunSayisi: 8, deger: (i) => 50000.0 - i * 500),
          },
        ),
        now: now,
        etiket: (k) => k.split('|')[1],
      );

      expect(s.enIyi?.name, 'AAA');
      expect(s.enZayif?.name, 'BBB');
      expect(s.enZayif!.changePct, lessThan(0));

      // Yüzde, PENCEREYE düşen uçlardan ölçülür — serinin tamamından
      // değil. Pencere 6 Eylül'de başlıyor, seri 7'sinde; ayrıca `now`
      // (13 Eyl 15:00) son günün 18:00 kapanışını dışarıda bırakıyor.
      // Elle yazılmış bir beklenti bu kırpmayı sessizce yanlış kilitler,
      // o yüzden aynı uç kuralından türetilir.
      final u = PeriodSummaryService.uclar(
        _gunluk(bas: bas, gunSayisi: 8, deger: (i) => 50000.0 + i * 1500),
        fromMs: s.start.millisecondsSinceEpoch,
        toMs: s.end.millisecondsSinceEpoch,
      )!;
      expect(s.enIyi!.changePct, closeTo((u.last / u.first - 1) * 100, 0.0001));
      expect(s.enIyi!.changePct, greaterThan(0));
    });

    test('dönem içinde ALIM görmüş pozisyon yarıştan ELENİR', () {
      // Miktar artışı serinin zıplamasına yol açar; o zıplama getiri
      // sanılırsa yanlış bir şampiyon ilan edilir.
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 9, 6);

      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: [
          _lot(
            id: 'yeni',
            qty: 100,
            cur: 100,
            purchase: 100,
            ticker: 'AAA',
            added: DateTime(2026, 9, 9),
          ),
        ],
        breakdown: _bd(
          _gunluk(bas: bas, gunSayisi: 8, deger: (i) => 100000.0 + i * 1000),
          byPosition: {
            // Alım yüzünden %200 "artmış" görünen pozisyon.
            'hisse|AAA|TRY': _gunluk(
                bas: bas,
                gunSayisi: 8,
                deger: (i) => i < 3 ? 10000.0 : 30000.0),
            'hisse|BBB|TRY': _gunluk(
                bas: bas, gunSayisi: 8, deger: (i) => 50000.0 + i * 300),
          },
        ),
        now: now,
        etiket: (k) => k.split('|')[1],
      );

      expect(s.enIyi?.name, 'BBB',
          reason: 'AAA alım gördü — %200 zıplaması getiri DEĞİL, elenmeli');
    });

    test('hepsi artıdaysa enZayif null — azarlama yok', () {
      final now = DateTime(2026, 9, 13, 15);
      final bas = DateTime(2026, 9, 6);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: const [],
        breakdown: _bd(
          _gunluk(bas: bas, gunSayisi: 8, deger: (i) => 100000.0 + i * 1000),
          byPosition: {
            'hisse|AAA|TRY': _gunluk(
                bas: bas, gunSayisi: 8, deger: (i) => 50000.0 + i * 1500),
            'hisse|BBB|TRY': _gunluk(
                bas: bas, gunSayisi: 8, deger: (i) => 50000.0 + i * 300),
          },
        ),
        now: now,
        etiket: (k) => k.split('|')[1],
      );
      expect(s.enIyi?.name, 'AAA');
      expect(s.enZayif, isNull,
          reason: 'kârdaki varlığı "en zayıfın" diye sunmak azarlamaktır');
    });

    test('tek noktalı pozisyon serisi değişim TAŞIMAZ', () {
      final now = DateTime(2026, 9, 13, 15);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: const [],
        breakdown: _bd(
          _gunluk(
              bas: DateTime(2026, 9, 6), gunSayisi: 8, deger: (i) => 100000.0),
          byPosition: {
            'hisse|AAA|TRY': {
              DateTime(2026, 9, 10, 18).millisecondsSinceEpoch: 50000.0,
            },
          },
        ),
        now: now,
        etiket: (k) => k.split('|')[1],
      );
      expect(s.enIyi, isNull);
      expect(s.enZayif, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // İşlem günü sayımı (1H bağlamı)
  // ══════════════════════════════════════════════════════════════════════
  group('artıda kapanan gün sayımı', () {
    test('5 işlem gününün 3\'ü artıda', () {
      final bas = DateTime(2026, 9, 7); // Pazartesi
      // 6 gün → 5 karşılaştırma. 3 artı, 2 eksi.
      final degerler = [100.0, 101.0, 100.5, 102.0, 101.0, 103.0];
      final total = _gunluk(
        bas: bas,
        gunSayisi: 6,
        deger: (i) => degerler[i] * 1000,
      );

      final sayim = PeriodSummaryService.gunSayimi(
        total,
        fromMs: DateTime(2026, 9, 6).millisecondsSinceEpoch,
        toMs: DateTime(2026, 9, 13, 23, 59, 59).millisecondsSinceEpoch,
      );

      expect(sayim?.toplam, 5);
      expect(sayim?.artida, 3);
    });

    test('tek gün varsa sayım null', () {
      expect(
        PeriodSummaryService.gunSayimi(
          {DateTime(2026, 9, 10, 18).millisecondsSinceEpoch: 100.0},
          fromMs: DateTime(2026, 9, 6).millisecondsSinceEpoch,
          toMs: DateTime(2026, 9, 13).millisecondsSinceEpoch,
        ),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Düz dönem — sıfır bir YÖN taşımaz
  // ══════════════════════════════════════════════════════════════════════
  group('düz dönem', () {
    test('hareket yoksa isFlat ve nötr cümle', () {
      final now = DateTime(2026, 9, 13, 15);
      final total = _gunluk(
        bas: DateTime(2026, 8, 14),
        gunSayisi: 31,
        deger: (i) => 100000.0,
      );
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: const [],
        breakdown: _bd(total),
        now: now,
      );
      expect(s.isFlat, isTrue);
      expect(s.isNegative, isFalse,
          reason: 'sıfır YÖN taşımaz — kırmızı gösterilmemeli');
      expect(PeriodSummaryService.tonCumlesi(s), 'Bu ay piyasa hareketi yok.');
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // flowOf — tek kaynak, DailySummary ile aynı işaret kuralı
  // ══════════════════════════════════════════════════════════════════════
  group('flowOf işaret kuralı', () {
    test('alım +, satış −, silinen ve temettü 0', () {
      final alim = _lot(
          id: 'a',
          qty: 10,
          cur: 100,
          purchase: 90,
          added: DateTime(2026, 9, 1));
      expect(PeriodSummaryService.flowOf(alim), alim.totalCostTRY);
      expect(PeriodSummaryService.flowOf(alim), greaterThan(0));

      final satis = _lot(
        id: 's',
        qty: 10,
        cur: 100,
        purchase: 90,
        sellPrice: 110,
        kind: AssetKind.sell,
        added: DateTime(2026, 9, 1),
      );
      expect(PeriodSummaryService.flowOf(satis), -satis.sellProceedsTRY);
      expect(PeriodSummaryService.flowOf(satis), lessThan(0));

      final temettu = _lot(
        id: 'd',
        qty: 0,
        cur: 100,
        kind: AssetKind.dividend,
        added: DateTime(2026, 9, 1),
      );
      expect(PeriodSummaryService.flowOf(temettu), 0,
          reason: 'temettü miktara girmez — akışa da girmez');
    });

    test('netInflow DailySummary.inflowOnDay ile aynı sonucu verir', () {
      // İki katman aynı kuralı kullanmak ZORUNDA (daily_summary.dart
      // "Değişmezler"). Ayrışırlarsa günlük ve dönemsel rakam çelişir.
      final gun = DateTime(2026, 9, 10);
      final assets = [
        _lot(
            id: 'a',
            qty: 10,
            cur: 100,
            purchase: 100,
            added: DateTime(2026, 9, 10, 11)),
        _lot(
          id: 's',
          qty: 5,
          cur: 100,
          purchase: 90,
          sellPrice: 120,
          kind: AssetKind.sell,
          added: DateTime(2026, 9, 10, 15),
        ),
        // Pencere dışı.
        _lot(
            id: 'b',
            qty: 10,
            cur: 100,
            purchase: 100,
            added: DateTime(2026, 9, 9, 11)),
      ];

      expect(
        PeriodSummaryService.netInflow(assets, gun, gun),
        DailySummary.inflowOnDay(
          assets,
          DateTime(2026, 9, 10),
          DateTime(2026, 9, 10, 23, 59, 59),
        ),
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // Paylaşım metni — TUTAR İÇERMEZ kuralı ikinci çağıranda da geçerli
  // ══════════════════════════════════════════════════════════════════════
  group('paylaşım metni', () {
    PeriodSummary ozet({
      SummaryPeriod period = SummaryPeriod.birAy,
      double? pct = 2.72,
      double? tufe,
    }) =>
        PeriodSummary(
          period: period,
          start: DateTime(2026, 8, 14),
          end: DateTime(2026, 9, 13),
          // Bilerek BÜYÜK tutarlar: metne sızarlarsa test yakalar.
          baslangicTRY: 2489186,
          sonTRY: 2685684,
          katkiTRY: 120000,
          piyasaTRY: 76498,
          getiriPct: pct,
          tufeFarki: tufe,
        );

    test('TUTAR İÇERMEZ — dört haneli sayı yok', () {
      // `recap_service_test`'teki aynı iddia, ikinci çağıran için.
      // Tutarlı bir kart paylaşılmaz; tutarsız kart paylaşılır.
      final metin = PeriodSummaryService.shareText(ozet(tufe: 6.4))!;

      expect(metin.contains('₺'), isFalse);
      expect(metin.contains('2489186'), isFalse);
      expect(metin.contains('2.489'), isFalse);
      expect(metin.contains('120'), isFalse);
      expect(RegExp(r'\d{4,}').hasMatch(metin), isFalse,
          reason: 'dört haneli sayı tutar demektir — başlıkta tarih '
              'aralığı da bu yüzden YOK');
    });

    test('yüzde SAF PİYASA getirisi olarak etiketlenir', () {
      final metin = PeriodSummaryService.shareText(ozet())!;
      expect(metin.contains('Piyasa getirim: +%2,7'), isTrue,
          reason: 'katkının şişirdiği rakamı "getirim" diye paylaşmak '
              'ekranın tüm mesajını tersine çevirirdi');
    });

    test('dönem adı başlıkta geçer', () {
      expect(PeriodSummaryService.shareText(ozet())!.contains('Bu ay'), isTrue);
      expect(
        PeriodSummaryService.shareText(ozet(period: SummaryPeriod.birYil))!
            .contains('Bu yıl'),
        isTrue,
      );
    });

    test('ölçülebilir yüzde yoksa null — buton çizilmez', () {
      expect(PeriodSummaryService.shareText(ozet(pct: null)), isNull,
          reason: 'içinde tek bir sayı olmayan kart paylaşılmaz');
    });

    test('kayıp döneminde işaret − ve kutlama dili yok', () {
      final metin = PeriodSummaryService.shareText(ozet(pct: -11.5))!;
      expect(metin.contains('−%11,5'), isTrue);
      for (final k in ['Tebrikler', 'Harika', '🎉', '🔥', 'Devam']) {
        expect(metin.contains(k), isFalse, reason: '"$k" paylaşımda olmamalı');
      }
    });

    test('TÜFE yoksa o satır hiç yazılmaz', () {
      final metin = PeriodSummaryService.shareText(ozet())!;
      expect(metin.contains('Enflasyonun'), isFalse);
      final ileTufe = PeriodSummaryService.shareText(ozet(tufe: 6.4))!;
      expect(ileTufe.contains('Enflasyonun 6,4 puan önündeyim'), isTrue);
    });

    test('karakter verilirse etiketi geçer, verilmezse satır yok', () {
      expect(
        PeriodSummaryService.shareText(ozet(),
                karakter: PortfolioCharacter.altinci)!
            .contains('Altıncı'),
        isTrue,
      );
      expect(PeriodSummaryService.shareText(ozet())!.contains('—'), isFalse,
          reason: 'karakter yoksa tagline ayıracı da olmamalı');
    });

    test('composeShareText TRY alanı KABUL ETMEZ', () {
      // Yapısal koruma: imzada tutar taşıyan parametre yok, dolayısıyla
      // çağıran taraf yanlışlıkla tutar geçemiyor. Bu test o imzanın
      // genişletilmediğini kilitler.
      final metin = RecapService.composeShareText(
        baslik: 'sandık · Bu ay',
        degisimPct: 2.72,
      );
      expect(metin.startsWith('sandık · Bu ay'), isTrue);
      expect(metin.endsWith('sandık ile takip ediyorum'), isTrue);
      expect(RegExp(r'\d{4,}').hasMatch(metin), isFalse);
    });
  });
}
