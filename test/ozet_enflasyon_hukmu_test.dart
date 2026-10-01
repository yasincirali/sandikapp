import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/inflation_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/real_return_service.dart';
import 'package:portfoy_takip/services/recap_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Özet › 1A / 1Y "enflasyonu yendim mi?" — uçtan uca, ELLE HESAPLI örnekler.
///
/// ## Neden bu dosya (yasin, 2026-10-01)
/// *"Benim kümülatif yatırımım enflasyonu yenmiş mi altında mı kalmış bunu
/// görmeliyim … burasını pushla göstercez, kesinlikle doğru olmalı."*
///
/// Zincir, üretimdeki sırayla:
///   1. `InflationService.pencere(30 | 365, now)` → hangi ayın TÜFE'si, hangi
///      uçlar (`seriBaslangici` / `seriBitisi`).
///   2. `RealReturnService.piyasaGetirisi` → `PeriodSummaryService.compute(
///      now: seriBitisi, pencereBaslangici: seriBaslangici)` → nominal
///      (Modified Dietz: piyasa ₺ / ortalama sermaye).
///   3. `RealReturn` → puan farkı ve bileşik reel getiri.
///   4. `PeriodSummaryView` › reel getiri kartı → kullanıcının okuduğu hüküm.
///
/// 2. adımın ağ kısmı (`HistoryService`) burada [_motor] ile taklit edilir:
/// motorun kuralı birebir — slot günün 00:00'ı (haftalıkta pazartesi),
/// slottaki miktar `addedDate <= slot` olan lotlar, değer miktar × o slotun
/// fiyatı. Beklenen değerler testten BAĞIMSIZ hesaplandı (Python, aynı
/// formül) ve her örneğin yanında elle yazılı.
void main() {
  DateTime ay(int y, int m) => DateTime(y, m, 1);

  setUp(() => InflationService.instance.resetForTest());
  tearDown(() => InflationService.instance.resetForTest());

  // ── 1. Hangi ayın TÜFE'si? ──────────────────────────────────────────────
  group('TÜFE ayı hizası (1A ve 1Y)', () {
    // Tablo, 1 Ekim 2026 sabahının gerçek durumu: son açıklanan ay Ağustos.
    Map<DateTime, double> agustosaKadar() => {
          for (var i = 0; i <= 13; i++)
            DateTime(2025, 7 + i, 1): 100.0 * (1 + 0.02 * i),
        };

    test('1 Ekim (Eylül TÜFE\'si yok): 1A = AĞUSTOS, 31 Tem → 31 Ağu',
        () async {
      InflationService.instance.seedForTest(agustosaKadar());
      final w = (await InflationService.instance
          .pencere(30, now: DateTime(2026, 10, 1, 9, 30)))!;
      expect(w.sonAy, ay(2026, 8));
      expect(w.ilkAy, ay(2026, 7));
      expect(w.ayAdedi, 1);
      expect(w.seriBaslangici, DateTime(2026, 7, 31));
      expect(w.seriBitisi, DateTime(2026, 8, 31));
      // Endeks Tem 2026 = 100×1,24, Ağu 2026 = 100×1,26 → 1,26/1,24 − 1.
      expect(w.pct, closeTo((1.26 / 1.24 - 1) * 100, 1e-9));
    });

    test('3 Ekim 10:05 öncesi hâlâ Ağustos; Eylül satırı gelince Eylül',
        () async {
      final tablo = agustosaKadar();
      InflationService.instance.seedForTest(tablo);
      final once = (await InflationService.instance
          .pencere(30, now: DateTime(2026, 10, 3, 9, 0)))!;
      expect(once.sonAy, ay(2026, 8));

      // fetch-inflation 10:05'te Eylül'ü yazdı.
      InflationService.instance
          .seedForTest({...tablo, ay(2026, 9): 128.5});
      final sonra = (await InflationService.instance
          .pencere(30, now: DateTime(2026, 10, 3, 10, 30)))!;
      expect(sonra.sonAy, ay(2026, 9));
      expect(sonra.seriBaslangici, DateTime(2026, 8, 31));
      expect(sonra.seriBitisi, DateTime(2026, 9, 30));
      expect(sonra.pct, closeTo((128.5 / 126 - 1) * 100, 1e-9));
    });

    test('1Y: Ağu 2025 → Ağu 2026 (TÜİK yıllık), 31 Ağu → 31 Ağu', () async {
      InflationService.instance.seedForTest(agustosaKadar());
      final w = (await InflationService.instance
          .pencere(365, now: DateTime(2026, 10, 1)))!;
      expect(w.ilkAy, ay(2025, 8));
      expect(w.sonAy, ay(2026, 8));
      expect(w.ayAdedi, 12);
      expect(w.seriBaslangici, DateTime(2025, 8, 31));
      expect(w.seriBitisi, DateTime(2026, 8, 31));
      // Ağu 2025 = 102, Ağu 2026 = 126 → %23,529…
      expect(w.pct, closeTo((126 / 102 - 1) * 100, 1e-9));
    });

    test('1A yüzdesi push\'un "aylık TÜFE"siyle AYNI sayı', () async {
      // Push başlığı (monthlyInflation) ile Özet kartı aynı ayı, aynı
      // sayıyı söylemeli.
      InflationService.instance.seedForTest(agustosaKadar());
      final now = DateTime(2026, 10, 3, 10, 30);
      final w = await InflationService.instance.pencere(30, now: now);
      final aylik = await InflationService.instance.monthlyInflation(now: now);
      expect(w!.pct, aylik);
    });

    test('Özet dönemleri doğru AY sayısına çevrilir', () {
      // ozet_yan_veri: 1A → pencere(30), diğerleri → period.days.
      expect(InflationService.aySayisi(30), 1);
      expect(InflationService.aySayisi(SummaryPeriod.ucAy.days), 3);
      expect(InflationService.aySayisi(SummaryPeriod.altiAy.days), 6);
      expect(InflationService.aySayisi(SummaryPeriod.birYil.days), 12);
      expect(InflationService.aySayisi(SummaryPeriod.besYil.days), 60);
    });

    test('Şubat ölçümü: 31 Oca → 29 Şub (artık yıl), ay sonu kırpılır',
        () async {
      InflationService.instance
          .seedForTest({ay(2028, 1): 100.0, ay(2028, 2): 102.0});
      final w = (await InflationService.instance
          .pencere(30, now: DateTime(2028, 3, 5)))!;
      expect(w.seriBaslangici, DateTime(2028, 1, 31));
      expect(w.seriBitisi, DateTime(2028, 2, 29));
    });

    test('TÜFE iki aydan eskiyse kart YOK (uydurma ay gösterilmez)',
        () async {
      // 1 Kasım'da tablo hâlâ Ağustos'ta kaldıysa (çekim iki kez kaçtı):
      // 3 ay geride → bayat → null. Ekran "veri bekleniyor" der.
      InflationService.instance.seedForTest(agustosaKadar());
      expect(
          await InflationService.instance
              .pencere(30, now: DateTime(2026, 11, 1)),
          isNull);
      expect(
          await InflationService.instance
              .pencere(30, now: DateTime(2026, 10, 31)),
          isNotNull);
    });

    test('1Y\'nin taban ayı tabloda yoksa kart YOK', () async {
      InflationService.instance
          .seedForTest({ay(2026, 7): 120.0, ay(2026, 8): 122.0});
      expect(
          await InflationService.instance
              .pencere(365, now: DateTime(2026, 10, 1)),
          isNull);
    });
  });

  // ── 2. Önbellek: push'a dokunulduğunda yeni ay görünmeli ────────────────
  group('TÜFE önbelleği ayın 3\'ünde eski ayı tutmaz', () {
    final agustos = {ay(2026, 7): 124.0, ay(2026, 8): 126.0};
    final eylul = {...agustos, ay(2026, 9): 128.5};

    test('3 Ekim 09:00\'da çekilen tablo 10:30\'da TAZE SAYILMAZ', () {
      // Eskiden 12 saat geçerliydi: 09:00'da açan kullanıcı 10:30
      // push'una dokunduğunda Eylül yerine Ağustos'u görüyordu.
      expect(
          InflationService.onbellekTaze(
            endeks: agustos,
            cekildi: DateTime(2026, 10, 3, 9, 0),
            simdi: DateTime(2026, 10, 3, 10, 30),
          ),
          isFalse);
    });

    test('beklenen ay eksikken yarım saat içinde tekrar sorulmaz', () {
      expect(
          InflationService.onbellekTaze(
            endeks: agustos,
            cekildi: DateTime(2026, 10, 3, 10, 0),
            simdi: DateTime(2026, 10, 3, 10, 20),
          ),
          isTrue);
    });

    test('yeni ay geldiyse 12 saat geçerli', () {
      expect(
          InflationService.onbellekTaze(
            endeks: eylul,
            cekildi: DateTime(2026, 10, 3, 10, 30),
            simdi: DateTime(2026, 10, 3, 21, 0),
          ),
          isTrue);
      expect(
          InflationService.onbellekTaze(
            endeks: eylul,
            cekildi: DateTime(2026, 10, 3, 10, 30),
            simdi: DateTime(2026, 10, 4, 0, 0),
          ),
          isFalse);
    });

    test('ay ortası: önceki ay tabloda → 12 saat', () {
      expect(
          InflationService.onbellekTaze(
            endeks: eylul,
            cekildi: DateTime(2026, 10, 15, 8, 0),
            simdi: DateTime(2026, 10, 15, 19, 0),
          ),
          isTrue);
    });

    test('boş/çekilmemiş önbellek taze değil', () {
      expect(
          InflationService.onbellekTaze(
              endeks: null, cekildi: null, simdi: DateTime(2026, 10, 3)),
          isFalse);
    });
  });

  // ── 3. Nominal getiri: 1A (Ağustos), elle hesaplı ───────────────────────
  //
  // Ortak senaryo: 100 adet hisse, 1 Tem'de alınmış. Fiyat 31 Tem–15 Ağu
  // 100 ₺, 16–30 Ağu 102 ₺, 31 Ağu [son]. Ağustos TÜFE'si %2,50
  // (endeks 100 → 102,5). Pencere 31 Tem 00:00 → 31 Ağu 00:00 (31 gün).
  group('1A nominal ve hüküm (Ağustos TÜFE %2,50)', () {
    final w = InflationWindow(ilkAy: ay(2026, 7), sonAy: ay(2026, 8), pct: 2.5);

    double Function(DateTime) fiyat(double son) => (d) {
          if (d.isBefore(DateTime(2026, 8, 16))) return 100;
          if (d.isBefore(DateTime(2026, 8, 31))) return 102;
          return son;
        };

    final ilkLot = _lot('ilk', 100, DateTime(2026, 7, 1, 10), alis: 95);

    test('akış yok, +%3,00 → enflasyonu YENDİ (+0,5 puan, reel +%0,49)',
        () {
      final r = _hizali([ilkLot], w, fiyat(103));
      expect(r.ozet.baslangicTRY, 10000);
      expect(r.ozet.sonTRY, 10300);
      expect(r.ozet.katkiTRY, 0);
      expect(r.ozet.piyasaTRY, 300);
      expect(r.nominal, closeTo(3.0, 1e-9));
      expect(r.puan, closeTo(0.5, 1e-9));
      // 1,03 / 1,025 − 1 = %0,487805
      expect(r.reel, closeTo(0.487805, 1e-6));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.ustunde);
    });

    test('akış yok, +%1,50 → ALTINDA KALDI (−1,0 puan, reel −%0,98)', () {
      final r = _hizali([ilkLot], w, fiyat(101.5));
      expect(r.nominal, closeTo(1.5, 1e-9));
      expect(r.puan, closeTo(-1.0, 1e-9));
      // 1,015 / 1,025 − 1 = −%0,975610
      expect(r.reel, closeTo(-0.975610, 1e-6));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.altinda);
    });

    test('akış yok, tam %2,50 → BAŞA BAŞ (yön söylenmez)', () {
      final r = _hizali([ilkLot], w, fiyat(102.5));
      expect(r.nominal, closeTo(2.5, 1e-9));
      expect(r.reel.abs(), lessThan(1e-9));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.basaBas);
    });

    test('negatif ay −%5,00 → ALTINDA (−7,5 puan, reel −%7,32)', () {
      final r = _hizali([ilkLot], w, fiyat(95));
      expect(r.ozet.piyasaTRY, -500);
      expect(r.nominal, closeTo(-5.0, 1e-9));
      expect(r.puan, closeTo(-7.5, 1e-9));
      // 0,95 / 1,025 − 1 = −%7,317073
      expect(r.reel, closeTo(-7.317073, 1e-6));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.altinda);
    });

    test('ay ortası ALIM: eklenen para getiri sayılmaz, yüzde %2,7030', () {
      // 16 Ağu 10:00'da 100 adet × 102 ₺ = ₺10.200 eklendi.
      //   son = 200 × 103 = ₺20.600, katkı ₺10.200
      //   piyasa = 20.600 − 10.000 − 10.200 = ₺400
      //   ağırlık = (31 Ağu 00:00 − 16 Ağu 10:00) / 31 gün = 14,5833/31
      //   ortalama sermaye = 10.000 + 10.200 × 0,470430 = ₺14.798,39
      //   nominal = 400 / 14.798,39 = %2,702997
      final r = _hizali([
        ilkLot,
        _lot('ek', 100, DateTime(2026, 8, 16, 10), alis: 102),
      ], w, fiyat(103));
      expect(r.ozet.sonTRY, 20600);
      expect(r.ozet.katkiTRY, 10200);
      expect(r.ozet.piyasaTRY, closeTo(400, 1e-6));
      expect(r.nominal, closeTo(2.702997, 1e-5));
      expect(r.puan, closeTo(0.202997, 1e-5));
      expect(r.reel, closeTo(0.198046, 1e-5));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.ustunde);
    });

    test('ay ortası SATIŞ: çekilen para kayıp sayılmaz, yüzde %3,2891', () {
      // 16 Ağu 10:00'da 50 adet 102 ₺'dan satıldı → ₺5.100 çıktı.
      //   son = 50 × 103 = ₺5.150, katkı −₺5.100
      //   piyasa = 5.150 − 10.000 + 5.100 = ₺250
      //   ortalama sermaye = 10.000 − 5.100 × 0,470430 = ₺7.600,81
      //   nominal = 250 / 7.600,81 = %3,289125
      final r = _hizali([
        ilkLot,
        _lot('satis', 50, DateTime(2026, 8, 16, 10),
            alis: 95, kind: AssetKind.sell, satis: 102),
      ], w, fiyat(103));
      expect(r.ozet.sonTRY, 5150);
      expect(r.ozet.katkiTRY, -5100);
      expect(r.ozet.piyasaTRY, closeTo(250, 1e-6));
      expect(r.nominal, closeTo(3.289125, 1e-5));
      expect(r.reel, closeTo(0.769878, 1e-5));
    });

    test('AYIN SON GÜNÜ alım ölçümü bozmaz: yine %3,00', () {
      // 31 Ağu 14:00 alımı ölçüm ANINDAN (31 Ağu 00:00) sonra: ne değerde
      // ne katkıda. Eskiden katkıya girip ayı −%31 gösteriyordu.
      final r = _hizali([
        ilkLot,
        _lot('songun', 100, DateTime(2026, 8, 31, 14), alis: 103),
      ], w, fiyat(103));
      expect(r.ozet.sonTRY, 10300);
      expect(r.ozet.katkiTRY, 0);
      expect(r.nominal, closeTo(3.0, 1e-9));
    });

    test('sondan bir önceki gün alım: tam sayılır, ağırlığı ~0 (%3,9459)',
        () {
      // 30 Ağu 14:00, 100 × 102 ₺. Son slotta (31 Ağu) değerin içinde.
      //   piyasa = 20.600 − 10.000 − 10.200 = ₺400
      //   ağırlık = 10 saat / 744 saat = 0,013441
      //   sermaye = 10.000 + 10.200 × 0,013441 = ₺10.137,10
      //   nominal = 400 / 10.137,10 = %3,945903
      final r = _hizali([
        ilkLot,
        _lot('ondan', 100, DateTime(2026, 8, 30, 14), alis: 102),
      ], w, fiyat(103));
      expect(r.ozet.katkiTRY, 10200);
      expect(r.nominal, closeTo(3.945903, 1e-5));
    });

    test('yüzdenin işareti HER ZAMAN ₺ piyasa satırınınki', () {
      for (final son in [90.0, 99.0, 100.5, 103.0, 110.0]) {
        final r = _hizali([
          ilkLot,
          _lot('ek', 100, DateTime(2026, 8, 16, 10), alis: 102),
          _lot('satis', 30, DateTime(2026, 8, 20, 10),
              alis: 95, kind: AssetKind.sell, satis: 102),
        ], w, fiyat(son));
        expect(r.nominal.sign, r.ozet.piyasaTRY!.sign, reason: 'son=$son');
      }
    });
  });

  // ── 4. Nominal getiri: 1Y (haftalık seri), elle hesaplı ─────────────────
  //
  // TÜFE Ağu 2025 → Ağu 2026 %31,51. Pencere 31 Ağu 2025 → 31 Ağu 2026.
  // `pickForSpan(365)` HAFTALIK: slotlar pazartesi; ilk ölçüm 1 Eyl 2025
  // (k=0), son ölçüm 31 Ağu 2026 (k=52).
  group('1Y nominal ve hüküm (yıllık TÜFE %31,51)', () {
    final w =
        InflationWindow(ilkAy: ay(2025, 8), sonAy: ay(2026, 8), pct: 31.51);
    final k0 = DateTime(2025, 9, 1);
    int hafta(DateTime d) => d.difference(k0).inDays ~/ 7;

    final ilkLot = _lot('ilk', 1000, DateTime(2025, 6, 1, 10), alis: 60);

    test('akış yok, her hafta +%0,55 → %33,00 → YENDİ (+1,5 puan)', () {
      // 1,0055^52 − 1 = %33,004978
      final r = _hizali([ilkLot], w,
          (d) => 100 * _us(1.0055, hafta(d)), haftalik: true);
      expect(r.ozet.baslangicTRY, closeTo(100000, 1e-6));
      expect(r.nominal, closeTo(33.004978, 1e-5));
      expect(r.puan, closeTo(1.494978, 1e-5));
      // 1,33004978 / 1,3151 − 1 = %1,136779
      expect(r.reel, closeTo(1.136779, 1e-5));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.ustunde);
    });

    test('yıl boyu her ayın 15\'i 10 adet alım (DCA) → %32,9431', () {
      // 12 alım × 10 adet, alış fiyatı o haftanın fiyatı (Python ile):
      //   baş ₺100.000, son 1.120 × 133,005 = ₺148.965,58
      //   katkı ₺13.841,17, piyasa ₺35.124,41
      //   ortalama sermaye ₺106.621,48 → nominal %32,943085
      double fiyat(DateTime d) => 100 * _us(1.0055, hafta(d));
      final lotlar = [ilkLot];
      for (var m = 0; m < 12; m++) {
        final t = DateTime(2025, 9 + m, 15, 12);
        final slot = k0.add(Duration(days: 7 * hafta(t)));
        lotlar.add(_lot('dca$m', 10, t, alis: fiyat(slot)));
      }
      final r = _hizali(lotlar, w, fiyat, haftalik: true);
      expect(r.ozet.katkiTRY, closeTo(13841.170399, 1e-4));
      expect(r.ozet.piyasaTRY, closeTo(35124.405242, 1e-4));
      expect(r.nominal, closeTo(32.943085, 1e-5));
      expect(r.puan, closeTo(1.433085, 1e-5));
      expect(r.reel, closeTo(1.089715, 1e-5));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.ustunde);
    });

    test('negatif yıl −%20 → ALTINDA (−51,51 puan, reel −%39,17)', () {
      final r = _hizali([ilkLot], w, (d) => 100 - 20 * hafta(d) / 52,
          haftalik: true);
      expect(r.nominal, closeTo(-20.0, 1e-9));
      expect(r.puan, closeTo(-51.51, 1e-9));
      // 0,80 / 1,3151 − 1 = −%39,168124
      expect(r.reel, closeTo(-39.168124, 1e-5));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.altinda);
    });

    test('tam %31,51 → BAŞA BAŞ (kayan nokta −7e−15 "altında" demez)', () {
      final r = _hizali([ilkLot], w,
          (d) => 100 * _us(1.3151, hafta(d) / 52), haftalik: true);
      expect(r.nominal, closeTo(31.51, 1e-9));
      expect(InflationService.hukum(r.reel), EnflasyonHukmu.basaBas);
    });

    test('DÖNEM getirisidir, ömürlük değil: 2 yıl önceki kâr sayılmaz', () {
      // Lot 60 ₺'dan alınmış; pencere başında 100, sonunda 133. Ömürlük
      // kazanç %121 ama 1Y sorusu "son 12 ayda" — %33.
      final r = _hizali([ilkLot], w,
          (d) => 100 * _us(1.0055, hafta(d)), haftalik: true);
      expect(ilkLot.purchasePrice, 60);
      expect(r.nominal, closeTo(33.004978, 1e-5));
    });
  });

  // ── 5. Bileşik reel getiri ile puan farkı aynı yönü söyler ──────────────
  test('reel getiri ve puan farkı her zaman AYNI hükmü verir', () {
    for (final n in [-60.0, -5.0, 0.0, 1.0, 2.49, 2.5, 2.51, 31.51, 80.0]) {
      for (final e in [0.5, 1.84, 2.5, 31.51, 75.0]) {
        final reel = InflationService.realReturnPct(n, e);
        final puan = InflationService.spreadPoints(n, e);
        if (puan.abs() < 1e-9) continue;
        expect(reel.sign, puan.sign, reason: 'n=$n e=$e');
      }
    }
  });

  test('hüküm eşiği ekranda görünen sayıdır (%0,00 → başa baş)', () {
    expect(InflationService.hukum(0.0), EnflasyonHukmu.basaBas);
    expect(InflationService.hukum(0.0049), EnflasyonHukmu.basaBas);
    expect(InflationService.hukum(-0.0049), EnflasyonHukmu.basaBas);
    expect(InflationService.hukum(0.005), EnflasyonHukmu.ustunde);
    expect(InflationService.hukum(-0.005), EnflasyonHukmu.altinda);
  });

  // ── 6. Kullanıcının okuduğu metin ───────────────────────────────────────
  group('Özet kartı: kullanıcının gördüğü hüküm', () {
    PeriodSummary ozet(SummaryPeriod p, _Sonuc r) => PeriodSummary(
          period: p,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 10, 1),
          baslangicTRY: r.ozet.baslangicTRY,
          sonTRY: r.ozet.sonTRY,
          katkiTRY: r.ozet.katkiTRY,
          piyasaTRY: r.ozet.piyasaTRY,
          getiriPct: r.nominal,
          // `_OzetYanVeri._tufeIle` ile aynı alanlar.
          tufeFarki: r.puan,
          tufePct: r.w.pct,
          reelGetiriPct: r.reel,
          tufeNominalPct: r.nominal,
          tufeBaslangic: r.w.seriBaslangici,
          tufeBitis: r.w.seriBitisi,
        );

    Future<void> kur(WidgetTester t, PeriodSummary s) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [SandikPalette.light]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: SingleChildScrollView(child: PeriodSummaryView(summary: s)),
        ),
      ));
      await t.pumpAndSettle();
    }

    final agustos =
        InflationWindow(ilkAy: ay(2026, 7), sonAy: ay(2026, 8), pct: 2.5);
    final yil =
        InflationWindow(ilkAy: ay(2025, 8), sonAy: ay(2026, 8), pct: 31.51);
    final ilk = _lot('ilk', 100, DateTime(2025, 6, 1, 10), alis: 95);
    double Function(DateTime) aylikFiyat(double son) =>
        (d) => d.isBefore(DateTime(2026, 8, 31)) ? 100 : son;

    testWidgets('1A yendi: ▲ %0,49 · Ağustos 2026 · +%3,00 / %2,50 / +0,5',
        (t) async {
      await kur(t,
          ozet(SummaryPeriod.birAy, _hizali([ilk], agustos, aylikFiyat(103))));
      expect(find.text('Reel getiri · Ağustos 2026'), findsOneWidget);
      expect(find.text('▲'), findsWidgets);
      expect(find.text('%0,49'), findsOneWidget);
      expect(
          find.text(
              'Portföyün enflasyonun üzerinde reel getiri sağladı, alım gücün arttı.'),
          findsOneWidget);
      expect(find.text('+%3,00'), findsWidgets);
      expect(find.text('%2,50'), findsOneWidget);
      expect(find.text('+0,5 puan'), findsOneWidget);
      expect(find.text('Ölçülen ay: Ağustos 2026'), findsOneWidget);
      expect(find.textContaining('alım gücün geriledi'), findsNothing);
    });

    testWidgets('1A altında: ▼ %0,98 · −1,0 puan · "alım gücün geriledi"',
        (t) async {
      await kur(t,
          ozet(SummaryPeriod.birAy, _hizali([ilk], agustos, aylikFiyat(101.5))));
      expect(find.text('▼'), findsWidgets);
      expect(find.text('%0,98'), findsOneWidget);
      expect(
          find.text('Portföyün enflasyonun altında kaldı, alım gücün geriledi.'),
          findsOneWidget);
      expect(find.text('−1,0 puan'), findsOneWidget);
      expect(find.textContaining('alım gücün arttı'), findsNothing);
    });

    testWidgets('1A başa baş: "=" %0,00 · 0,0 puan · "alım gücün korundu"',
        (t) async {
      await kur(t,
          ozet(SummaryPeriod.birAy, _hizali([ilk], agustos, aylikFiyat(102.5))));
      expect(find.text('='), findsOneWidget);
      expect(find.text('%0,00'), findsOneWidget);
      expect(
          find.text(
              'Portföyün enflasyonla aynı oranda değerlendi, alım gücün korundu.'),
          findsOneWidget);
      expect(find.text('0,0 puan'), findsOneWidget);
      expect(find.textContaining('alım gücün arttı'), findsNothing);
      expect(find.textContaining('alım gücün geriledi'), findsNothing);
    });

    testWidgets('1Y yendi: "son 1 yıl" · Ağustos 2025 - Ağustos 2026',
        (t) async {
      final k0 = DateTime(2025, 9, 1);
      final r = _hizali(
          [ilk], yil, (d) => 100 * _us(1.0055, d.difference(k0).inDays ~/ 7),
          haftalik: true);
      await kur(t, ozet(SummaryPeriod.birYil, r));
      expect(find.text('Reel getiri · son 1 yıl'), findsOneWidget);
      expect(find.text('%1,14'), findsOneWidget);
      expect(find.text('+%33,00'), findsWidgets);
      expect(find.text('%31,51'), findsOneWidget);
      expect(find.text('+1,5 puan'), findsOneWidget);
      expect(find.text('Ölçüm aralığı: Ağustos 2025 - Ağustos 2026'),
          findsOneWidget);
      expect(find.textContaining('alım gücün arttı'), findsOneWidget);
    });

    testWidgets('1Y başa baş: kayan nokta "altında kaldı" yazdırmaz',
        (t) async {
      final k0 = DateTime(2025, 9, 1);
      final r = _hizali([ilk], yil,
          (d) => 100 * _us(1.3151, (d.difference(k0).inDays ~/ 7) / 52),
          haftalik: true);
      await kur(t, ozet(SummaryPeriod.birYil, r));
      expect(find.textContaining('alım gücün korundu'), findsOneWidget);
      expect(find.textContaining('alım gücün geriledi'), findsNothing);
      expect(find.text('▼'), findsNothing);
    });
  });

  group('paylaşım metni de aynı hükmü verir', () {
    String? metin(double puan, double reel) =>
        RecapService.composeShareText(
          baslik: 'sandık · Bu ay',
          degisimPct: 2.5,
          degisimEtiketi: 'Piyasa getirim',
          enflasyonPuan: puan,
          reelGetiriPct: reel,
        );

    test('önde / geride / başa baş', () {
      expect(metin(0.5, 0.49), contains('Enflasyonun 0,5 puan önündeyim'));
      expect(metin(-1.0, -0.98), contains('Enflasyonun 1,0 puan gerisindeyim'));
      final esit = metin(-0.00000001, -0.0000001)!;
      expect(esit, contains('Enflasyonla başa başım'));
      expect(esit, isNot(contains('gerisindeyim')));
    });
  });
}

double _us(double taban, num us) => math.pow(taban, us).toDouble();

Asset _lot(
  String id,
  double qty,
  DateTime added, {
  required double alis,
  AssetKind kind = AssetKind.buy,
  double? satis,
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: alis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: alis,
      addedDate: added,
      kind: kind,
      sellPrice: satis,
    );

/// `HistoryService.getPortfolioHistoryBreakdownAtResolution`'ın değer
/// kuralı: slot = günün 00:00'ı (haftalıkta pazartesi 00:00), slottaki
/// miktar `addedDate <= slot` lotların işaretli toplamı, değer miktar ×
/// o slotun fiyatı. Sıfır miktarlı slot seride 0 taşır (motor da öyle).
Map<int, double> _motor(
  List<Asset> lotlar,
  DateTime from,
  DateTime to,
  double Function(DateTime slot) fiyat, {
  bool haftalik = false,
}) {
  final tier = haftalik ? ResolutionTier.weekly : ResolutionTier.daily;
  var cursor = DateTime.fromMillisecondsSinceEpoch(
      tier.normalizeTs(from.millisecondsSinceEpoch));
  final son = tier.normalizeTs(to.millisecondsSinceEpoch);
  final out = <int, double>{};
  while (cursor.millisecondsSinceEpoch <= son) {
    var q = 0.0;
    for (final l in lotlar) {
      if (l.addedDate.isAfter(cursor)) continue;
      q += l.isSell ? -l.quantity : l.quantity;
    }
    out[cursor.millisecondsSinceEpoch] = q * fiyat(cursor);
    cursor = DateTime(
        cursor.year, cursor.month, cursor.day + (haftalik ? 7 : 1));
  }
  return out;
}

class _Sonuc {
  final PeriodSummary ozet;
  final InflationWindow w;
  final RealReturn rr;
  _Sonuc(this.ozet, this.w, this.rr);
  double get nominal => rr.nominal;
  double get puan => rr.puan;
  double get reel => rr.reel;
}

/// `RealReturnService.piyasaGetirisi` ile AYNI çağrı — yalnızca seri
/// ağdan değil [_motor]'dan gelir.
_Sonuc _hizali(
  List<Asset> lotlar,
  InflationWindow w,
  double Function(DateTime) fiyat, {
  bool haftalik = false,
}) {
  final bd = PortfolioHistoryBreakdown(
    total: _motor(lotlar, w.seriBaslangici, w.seriBitisi, fiyat,
        haftalik: haftalik),
    byType: const {},
    byPosition: const {},
    positionType: const {},
  );
  final s = PeriodSummaryService.compute(
    period: SummaryPeriod.birYil,
    assets: lotlar,
    breakdown: bd,
    now: w.seriBitisi,
    pencereBaslangici: w.seriBaslangici,
  );
  return _Sonuc(
    s,
    w,
    RealReturn(nominal: s.getiriPct!, inflation: w.pct, pencere: w),
  );
}
