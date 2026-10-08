/// Eurobond — ISIN kimliği, kupon takvimi, işlemiş faiz ve kirli fiyat.
///
/// ## Neden ayrı bir model (2026-10-08, yasin: "eurobond … her varlık türü
/// için detaycı olmalıyız, kendine has masraflarını ekranda gösterebilmeliyiz")
/// Eurobond hisse gibi "adet × fiyat" değildir:
///   * Miktar NOMİNALDİR (ör. 10.000 USD), fiyat nominalin YÜZDESİ olarak
///     kote edilir (ör. 98,45 → 100 nominal için 98,45 USD).
///   * Ekranda ve kaynaklarda görünen fiyat TEMİZ fiyattır; alıcı ayrıca son
///     kupondan bu yana İŞLEMİŞ FAİZİ öder (kirli fiyat = temiz + işlemiş).
///     Bunu göstermemek, kullanıcının cebinden çıkan parayı eksik yazmak olur.
///   * Kupon dönemsel nakit akışıdır; temettü gibi ama tarihi ve tutarı
///     baştan bellidir.
///
/// Fiyat KAYNAĞI bu dosyada değildir (fiyat kaynağı sözleşmesi madde 1:
/// karar `FiyatKaynagi`'nda). Burası yalnızca sözleşmenin aritmetiğidir ve
/// saf Dart'tır; sunucu eşi `supabase/functions/_shared/eurobond.ts`.
library;

import 'dart:math' as math;

/// Eurobond sembol öneki — `assets.ticker` = `EUROBOND:US900123DF45`.
///
/// `KRIPTO:`/`TEFAS:` gibi: önek fiyat servisinde sembolü Yahoo'dan
/// UZAK tutar. Eski uygulama sürümleri öneki tanımaz ve sembolü Yahoo'ya
/// sorar; Yahoo'da böyle bir sembol olmadığı için fiyat DÖNMEZ ve lot son
/// bilinen fiyatla kalır — yanlış bir fiyat yazılmaz (uydurma sayı yasağı).
const String eurobondOneki = 'EUROBOND:';

/// `EUROBOND:us900123df45` → `US900123DF45`; geçerli ISIN değilse `null`.
String? eurobondIsin(String ticker) {
  final s = ticker.trim().toUpperCase();
  if (!s.startsWith(eurobondOneki)) return null;
  final isin = s.substring(eurobondOneki.length);
  return isinGecerli(isin) ? isin : null;
}

/// `US900123DF45` → `EUROBOND:US900123DF45`.
String eurobondSembolu(String isin) =>
    '$eurobondOneki${isin.trim().toUpperCase()}';

final RegExp _isinDeseni = RegExp(r'^[A-Z]{2}[A-Z0-9]{9}[0-9]$');

/// ISIN kontrol hanesi (ISO 6166, Luhn) doğru mu?
///
/// Neden zorunlu: araştırma sırasında örnek verilen `US900123DF46` hiçbir
/// kaynakta yoktu; doğrusu `US900123DF45`. Tek hane hatalı ISIN kaynakta
/// "fiyat yok" döner ve kullanıcı sebebini anlamaz — girişte yakalanır.
bool isinGecerli(String isin) {
  final s = isin.trim().toUpperCase();
  if (!_isinDeseni.hasMatch(s)) return false;
  // Harfler 10..35'e açılır, sonra Luhn.
  final rakamlar = StringBuffer();
  for (final c in s.codeUnits) {
    if (c >= 48 && c <= 57) {
      rakamlar.writeCharCode(c);
    } else {
      rakamlar.write(c - 55);
    }
  }
  final d = rakamlar.toString();
  var toplam = 0;
  var cift = false;
  for (var i = d.length - 1; i >= 0; i--) {
    var n = d.codeUnitAt(i) - 48;
    if (cift) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    toplam += n;
    cift = !cift;
  }
  return toplam % 10 == 0;
}

/// İhraççı sınıfı — kupon vergisi buna göre değişir.
enum EurobondIhracci {
  /// T.C. Hazine ve Maliye Bakanlığı (ISIN çoğunlukla `US900123…`).
  hazine,

  /// Türk şirketi / bankası (ISIN çoğunlukla `XS…`).
  ozelSektor,
}

/// Gün sayım kuralı. Hazine USD eurobondları ve Türk kurumsalların büyük
/// çoğunluğu 30/360 (ABD) kullanır; EUR ihraçlar ACT/ACT (ICMA).
enum GunSayimi { otuz360, actAct }

/// Bir eurobondun sözleşme özellikleri — katalogdan gelir, kullanıcı
/// girmez (kupon/vade yanlış girilirse işlemiş faiz sessizce yanlış çıkar).
class EurobondSozlesmesi {
  const EurobondSozlesmesi({
    required this.isin,
    required this.ad,
    required this.paraBirimi,
    required this.kuponOrani,
    required this.vade,
    required this.ihracTarihi,
    required this.ihracci,
    this.yillikKuponSayisi = 2,
    this.gunSayimi = GunSayimi.otuz360,
    this.asgariNominal,
  });

  final String isin;
  final String ad;

  /// 'USD' ya da 'EUR'.
  final String paraBirimi;

  /// Yıllık kupon, oran olarak (%9,875 → 0.09875).
  final double kuponOrani;
  final DateTime vade;
  final DateTime ihracTarihi;
  final EurobondIhracci ihracci;
  final int yillikKuponSayisi;
  final GunSayimi gunSayimi;

  /// İhraçtaki asgari işlem nominali (çoğu ihraçta 200.000). Bilinmiyorsa
  /// null — uydurulmaz.
  final double? asgariNominal;

  /// İhraçtaki vade (yıl) — kurumsal kupon stopajı buna bağlı.
  double get ihracVadesiYil =>
      vade.difference(ihracTarihi).inDays / 365.25;

  /// Kupon tarihleri vadeden geriye, ay adımıyla üretilir (ilk kupon kısa
  /// ya da uzun olabilir; vadeye hizalı takvim piyasa standardıdır).
  List<DateTime> kuponTarihleri() {
    final adim = 12 ~/ yillikKuponSayisi;
    final out = <DateTime>[];
    var t = vade;
    while (t.isAfter(ihracTarihi)) {
      out.add(t);
      t = _ayEkle(vade, -adim * out.length);
    }
    return out.reversed.toList();
  }

  /// [gun] itibarıyla son ve sonraki kupon tarihi. Vadeden sonra null.
  ({DateTime onceki, DateTime sonraki})? kuponAraligi(DateTime gun) {
    final g = _gun(gun);
    if (!g.isBefore(vade)) return null;
    final adim = 12 ~/ yillikKuponSayisi;
    var sonraki = vade;
    var i = 1;
    while (true) {
      final onceki = _ayEkle(vade, -adim * i);
      if (!g.isBefore(onceki)) {
        return (
          onceki: onceki.isBefore(ihracTarihi) ? ihracTarihi : onceki,
          sonraki: sonraki,
        );
      }
      sonraki = onceki;
      i++;
    }
  }

  /// 100 nominal başına işlemiş faiz (fiyat puanı cinsinden).
  ///
  /// Uzlaşma tarihi (T+2) yerine [gun] kullanılır: uygulama değerleme
  /// yapar, takas değil; fark kupon başına iki günlük faizdir ve
  /// kaynak fiyatlarının kendisi de günlük kapanıştır.
  double islemisFaiz(DateTime gun) {
    final a = kuponAraligi(gun);
    if (a == null) return 0;
    final kupon = 100 * kuponOrani / yillikKuponSayisi;
    final g = _gun(gun);
    switch (gunSayimi) {
      case GunSayimi.otuz360:
        final gecen = _gun30360(a.onceki, g);
        final donem = 360 / yillikKuponSayisi;
        return kupon * gecen / donem;
      case GunSayimi.actAct:
        final gecen = g.difference(a.onceki).inDays;
        final donem = a.sonraki.difference(a.onceki).inDays;
        return donem <= 0 ? 0 : kupon * gecen / donem;
    }
  }

  /// Kirli fiyat = temiz + işlemiş faiz (100 nominal başına).
  double kirliFiyat(double temizFiyat, DateTime gun) =>
      temizFiyat + islemisFaiz(gun);

  /// Bir kuponun brüt tutarı, [nominal] için para biriminde.
  double kuponTutari(double nominal) =>
      nominal * kuponOrani / yillikKuponSayisi;

  /// Kupon stopajı (tam mükellef gerçek kişi).
  ///
  /// * Hazine eurobondu: stopaj YOK (yıllık beyan; GVK geçici 67 dışı).
  /// * Türk şirketi eurobondu: 2009/14592 BKK, 842 sayılı CBK (2019) ile
  ///   ihraç vadesi < 1 yıl %7, 1–3 yıl %3, ≥ 3 yıl %0.
  ///   "%10" yurt içi ÖSBA oranıdır, eurobonda UYGULANMAZ.
  double get kuponStopajOrani {
    if (ihracci == EurobondIhracci.hazine) return 0;
    final y = ihracVadesiYil;
    if (y < 1) return 0.07;
    if (y < 3) return 0.03;
    return 0;
  }

  /// Basit vadeye getiri (yıllık, yarı yıllık bileşik), temiz fiyattan.
  ///
  /// Newton yerine ikiye bölme: fiyat getiride monoton azalan, 60 adımda
  /// 1e-12 hassasiyet; ıraksama ihtimali yok. Vadesi geçmişse null.
  double? vadeyeGetiri(double temizFiyat, DateTime gun) {
    final g = _gun(gun);
    if (!g.isBefore(vade) || temizFiyat <= 0) return null;
    final kirli = kirliFiyat(temizFiyat, g);
    final f = yillikKuponSayisi;
    final kupon = 100 * kuponOrani / f;
    final kalanlar = kuponTarihleri().where((t) => t.isAfter(g)).toList();
    double bugunkuDeger(double y) {
      var t = 0.0;
      for (final k in kalanlar) {
        final yil = k.difference(g).inDays / 365.25;
        final nakit = kupon + (k == kalanlar.last ? 100 : 0);
        t += nakit / math.pow(1 + y / f, yil * f);
      }
      return t;
    }

    var alt = -0.99, ust = 5.0;
    for (var i = 0; i < 60; i++) {
      final orta = (alt + ust) / 2;
      if (bugunkuDeger(orta) > kirli) {
        alt = orta;
      } else {
        ust = orta;
      }
    }
    return (alt + ust) / 2;
  }
}

DateTime _gun(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Ay ekler; hedef ayda o gün yoksa ayın son günü (31 Mart − 1 ay = 28/29 Şubat).
DateTime _ayEkle(DateTime d, int ay) {
  final toplamAy = d.year * 12 + (d.month - 1) + ay;
  final y = toplamAy ~/ 12;
  final m = toplamAy % 12 + 1;
  final sonGun = DateTime.utc(y, m + 1, 0).day;
  return DateTime.utc(y, m, d.day > sonGun ? sonGun : d.day);
}

/// 30/360 (ABD, "bond basis") gün sayısı.
int _gun30360(DateTime a, DateTime b) {
  var d1 = a.day, d2 = b.day;
  if (d1 == 31) d1 = 30;
  if (d2 == 31 && d1 == 30) d2 = 30;
  return 360 * (b.year - a.year) + 30 * (b.month - a.month) + (d2 - d1);
}
