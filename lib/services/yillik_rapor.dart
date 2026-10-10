import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import 'varlik_masraflari.dart' show abdTemettuStopajOrani;

/// Yıllık kâr, temettü ve masraf raporu (Premium, yasin 2026-10-10).
///
/// ## Neden
/// Araştırmada (tmp/arastirma, "Portföy takibine neden para ödenir")
/// portföy takipçisine ödenen en somut iş vergi/rapor işi çıktı: Sharesight
/// ucuz kademeyi ana kademeden bu raporla ayırıyor. sandık gerçekleşen
/// kâr/zararı, satış günü kurunu ve temettüyü zaten tutuyor; eksik olan
/// "bu yıl ne sattım, ne kazandım, ne kesildi" sorusunu TEK belgede
/// cevaplamaktı — mali müşavire verilebilecek biçimde (PDF/Excel,
/// `yillik_rapor_disa_aktarim.dart`).
///
/// ## Kurallar
/// - **Geçmiş sorusudur → ham defter.** `aktifLotlar` değil: kapanmış
///   pozisyonun satışı da o yılın raporundadır (CLAUDE.md "Kapanmış
///   pozisyon"). Yalnız silinmiş satırlar (`isActive == false`) düşer.
/// - **Yalnız kendi lotların.** Ortağın satırları (Birlikte görünümünde
///   durumda bulunur) rapora girmez: rapor kişinin beyanına dayanak olur
///   (ortak aggregation kuralı).
/// - **Gerçekleşen kâr `PortfolioState.realizedGainLoss` ile aynı formül.**
///   Satış fiyatı olmayan eski satış satırları uydurulmaz, sayılıp
///   [YillikRapor.fiyatsizSatis] ile söylenir.
/// - **Stopaj yalnız bilinen orandan.** Temettü satırı NET tutarı taşır
///   (`Asset.dividendAmount`); brüt = net / (1 − oran). BIST hissesinde oran
///   Remote Config `temettu_stopaj_orani`, ABD hissesinde anlaşma oranı
///   (%20, `abdTemettuStopajOrani`). Oran bilinmiyorsa brüt ve stopaj
///   `null` kalır — tahmin yazılmaz.
/// - **Vergi hesabı yapmaz.** Rapor beyanname ya da vergi tavsiyesi değil;
///   kayıtları dönemine göre toplar. Yurt dışı (ABD) satışları ayrı toplanır
///   çünkü beyan sorusu orada başlar; yorum müşavirindir.
///
/// Saf Dart: ağ yok, Flutter yok. Ekran: `yillik_rapor_screen.dart`.

@immutable
class YillikSatis {
  const YillikSatis({
    required this.tarih,
    required this.ad,
    required this.ticker,
    required this.tur,
    required this.yurtDisi,
    required this.miktar,
    required this.satisTry,
    required this.maliyetTry,
    required this.komisyonTry,
  });

  final DateTime tarih;
  final String ad;
  final String ticker;
  final AssetType tur;

  /// ABD hissesi (yurt dışı menkul kıymet).
  final bool yurtDisi;
  final double miktar;

  /// Satış tutarı, satış günü kuruyla (komisyon düşülmeden).
  final double satisTry;

  /// Satılan miktarın alım maliyeti, alım kuruyla.
  final double maliyetTry;

  /// Satış komisyonu, satış kuruyla.
  final double komisyonTry;

  /// Gerçekleşen kâr/zarar: satış − maliyet − komisyon.
  double get karTry => satisTry - maliyetTry - komisyonTry;
}

@immutable
class YillikTemettu {
  const YillikTemettu({
    required this.tarih,
    required this.ad,
    required this.ticker,
    required this.yurtDisi,
    required this.netTry,
    required this.stopajOrani,
  });

  final DateTime tarih;
  final String ad;
  final String ticker;
  final bool yurtDisi;

  /// Ele geçen net tutar (kayıtlı).
  final double netTry;

  /// Bilinen stopaj oranı (kesir) ya da `null`.
  final double? stopajOrani;

  double? get brutTry =>
      stopajOrani == null ? null : netTry / (1 - stopajOrani!);

  double? get stopajTry => brutTry == null ? null : brutTry! - netTry;
}

@immutable
class YillikRapor {
  const YillikRapor({
    required this.yil,
    required this.satislar,
    required this.temettuler,
    required this.alimKomisyonuTry,
    required this.fiyatsizSatis,
  });

  final int yil;

  /// Tarihe göre sıralı.
  final List<YillikSatis> satislar;

  /// Tarihe göre sıralı.
  final List<YillikTemettu> temettuler;

  /// O yıl yapılan alımların komisyonu (alım kuruyla).
  final double alimKomisyonuTry;

  /// Satış fiyatı kayıtlı olmadığı için rapora giremeyen satış satırı sayısı.
  final int fiyatsizSatis;

  bool get bos => satislar.isEmpty && temettuler.isEmpty && alimKomisyonuTry == 0;

  double get gerceklesenKarTry => satislar.fold(0.0, (t, s) => t + s.karTry);

  double get yurtDisiKarTry => satislar
      .where((s) => s.yurtDisi)
      .fold(0.0, (t, s) => t + s.karTry);

  bool get yurtDisiVar =>
      satislar.any((s) => s.yurtDisi) || temettuler.any((t) => t.yurtDisi);

  double get temettuNetTry => temettuler.fold(0.0, (t, d) => t + d.netTry);

  /// Bütün temettülerin oranı biliniyorsa toplam stopaj; biri bile
  /// bilinmiyorsa `null` (eksik toplam doğru toplam gibi okunurdu).
  double? get stopajTry {
    double t = 0;
    for (final d in temettuler) {
      final s = d.stopajTry;
      if (s == null) return null;
      t += s;
    }
    return t;
  }

  double get satisKomisyonuTry =>
      satislar.fold(0.0, (t, s) => t + s.komisyonTry);

  /// O yıl ödenen bütün işlem masrafları (alım + satış komisyonu).
  double get masrafTry => alimKomisyonuTry + satisKomisyonuTry;
}

/// Raporda yılı olan bütün yıllar (yeniden eskiye). Seçici bunları sunar;
/// kaydı olmayan yıl listelenmez.
List<int> raporYillari(Iterable<Asset> lotlar, String userId) {
  final yillar = <int>{
    for (final a in lotlar)
      if (a.userId == userId &&
          a.isActive &&
          (a.isSell || a.isDividend || (a.isBuy && a.commission > 0)))
        a.addedDate.year,
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  return yillar;
}

/// [userId]'nin [yil] raporu. [bistStopajOrani]: Remote Config
/// `temettu_stopaj_orani` (`null` = bilinmiyor).
YillikRapor yillikRapor({
  required Iterable<Asset> lotlar,
  required String userId,
  required int yil,
  required double? bistStopajOrani,
}) {
  final satislar = <YillikSatis>[];
  final temettuler = <YillikTemettu>[];
  double alimKomisyonu = 0;
  var fiyatsiz = 0;
  for (final a in lotlar) {
    if (a.userId != userId || !a.isActive) continue;
    if (a.addedDate.year != yil) continue;
    if (a.isSell) {
      if (a.sellPrice == null) {
        fiyatsiz++;
        continue;
      }
      satislar.add(YillikSatis(
        tarih: a.addedDate,
        ad: a.name,
        ticker: a.ticker,
        tur: a.type,
        yurtDisi: a.abdHissesi,
        miktar: a.quantity,
        satisTry: a.sellPrice! * a.quantity * a.satisKuru,
        maliyetTry: a.purchasePrice * a.quantity * a.purchaseFxRate,
        komisyonTry: a.commission * a.satisKuru,
      ));
    } else if (a.isDividend) {
      final double? oran;
      if (a.type != AssetType.hisse) {
        oran = null;
      } else if (a.abdHissesi) {
        oran = abdTemettuStopajOrani;
      } else {
        oran = bistStopajOrani;
      }
      temettuler.add(YillikTemettu(
        tarih: a.addedDate,
        ad: a.name,
        ticker: a.ticker,
        yurtDisi: a.abdHissesi,
        netTry: a.dividendTRY,
        stopajOrani: oran,
      ));
      // Temettü satırının komisyonu (nadiren; saklama ücreti) masrafa girer.
      alimKomisyonu += a.commission * a.purchaseFxRate;
    } else if (a.isBuy) {
      alimKomisyonu += a.commission * a.purchaseFxRate;
    }
  }
  satislar.sort((x, y) => x.tarih.compareTo(y.tarih));
  temettuler.sort((x, y) => x.tarih.compareTo(y.tarih));
  return YillikRapor(
    yil: yil,
    satislar: satislar,
    temettuler: temettuler,
    alimKomisyonuTry: alimKomisyonu,
    fiyatsizSatis: fiyatsiz,
  );
}
