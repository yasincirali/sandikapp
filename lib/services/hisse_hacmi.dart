/// Hisse hacim radarı özeti (Balina B2, 2026-10-04) — SAF hesap.
///
/// Veri sunucudan gelir (`hisse_hacim_gunluk`, `balina_olay`; 0104). Hangi
/// günün "olağandışı" olduğuna SUNUCU karar verir (`_shared/hacim.ts`); burada
/// yalnız gösterim için toplanır: son 20 gün, ortalama, son günün katı.
///
/// ## Ortalama = son günden ÖNCEKİ 20 işlem günü
/// Sunucunun olay kuralıyla aynı pencere: kartın yazdığı "ortalamanın 3,2
/// katı" ile olay satırındaki kat aynı sayıdır. 20 önceki gün yoksa ortalama
/// ve kat HİÇ gösterilmez (kısa pencereden ortalama uydurulmaz).
///
/// ## Dil sınırı
/// Hacim yön taşımaz; her işlemin bir alıcısı ve bir satıcısı vardır. Kart
/// "para girdi" demez, "balina" demez; yön yalnız fiyat yönüdür.
/// Test: `test/hisse_hacmi_test.dart`.
library;

class HacimGunu {
  const HacimGunu({
    required this.tarih,
    required this.kapanis,
    required this.paraHacmi,
  });

  final DateTime tarih;
  final double kapanis;

  /// Kapanış × işlem adedi, TL.
  final double paraHacmi;

  static HacimGunu? satirdan(Map<String, dynamic> r) {
    final tarih = _gun(r['tarih']);
    final kapanis = (r['kapanis'] as num?)?.toDouble();
    final para = (r['para_hacmi'] as num?)?.toDouble();
    if (tarih == null ||
        kapanis == null ||
        para == null ||
        !(kapanis > 0) ||
        !(para >= 0) ||
        !para.isFinite) {
      return null;
    }
    return HacimGunu(tarih: tarih, kapanis: kapanis, paraHacmi: para);
  }
}

class HacimOlayi {
  const HacimOlayi({
    required this.tarih,
    required this.yukselis,
    required this.paraHacmi,
    required this.ortalamaKati,
    required this.fiyatDegisim,
  });

  final DateTime tarih;

  /// O gün fiyat yükseldi mi (hacmin yönü DEĞİL).
  final bool yukselis;
  final double paraHacmi;

  /// Para hacmi / önceki 20 günün ortalaması.
  final double ortalamaKati;

  /// Günün kapanış değişimi (0,041 = +%4,1).
  final double fiyatDegisim;

  static HacimOlayi? satirdan(Map<String, dynamic> r) {
    final tarih = _gun(r['tarih']);
    final tur = '${r['tur'] ?? ''}';
    final para = (r['tutar'] as num?)?.toDouble();
    final kat = (r['ortalama_kati'] as num?)?.toDouble();
    final degisim = (r['fiyat_degisim'] as num?)?.toDouble();
    final yukselis = tur == 'hisse_hacim_yukselis';
    if (tarih == null ||
        (!yukselis && tur != 'hisse_hacim_dusus') ||
        para == null ||
        kat == null ||
        degisim == null ||
        !(para > 0) ||
        !(kat > 0)) {
      return null;
    }
    return HacimOlayi(
        tarih: tarih,
        yukselis: yukselis,
        paraHacmi: para,
        ortalamaKati: kat,
        fiyatDegisim: degisim);
  }
}

class HacimOzeti {
  const HacimOzeti({
    required this.gunler,
    required this.sonGun,
    required this.ortalama,
    required this.kat,
    required this.fiyatDegisim,
    required this.olaylar,
  });

  /// Grafikteki günler (en çok [grafikGun]), eskiden yeniye; sonuncusu
  /// [sonGun].
  final List<HacimGunu> gunler;
  final HacimGunu sonGun;

  /// Son günden önceki 20 işlem gününün ortalama para hacmi; yoksa null.
  final double? ortalama;

  /// Son günün para hacmi / [ortalama]; ortalama yoksa null.
  final double? kat;

  /// Son günün kapanış değişimi; önceki gün yoksa null.
  final double? fiyatDegisim;

  /// Son [hacimOlayGun] gündeki olaylar, yeniden eskiye, en çok
  /// [hacimOlayUstu].
  final List<HacimOlayi> olaylar;
}

const int grafikGun = 20;
const int ortalamaGun = 20;
const int hacimOlayGun = 30;
const int hacimOlayUstu = 4;

/// En yeni veri bundan eskiyse kart çizilmez (fon kartıyla aynı sınır).
const Duration hacimBayatlikSiniri = Duration(days: 12);

/// İstemcinin isteyeceği geriye dönük süre: 21 işlem günü + olay penceresi.
const Duration hacimSorguPenceresi = Duration(days: 50);

HacimOzeti? hacimOzeti(
  List<HacimGunu> gunler,
  List<HacimOlayi> olaylar, {
  required DateTime simdi,
}) {
  if (gunler.isEmpty) return null;
  final sirali = [...gunler]..sort((a, b) => a.tarih.compareTo(b.tarih));
  final son = sirali.last;
  final bugun = DateTime.utc(simdi.year, simdi.month, simdi.day);
  if (bugun.difference(son.tarih) > hacimBayatlikSiniri) return null;

  double? ortalama;
  if (sirali.length > ortalamaGun) {
    var toplam = 0.0;
    for (var i = sirali.length - 1 - ortalamaGun; i < sirali.length - 1; i++) {
      toplam += sirali[i].paraHacmi;
    }
    final ort = toplam / ortalamaGun;
    if (ort > 0) ortalama = ort;
  }

  final esik = DateTime.utc(
      son.tarih.year, son.tarih.month, son.tarih.day - hacimOlayGun);
  final gosterilen = [
    for (final o in olaylar)
      if (!o.tarih.isBefore(esik) && !o.tarih.isAfter(son.tarih)) o,
  ]..sort((a, b) => b.tarih.compareTo(a.tarih));

  return HacimOzeti(
    gunler: sirali.length > grafikGun
        ? sirali.sublist(sirali.length - grafikGun)
        : sirali,
    sonGun: son,
    ortalama: ortalama,
    kat: ortalama == null ? null : son.paraHacmi / ortalama,
    fiyatDegisim: sirali.length > 1
        ? son.kapanis / sirali[sirali.length - 2].kapanis - 1
        : null,
    olaylar: gosterilen.take(hacimOlayUstu).toList(),
  );
}

DateTime? _gun(Object? ham) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${ham ?? ''}');
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}
