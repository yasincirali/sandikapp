import 'ekstre_tablosu.dart';
import 'tablo_anlama.dart';
import 'tablo_okuyucular.dart' show sayiMetni;

/// Hesap hareketlerindeki fon/hisse alım satımları (2026-10-05).
///
/// ## Neden
/// Banka varlık ekstresi iki şey taşır: dönem sonundaki VARLIKLAR (pay adedi,
/// o günün fiyatı) ve dönem içindeki HESAP HAREKETLERİ. Yalnız varlık
/// tablosu okunursa maliyet "ekstre günündeki fiyat" olur ve K/Z ekstre
/// gününden başlar. Gerçek alış hareketin açıklamasında yazar:
/// "TEFAS Müşteriye Fon Satış YAY 29,00x1.739,1789960   -50.436,19".
/// Kullanıcı (yasin, 2026-10-05): "bunun içinden varlık alım satımları
/// nasıl ayıklarsın".
///
/// ## Kurum başına kod yok — yön paranın İŞARETİNDEN
/// Banka açıklamayı kendi gözünden yazar ("Müşteriye Fon Satış" müşterinin
/// ALIŞI, docs/EKSTRE_MOTORU.md tuzağı) ve bu kelimeler kurumdan kuruma
/// değişir. Kelimeye bakmak yerine paranın yönüne bakılır: hesaptan ÇIKAN
/// para (eksi tutar ya da "Çekilen/Borç" sütunu) alıştır, GİREN para satış.
/// Bu her kurumda aynıdır.
///
/// ## Uydurma yok
/// Satır yalnız `KOD adet x fiyat` kalıbı VE adet × fiyat ≈ |tutar| (±%2)
/// tuttuğunda alınır. Stopaj satırı ("Stopaj Vergisi FON ALIS FON5
/// 1834X5,48 … -19,37") kalıbı taşır ama tutarı tutmaz → alınmaz.
/// Kodun gerçek bir varlık olduğu burada bilinmez: hareket yalnız VARLIK
/// tablosunda aynı kodla duran bir satırı inceltmek için kullanılır
/// ([hareketlerleIncelt]); "FON5" gibi bankanın iç süpürme fonu böylece
/// hiçbir yere girmez.
class EkstreHareketi {
  const EkstreHareketi({
    required this.tarih,
    required this.kod,
    required this.adet,
    required this.fiyat,
    required this.satis,
  });

  final DateTime tarih;
  final String kod;
  final double adet;
  final double fiyat;

  /// Para hesaba GİRDİ (müşteri sattı).
  final bool satis;

  @override
  String toString() =>
      '$kod ${satis ? 'satış' : 'alış'} $adet×$fiyat @ ${tarih.toIso8601String().substring(0, 10)}';
}

final _kalip = RegExp(
  r'(?:^|[\s(])([A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ0-9]{1,5})\s+(\d[\d.,]*)\s*[xX×]\s*(\d[\d.,]*)',
);

/// Tüm tablolardaki hareket satırları. Başlığında "Açıklama" ve "Tarih"
/// olan tablolara bakılır (hesap hareketleri listesi).
List<EkstreHareketi> hareketleriBul(List<EkstreTablosu> tablolar) {
  final out = <EkstreHareketi>[];
  for (final t in tablolar) {
    out.addAll(_tablodan(t));
  }
  return out;
}

Iterable<EkstreHareketi> _tablodan(EkstreTablosu t) sync* {
  final satirlar = t.satirlar;
  for (var b = 0; b < satirlar.length && b < 40; b++) {
    final baslik = [for (final h in satirlar[b]) ekstreNormal(h)];
    final aciklama = baslik.indexWhere((h) => h.contains('aciklama'));
    final tarih = baslik.indexWhere((h) => h.contains('tarih'));
    if (aciklama < 0 || tarih < 0) continue;
    // Para hareketi sütunları: bakiye DEĞİL (bakiye satırın sonucudur).
    final tutarlar = <int, bool>{}; // sütun → çıkış sütunu mu
    for (final (i, h) in baslik.indexed) {
      if (i == aciklama || i == tarih || h.contains('bakiye')) continue;
      final cikis = h.contains('cekilen') ||
          h.contains('borc') ||
          h.contains('cikis') ||
          h.contains('cikan');
      final para = cikis ||
          h.contains('tutar') ||
          h.contains('yatirilan') ||
          h.contains('alacak') ||
          h.contains('giris') ||
          h.contains('giren');
      if (para) tutarlar[i] = cikis;
    }
    if (tutarlar.isEmpty) continue;
    for (final s in satirlar.skip(b + 1)) {
      if (aciklama >= s.length || tarih >= s.length) continue;
      final gun = tarihCoz(s[tarih]);
      if (gun == null) continue;
      final m = _kalip.firstMatch(s[aciklama]);
      if (m == null) continue;
      for (final MapEntry(key: c, value: cikisSutunu) in tutarlar.entries) {
        if (c >= s.length || s[c].trim().isEmpty) continue;
        final h = _eslesen(m.group(2)!, m.group(3)!, s[c]);
        if (h == null) continue;
        final (adet, fiyat, tutar) = h;
        yield EkstreHareketi(
          tarih: gun,
          kod: m.group(1)!,
          adet: adet,
          fiyat: fiyat,
          satis: !(tutar < 0 || cikisSutunu),
        );
        break;
      }
    }
    return; // bir tabloda tek hareket başlığı
  }
}

/// Adet, fiyat ve tutarı iki sayı stilinde de dener; adet × fiyat ≈ |tutar|
/// tutan ilk yorum. Açıklamadaki sayı ("4.897,00x5,47") ile tutar sütunu
/// ("26,808.56 TL") aynı belgede FARKLI stilde olabilir (DenizBank).
(double, double, double)? _eslesen(String a, String f, String t) {
  for (final ts in const [true, false]) {
    final tutar = sayiCoz(t, turkce: ts);
    if (tutar == null || tutar == 0) continue;
    for (final ss in const [true, false]) {
      final adet = sayiCoz(a, turkce: ss), fiyat = sayiCoz(f, turkce: ss);
      if (adet == null || fiyat == null || adet <= 0 || fiyat <= 0) continue;
      if ((adet * fiyat - tutar.abs()).abs() <= tutar.abs() * 0.02 + 0.01) {
        return (adet, fiyat, tutar);
      }
    }
  }
  return null;
}

/// Varlık satırlarını hareketlerle incelt: dönem içinde ALINMIŞ payın
/// gerçek tarihi ve fiyatı. Satırlar `kanonikSatirlar` düzeninde (sekmeli).
///
/// Kural (çift sayım yok): varlık tablosu NE olduğunu söyler, hareket
/// yalnız NE ZAMAN ve KAÇA alındığını. Bir kodun dönemdeki alışları
/// eldeki adedi aşmıyorsa alışlar ayrı satır olur, kalan (dönemden önce
/// alınmış) adet varlık satırında ekstre günüyle kalır. Kodda satış
/// varsa ya da alışlar eldekini aşıyorsa (başka hesaptan satış) satır
/// olduğu gibi kalır — sıralamayı tahmin etmektense eski davranış.
({List<String> satirlar, int incelen}) hareketlerleIncelt(
  List<String> satirlar,
  List<EkstreRol> sutunlar,
  List<EkstreHareketi> hareketler,
) {
  final iSembol = sutunlar.indexOf(EkstreRol.sembol);
  final iAdet = sutunlar.indexOf(EkstreRol.adet);
  if (hareketler.isEmpty || iSembol < 0 || iAdet < 0) {
    return (satirlar: satirlar, incelen: 0);
  }
  final iFiyat = sutunlar.indexOf(EkstreRol.fiyat);
  final iTutar = sutunlar.indexOf(EkstreRol.tutar);
  final iTarih = sutunlar.indexOf(EkstreRol.tarih);
  final iYon = sutunlar.indexOf(EkstreRol.yon);
  final kodlu = <String, List<EkstreHareketi>>{};
  for (final h in hareketler) {
    kodlu.putIfAbsent(h.kod.toUpperCase(), () => []).add(h);
  }
  final out = <String>[];
  var incelen = 0;
  for (final satir in satirlar) {
    final h = satir.split('\t');
    final hs = kodlu[h[iSembol].trim().toUpperCase()];
    final eldeki = sayiCoz(h[iAdet]);
    final yon = iYon < 0 ? '' : h[iYon];
    if (hs == null ||
        eldeki == null ||
        yon == 'Satış' ||
        hs.any((x) => x.satis)) {
      out.add(satir);
      continue;
    }
    final alis = hs.fold<double>(0, (t, x) => t + x.adet);
    if (alis > eldeki + 1e-6) {
      out.add(satir);
      continue;
    }
    incelen++;
    for (final x in [...hs]..sort((a, b) => a.tarih.compareTo(b.tarih))) {
      out.add(_kopya(h, iAdet, iFiyat, iTutar, iTarih, x.adet, x.fiyat, x.tarih));
    }
    final kalan = eldeki - alis;
    if (kalan > 1e-6) {
      final fiyat = iFiyat < 0 ? null : sayiCoz(h[iFiyat]);
      out.add(_kopya(h, iAdet, -1, iTutar, -1, kalan, fiyat, null));
    }
  }
  return (satirlar: out, incelen: incelen);
}

String _kopya(List<String> h, int iAdet, int iFiyat, int iTutar, int iTarih,
    double adet, double? fiyat, DateTime? tarih) {
  final y = [...h];
  y[iAdet] = sayiMetni(adet);
  if (iFiyat >= 0 && fiyat != null) y[iFiyat] = sayiMetni(fiyat);
  final birim = fiyat ?? (iFiyat >= 0 ? sayiCoz(h[iFiyat]) : null);
  if (iTutar >= 0) {
    y[iTutar] = birim == null ? '' : sayiMetni((adet * birim * 100).round() / 100);
  }
  if (iTarih >= 0 && tarih != null) {
    y[iTarih] = '${tarih.day.toString().padLeft(2, '0')}.'
        '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';
  }
  return y.join('\t');
}
