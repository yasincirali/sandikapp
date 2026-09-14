import 'dart:math' as math;

import '../models/asset.dart';
import '../utils/tr_format.dart';

/// Para ağırlıklı getiri (MWR) — XIRR.
///
/// ## Neden TWR'nin YANINDA, yerine değil
/// `LeaderboardService` yarış için simülasyon-ROI kullanıyor: dönem içi
/// alım/satım oranı ETKİLEMEZ, yalnızca piyasanın o varlıklara ne yaptığı
/// ölçülür. Bu yarış için doğru sorudur ("kim daha çok para koydu" değil).
///
/// XIRR bunun tam TERSİNİ ölçer ve o yüzden değerlidir: kullanıcının kendi
/// parasının, kendi zamanlamasıyla kazandığı yıllık bileşik oran. Dipte
/// alım yapan biri aynı varlıkla daha yüksek XIRR alır — "zamanlamam işe
/// yaradı mı" sorusunun cevabı budur ve simülasyon-ROI bunu yapısal olarak
/// veremez.
///
/// İki sayı ÇELİŞMEZ, farklı soruları yanıtlar. Ekran hangisinin hangi
/// soruya cevap verdiğini yazmak zorundadır; yoksa iki farklı yüzde gören
/// kullanıcı hangisine güveneceğini bilemez.
///
/// ## Nakit akışı işaret kuralı
/// XIRR yatırımcının CEBİ açısından bakar:
///   · alım  → cepten çıktı  → NEGATİF
///   · satış → cebe girdi    → POZİTİF
///   · temettü → cebe girdi  → POZİTİF
///   · bugünkü portföy değeri → sanal satış → POZİTİF (son akış)
///
/// `PeriodSummaryService.flowOf` bunun TERSİ işareti kullanır (portföye
/// giren para +). Bu bilinçli: orası "portföy ne kadar büyüdü" sorusunu,
/// burası "cebimden ne çıktı ne girdi" sorusunu yanıtlıyor. Dönüşüm tek
/// yerde ([_akislar]) ve işareti çeviren tek satır orada.
class XirrService {
  XirrService._();

  /// Yakınsama toleransı — NPV bu değerin altına inince kök bulunmuş sayılır.
  static const _tolerans = 1e-7;

  /// Newton-Raphson üst sınırı. Aşılırsa bisection'a düşülür.
  static const _maxIterasyon = 100;

  /// Anlamlı bir XIRR için gereken en az gün.
  ///
  /// Bir haftalık veriden yıllık bileşik oran türetmek 52. kuvvet almaktır:
  /// %2'lik bir haftalık hareket "%180 yıllık" olarak görünür. Matematiksel
  /// olarak doğru, ürün olarak yalan.
  static const minGun = 60;

  /// Döndürülebilir en uç oranlar.
  ///
  /// Bu aralığın dışına çıkan sonuç neredeyse her zaman veri hatasıdır
  /// (aynı gün alınıp satılmış lot, sıfıra yakın taban). Kullanıcıya
  /// "%14.000 yıllık getiri" yazmaktansa hiçbir şey yazmamak doğrudur.
  static const _altSinir = -0.9999;
  static const _ustSinir = 100.0; // %10.000

  /// Portföyün para ağırlıklı yıllık getirisi, YÜZDE olarak.
  ///
  /// [bugunkuDegerTRY] son (sanal) nakit akışıdır: bugün her şeyi satsan
  /// eline geçecek tutar.
  ///
  /// `null` döner — ve bu bir hata değil, dürüst bir cevaptır:
  ///   · akış yok ya da hepsi aynı işaretli (kök tanımsız)
  ///   · pencere [minGun]'den kısa
  ///   · yöntem yakınsamadı
  ///   · sonuç makul aralığın dışında
  static double? portfolioXirr({
    required List<Asset> assets,
    required double bugunkuDegerTRY,
    required DateTime now,
    DateTime? from,
  }) {
    final akislar = _akislar(assets, from: from, to: now);
    if (akislar.isEmpty) return null;

    // Bugünkü değer sanal satış olarak eklenir.
    if (bugunkuDegerTRY > 0) {
      akislar.add((tarih: now, tutar: bugunkuDegerTRY));
    }

    return compute(akislar);
  }

  /// Ham nakit akışlarından XIRR — saf, test edilebilir çekirdek.
  ///
  /// [akislar] sıralı olmak zorunda değil; içeride sıralanır.
  static double? compute(List<({DateTime tarih, double tutar})> akislar) {
    if (akislar.length < 2) return null;

    final sirali = [...akislar]..sort((a, b) => a.tarih.compareTo(b.tarih));

    // İşaret değişimi ŞART: hepsi pozitif ya da hepsi negatifse NPV
    // eğrisinin kökü yoktur. Bu bir hesap hatası değil, "bu veriyle XIRR
    // tanımsız" demektir.
    final varPozitif = sirali.any((a) => a.tutar > 0);
    final varNegatif = sirali.any((a) => a.tutar < 0);
    if (!varPozitif || !varNegatif) return null;

    final ilk = sirali.first.tarih;
    final gunFarki = sirali.last.tarih.difference(ilk).inDays;
    if (gunFarki < minGun) return null;

    // Gün cinsinden ofsetler — yıl kesri olarak (365 gün).
    final yillar = sirali
        .map((a) => a.tarih.difference(ilk).inDays / 365.0)
        .toList(growable: false);
    final tutarlar = sirali.map((a) => a.tutar).toList(growable: false);

    double npv(double oran) {
      var toplam = 0.0;
      for (var i = 0; i < tutarlar.length; i++) {
        toplam += tutarlar[i] / math.pow(1 + oran, yillar[i]);
      }
      return toplam;
    }

    // ── 1) Newton-Raphson ────────────────────────────────────────────────
    // Hızlı ama her zaman yakınsamaz: NPV eğrisi çok akışlı portföylerde
    // birden fazla kök ya da düz bölge taşıyabilir.
    var oran = 0.1; // %10 — makul başlangıç
    for (var i = 0; i < _maxIterasyon; i++) {
      final f = npv(oran);
      if (f.abs() < _tolerans) {
        return _dogrula(oran);
      }

      // Sayısal türev: analitik türev de yazılabilirdi ama pow'un negatif
      // tabanda davranışı burada ek bir tuzak; merkezi fark yeterince
      // kararlı ve okunur.
      const h = 1e-6;
      final tureva = (npv(oran + h) - f) / h;
      if (tureva.abs() < 1e-12) break; // düz bölge — bisection'a düş

      final yeni = oran - f / tureva;
      if (!yeni.isFinite) break;
      if (yeni <= _altSinir) break; // −%100'ün altı tanımsız

      if ((yeni - oran).abs() < _tolerans) {
        return _dogrula(yeni);
      }
      oran = yeni;
    }

    // ── 2) Bisection — garantili ama yavaş ───────────────────────────────
    // Newton başarısızsa işaret değiştiren bir aralık taranır. Bulunamazsa
    // sonuç UYDURULMAZ, `null` döner.
    return _bisection(npv);
  }

  /// İşaret değiştiren aralığı tarayıp ikiye bölerek kökü bulur.
  static double? _bisection(double Function(double) npv) {
    var alt = _altSinir + 1e-6;
    var alrDeger = npv(alt);
    if (!alrDeger.isFinite) return null;

    // Kaba tarama: −%99'dan %10.000'e logaritmik olmayan ama yeterince sık
    // adımlarla ilk işaret değişimini bul.
    const adim = 0.05;
    var ust = alt;
    var bulundu = false;
    for (var r = alt + adim; r <= _ustSinir; r += adim) {
      final d = npv(r);
      if (!d.isFinite) continue;
      if (alrDeger * d <= 0) {
        ust = r;
        bulundu = true;
        break;
      }
      alt = r;
      alrDeger = d;
    }
    if (!bulundu) return null;

    for (var i = 0; i < 200; i++) {
      final orta = (alt + ust) / 2;
      final d = npv(orta);
      if (d.abs() < _tolerans || (ust - alt) / 2 < 1e-9) {
        return _dogrula(orta);
      }
      if (alrDeger * d <= 0) {
        ust = orta;
      } else {
        alt = orta;
        alrDeger = d;
      }
    }
    return null;
  }

  /// Makul aralık denetimi + yüzdeye çevirme.
  static double? _dogrula(double oran) {
    if (!oran.isFinite) return null;
    if (oran <= _altSinir || oran > _ustSinir) return null;
    return oran * 100;
  }

  /// Varlık defterinden CEP açısından nakit akışları.
  ///
  /// İşaret `PeriodSummaryService.flowOf`'un TERSİ (sınıf notuna bakın).
  /// Temettü akışa GİRER — `flowOf` onu dışarıda bırakıyor çünkü orada
  /// soru "portföye ne kadar para koydum"; burada soru "cebime ne girdi"
  /// ve temettü tam olarak odur.
  ///
  /// Ham defter kullanılır (`aktifLotlar` DEĞİL): XIRR geçmişi sorar,
  /// bugünkü mülkiyeti değil (CLAUDE.md "kapanmış pozisyon" kuralı).
  /// `isActive` yine de elenir — yumuşak silinmiş lot hiç olmamış sayılır.
  static List<({DateTime tarih, double tutar})> _akislar(
    List<Asset> assets, {
    DateTime? from,
    required DateTime to,
  }) {
    final out = <({DateTime tarih, double tutar})>[];
    for (final a in assets) {
      if (!a.isActive) continue;
      if (a.addedDate.isAfter(to)) continue;
      if (from != null && a.addedDate.isBefore(from)) continue;

      if (a.isBuy) {
        out.add((tarih: a.addedDate, tutar: -a.totalCostTRY));
      } else if (a.isSell) {
        out.add((tarih: a.addedDate, tutar: a.sellProceedsTRY));
      } else if (a.isDividend) {
        out.add((tarih: a.addedDate, tutar: a.dividendTRY));
      }
    }
    return out;
  }

  /// Dönem içindeki temettü toplamı (TRY).
  ///
  /// Köprü kartının "temettü" satırı buradan besleniyor. `flowOf` temettüyü
  /// bilinçli olarak dışarıda bıraktığı için ayrı bir toplayıcı gerekti;
  /// pencere kuralı `netInflow` ile AYNI (gün sınırlarına genişletilmiş)
  /// olmalı ki iki sayı aynı dönemi anlatsın.
  static double dividendsInPeriod(
    List<Asset> assets,
    DateTime start,
    DateTime end,
  ) {
    final startMs = dayKey(start).millisecondsSinceEpoch;
    final endMs = DateTime(end.year, end.month, end.day, 23, 59, 59)
        .millisecondsSinceEpoch;

    var toplam = 0.0;
    for (final a in assets) {
      if (!a.isActive || !a.isDividend) continue;
      final ms = a.addedDate.millisecondsSinceEpoch;
      if (ms < startMs || ms > endMs) continue;
      toplam += a.dividendTRY;
    }
    return toplam;
  }
}
