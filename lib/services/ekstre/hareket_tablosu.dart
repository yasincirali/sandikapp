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

/// Varlık satırlarını hareketlerle incelt: dönem içindeki alım ve
/// satımlar gerçek tarih ve fiyatıyla ayrı satır olur. Satırlar
/// `kanonikSatirlar` düzeninde (sekmeli).
///
/// ## Kural (çift sayım yok)
/// Varlık tablosu dönem sonunda NE KADAR olduğunu söyler (E), hareketler
/// dönem içinde NE ZAMAN ve KAÇA alınıp satıldığını (alış toplamı a,
/// satış toplamı s). Dönem başındaki adet bundan çıkar: açılış = E − a + s.
/// - Satışsız kod: alışlar ayrı satır, kalan (açılış) adet varlık
///   satırında ekstre günü ve fiyatıyla kalır (2026-10-05 davranışı).
/// - Satışlı kod (2026-10-13, yasin: "içinden varlık alım satımlarını
///   çıkaramıyor"): açılış adedi ilk hareket gününe, fiyatı BOŞ yazılır —
///   toplu kayıt o günün kapanışını çeker (uydurma fiyat yok); ardından
///   bütün alış ve satışlar tarih sırasıyla. Defter dönem sonunda yine E
///   tutar; satış, elde olanı aşmadığı için `IceAktarmaSatislari`'ndan
///   geçer.
/// - Açılış negatifse ya da sıralı yürüyüşte bir satış eldekini aşıyorsa
///   (hareket başka hesaptan, ya da liste eksik) kod DOKUNULMAZ: varlık
///   satırı olduğu gibi kalır. Tahminle defter kurulmaz.
///
/// ## Varlık tablosunda olmayan kod
/// Dönem içinde tamamen satılmış fon/hisse varlık tablosunda yer almaz;
/// eski sürüm bu yüzden satışları hiç göstermiyordu. Yalnız [bilinenKodlar]
/// içindeki kod alınır (değer: `tur` hücresi, ör. "Fon"); "FON5" gibi
/// bankanın iç süpürme fonu bilinmediği için yine hiçbir yere girmez.
/// [varlikTablosuVar] ise kodun dönem sonu adedi 0 sayılır (açılış =
/// s − a); yoksa (yalnız hareket listesi) dönem sonu bilinmez ve açılış,
/// satışları karşılayan EN KÜÇÜK adettir — satış varsa o pay vardı.
({List<String> satirlar, int incelen}) hareketlerleIncelt(
  List<String> satirlar,
  List<EkstreRol> sutunlar,
  List<EkstreHareketi> hareketler, {
  Map<String, String> bilinenKodlar = const {},
  bool varlikTablosuVar = true,
}) {
  final iSembol = sutunlar.indexOf(EkstreRol.sembol);
  final iAdet = sutunlar.indexOf(EkstreRol.adet);
  if (hareketler.isEmpty || iSembol < 0 || iAdet < 0) {
    return (satirlar: satirlar, incelen: 0);
  }
  final ix = _Sutunlar(
    adet: iAdet,
    fiyat: sutunlar.indexOf(EkstreRol.fiyat),
    tutar: sutunlar.indexOf(EkstreRol.tutar),
    tarih: sutunlar.indexOf(EkstreRol.tarih),
    yon: sutunlar.indexOf(EkstreRol.yon),
  );
  final kodlu = <String, List<EkstreHareketi>>{};
  for (final h in hareketler) {
    kodlu.putIfAbsent(h.kod.toUpperCase(), () => []).add(h);
  }
  final out = <String>[];
  final islenen = <String>{};
  var incelen = 0;
  for (final satir in satirlar) {
    final h = satir.split('\t');
    final kod = h[iSembol].trim().toUpperCase();
    final hs = kodlu[kod];
    final eldeki = sayiCoz(h[iAdet]);
    final yon = ix.yon < 0 ? '' : h[ix.yon];
    if (hs == null || eldeki == null || yon == 'Satış' || islenen.contains(kod)) {
      out.add(satir);
      continue;
    }
    final d = _Defter(hs);
    final acilis = eldeki - d.alis + d.satis;
    if (acilis < d.acik - 1e-6) {
      out.add(satir);
      continue;
    }
    islenen.add(kod);
    incelen++;
    if (d.satis == 0) {
      for (final x in d.sirali) {
        out.add(_kopya(h, ix, x.adet, x.fiyat, x.tarih, satis: false));
      }
      if (acilis > 1e-6) {
        final fiyat = ix.fiyat < 0 ? null : sayiCoz(h[ix.fiyat]);
        out.add(_kopya(h, ix, acilis, fiyat, null, satis: false,
            fiyatYaz: false));
      }
    } else {
      out.addAll(_hareketSatirlari(h, ix, d, acilis));
    }
  }
  for (final MapEntry(key: kod, value: hs) in kodlu.entries) {
    final tur = bilinenKodlar[kod];
    if (tur == null || islenen.contains(kod)) continue;
    final d = _Defter(hs);
    final acilis = varlikTablosuVar ? d.satis - d.alis : d.acik;
    if (acilis < d.acik - 1e-6) continue;
    incelen++;
    final sablon = List.filled(sutunlar.length, '');
    sablon[iSembol] = kod;
    final iTur = sutunlar.indexOf(EkstreRol.tur);
    if (iTur >= 0) sablon[iTur] = tur;
    final iPara = sutunlar.indexOf(EkstreRol.paraBirimi);
    if (iPara >= 0) sablon[iPara] = 'TRY';
    out.addAll(_hareketSatirlari(sablon, ix, d, acilis));
  }
  return (satirlar: out, incelen: incelen);
}

/// Açılış (varsa, ilk hareket gününde, fiyatsız) + tarih sıralı hareketler.
Iterable<String> _hareketSatirlari(
    List<String> h, _Sutunlar ix, _Defter d, double acilis) sync* {
  if (acilis > 1e-6) {
    yield _kopya(h, ix, acilis, null, d.sirali.first.tarih, satis: false);
  }
  for (final x in d.sirali) {
    yield _kopya(h, ix, x.adet, x.fiyat, x.tarih, satis: x.satis);
  }
}

class _Sutunlar {
  const _Sutunlar({
    required this.adet,
    required this.fiyat,
    required this.tutar,
    required this.tarih,
    required this.yon,
  });
  final int adet, fiyat, tutar, tarih, yon;
}

/// Bir kodun dönem içi hareketleri: toplamlar ve sıralı yürüyüşte
/// satışların karşılanması için gereken en küçük açılış ([acik]).
class _Defter {
  _Defter(List<EkstreHareketi> hs)
      : sirali = [...hs]
          // Aynı gün önce alış: gün içi sıra ekstrede yok, satış da toplu
          // kayıtta gün sonuna kadarki alışlarla karşılanır.
          ..sort((a, b) {
            final t = a.tarih.compareTo(b.tarih);
            if (t != 0) return t;
            return (a.satis ? 1 : 0) - (b.satis ? 1 : 0);
          }) {
    var bakiye = 0.0;
    for (final x in sirali) {
      if (x.satis) {
        satis += x.adet;
        bakiye -= x.adet;
        if (-bakiye > acik) acik = -bakiye;
      } else {
        alis += x.adet;
        bakiye += x.adet;
      }
    }
  }

  final List<EkstreHareketi> sirali;
  double alis = 0, satis = 0, acik = 0;
}

/// [fiyat] `null`: fiyat ve tutar boş yazılır (toplu kayıt o günün
/// kapanışını çeker). [fiyatYaz] `false`: varlık satırının kendi fiyatı
/// kalır (ekstre günü fiyatı). [tarih] `null`: satırın tarihi kalır.
String _kopya(List<String> h, _Sutunlar ix, double adet, double? fiyat,
    DateTime? tarih,
    {required bool satis, bool fiyatYaz = true}) {
  final y = [...h];
  y[ix.adet] = sayiMetni(adet);
  if (fiyatYaz && ix.fiyat >= 0) {
    y[ix.fiyat] = fiyat == null ? '' : sayiMetni(fiyat);
  }
  if (ix.tutar >= 0) {
    y[ix.tutar] =
        fiyat == null ? '' : sayiMetni((adet * fiyat * 100).round() / 100);
  }
  if (ix.tarih >= 0 && tarih != null) {
    y[ix.tarih] = '${tarih.day.toString().padLeft(2, '0')}.'
        '${tarih.month.toString().padLeft(2, '0')}.${tarih.year}';
  }
  if (ix.yon >= 0) y[ix.yon] = satis ? 'Satış' : 'Alış';
  return y.join('\t');
}
