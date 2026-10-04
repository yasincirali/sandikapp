/// Fon para akışı özeti (Balina B1, 2026-10-04) — SAF hesap.
///
/// Veri sunucudan gelir (`fon_akis_gunluk`, `balina_olay`; 0106). Günlük net
/// akışı ve "büyük giriş/çıkış" kararını SUNUCU verir (`_shared/balina.ts`);
/// burada yalnızca gösterim için toplanır: haftalara bölme, son haftanın
/// toplamı, dönem oranları, yatırımcı sayısı farkı, ardışık olay günlerinin
/// tek satırda birleşmesi. Kural burada yeniden yazılmaz — kart, olay
/// listesi ve ileride bildirim aynı satırı okumalı.
///
/// ## Dönem oranı = akış / dönem BAŞINDAKİ büyüklük
/// ₺50 mn giriş 500 mn'lik fonda büyük, 50 mr'lik fonda gürültüdür; mutlak
/// tutar fonlar arasında kıyaslanamaz. Fon akışı raporlamasında yerleşik
/// ölçü budur ("organik büyüme"). Büyüklük değişimi ikiye ayrılır: para
/// akışının payı ve kalan (fiyat etkisi) — "fon büyüdü" ile "fona para
/// girdi" aynı şey değildir, kart ikisini ayrı söyler.
///
/// ## Neden "son hafta", "bu hafta" değil
/// Fon fiyatı bir gün gecikmeli yayınlanır; Pazartesi sabahı içinde bulunulan
/// haftanın hiç verisi yoktur. Kart, verisi olan EN YENİ haftayı gösterir ve
/// tarih aralığını yazar — "bu hafta ₺0" diye yanlış bir sayı çıkmaz.
///
/// ## Ne zaman özet kurulmaz (`null`)
///   · hiç akış satırı yok (fon yeni izlenmeye başlandı),
///   · en yeni veri [bayatlikSiniri]'ndan eski (kaynak durmuş: eski sayıyı
///     güncel gibi göstermektense kart hiç çizilmez).
/// Test: `test/fon_akisi_test.dart`.
library;

/// Bir fonun bir günü (`fon_akis_gunluk` satırı).
class FonAkisGunu {
  const FonAkisGunu({
    required this.tarih,
    required this.portfoyDegeri,
    this.netAkis,
    this.yatirimci,
  });

  /// Fiyatın ait olduğu gün (saat bileşeni yok).
  final DateTime tarih;

  /// Fon toplam değeri, TL.
  final double portfoyDegeri;

  /// O gün fona giren (+) / çıkan (−) para, TL. Önceki gün bilinmiyorsa null.
  final double? netAkis;

  /// Yatırımcı sayısı; sunucu o güne ait olduğunu kanıtlayamadıysa null.
  final int? yatirimci;

  /// Sunucu satırından; bozuk satır `null` (çağıran atlar).
  static FonAkisGunu? satirdan(Map<String, dynamic> r) {
    final tarih = _gun(r['tarih']);
    final deger = (r['portfoy_degeri'] as num?)?.toDouble();
    if (tarih == null || deger == null || !deger.isFinite || deger <= 0) {
      return null;
    }
    final akis = (r['net_akis'] as num?)?.toDouble();
    final kisi = (r['yatirimci'] as num?)?.toInt();
    return FonAkisGunu(
      tarih: tarih,
      portfoyDegeri: deger,
      netAkis: akis != null && akis.isFinite ? akis : null,
      yatirimci: kisi != null && kisi >= 0 ? kisi : null,
    );
  }
}

/// Kurala uyan bir gün (`balina_olay` satırı).
class FonBalinaOlayi {
  const FonBalinaOlayi({
    required this.tarih,
    required this.tutar,
    required this.buyuklukOrani,
    required this.sapmaKati,
    this.yatirimciDegisimi,
    this.ilkGun,
    this.gunSayisi = 1,
  });

  /// Olayın (birleşmişse SON) günü.
  final DateTime tarih;

  /// Birleşmiş olayın ilk günü; tek günlük olayda null.
  final DateTime? ilkGun;

  /// Ardışık kaç işlem günü birleşti (1 = tek gün).
  final int gunSayisi;

  /// Net akış, TL; girişte artı, çıkışta eksi.
  final double tutar;

  /// |tutar| / fon büyüklüğü (0,031 = %3,1).
  final double buyuklukOrani;

  /// |tutar| / fonun olağan günlük hareketi (standart sapma).
  final double sapmaKati;

  /// O gün yatırımcı sayısındaki değişim; iki günün sayısı da biliniyorsa.
  final int? yatirimciDegisimi;

  bool get giris => tutar > 0;

  static FonBalinaOlayi? satirdan(Map<String, dynamic> r) {
    final tarih = _gun(r['tarih']);
    final tutar = (r['tutar'] as num?)?.toDouble();
    final oran = (r['buyukluk_orani'] as num?)?.toDouble();
    final kat = (r['sapma_kati'] as num?)?.toDouble();
    if (tarih == null ||
        tutar == null ||
        oran == null ||
        kat == null ||
        !tutar.isFinite ||
        tutar == 0 ||
        !(oran > 0) ||
        !(kat > 0)) {
      return null;
    }
    return FonBalinaOlayi(
        tarih: tarih, tutar: tutar, buyuklukOrani: oran, sapmaKati: kat);
  }

  FonBalinaOlayi _yatirimciyla(int? degisim) => FonBalinaOlayi(
        tarih: tarih,
        tutar: tutar,
        buyuklukOrani: buyuklukOrani,
        sapmaKati: sapmaKati,
        yatirimciDegisimi: degisim,
      );

  /// Bir sonraki işlem günündeki aynı yönlü olayla birleşim. Tutar ve oran
  /// toplanır (iki günde çıkan para), kat en yükseği; yatırımcı farkı yalnız
  /// iki günün de farkı biliniyorsa toplanır.
  FonBalinaOlayi _birles(FonBalinaOlayi sonraki) => FonBalinaOlayi(
        tarih: sonraki.tarih,
        ilkGun: ilkGun ?? tarih,
        gunSayisi: gunSayisi + sonraki.gunSayisi,
        tutar: tutar + sonraki.tutar,
        buyuklukOrani: buyuklukOrani + sonraki.buyuklukOrani,
        sapmaKati:
            sapmaKati > sonraki.sapmaKati ? sapmaKati : sonraki.sapmaKati,
        yatirimciDegisimi:
            yatirimciDegisimi != null && sonraki.yatirimciDegisimi != null
                ? yatirimciDegisimi! + sonraki.yatirimciDegisimi!
                : null,
      );
}

/// Bir dönemin (1 ay, 3 ay) para akışı ve büyüklük değişiminin ayrıştırması.
class DonemAkisi {
  const DonemAkisi({
    required this.para,
    required this.paraOrani,
    required this.toplamDegisim,
  });

  /// Dönemdeki net akış, TL.
  final double para;

  /// [para] / dönem başındaki fon büyüklüğü (0,043 = %4,3).
  final double paraOrani;

  /// Fon büyüklüğünün dönemdeki toplam değişimi (oran).
  final double toplamDegisim;

  /// Büyüklük değişiminin para akışıyla açıklanmayan kısmı.
  double get fiyatEtkisi => toplamDegisim - paraOrani;

  /// Oran ve ayrıştırma okunabilir mi? Akış ya da değişim dönem başındaki
  /// büyüklüğü AŞTIYSA (fon birkaç katına çıkmış ya da boşalmış) "dönem
  /// başına oran" anlamını yitirir: gerçek veride +%3.014 akış ve −%363
  /// "fiyat etkisi" çıktı (DOH, 2026-09; emülatör 2026-10-04). O durumda
  /// yalnız tutar gösterilir.
  bool get oranAnlamli => paraOrani.abs() <= 1 && toplamDegisim.abs() <= 1;
}

/// Üst üste aynı yönde akan haftalar (en az iki).
class HaftaSerisi {
  const HaftaSerisi({required this.hafta, required this.giris});
  final int hafta;
  final bool giris;
}

/// Bir haftanın toplam net akışı.
class HaftaAkisi {
  const HaftaAkisi({required this.baslangic, required this.net});

  /// Haftanın Pazartesi'si.
  final DateTime baslangic;

  /// Haftadaki günlük akışların toplamı; o hafta hiç akış satırı yoksa null
  /// (çubuk çizilmez — sıfır çizmek "para girmedi" demek olurdu).
  final double? net;
}

class FonAkisOzeti {
  const FonAkisOzeti({
    required this.haftalar,
    required this.sonHaftaNet,
    required this.sonHaftaIlkGun,
    required this.veriTarihi,
    required this.buyukluk,
    required this.yatirimci,
    required this.yatirimciDegisimi,
    required this.olaylar,
    this.ay1,
    this.ay3,
    this.seri,
  });

  /// Son 30 / 90 günün akışı; dönem eksiksiz kurulamıyorsa null.
  final DonemAkisi? ay1;
  final DonemAkisi? ay3;

  /// Son hafta dahil üst üste aynı yönlü hafta sayısı; ikiden azsa null.
  final HaftaSerisi? seri;

  /// [haftaSayisi] hafta, eskiden yeniye; sonuncusu en yeni verinin haftası.
  final List<HaftaAkisi> haftalar;

  /// En yeni haftanın net akışı.
  final double sonHaftaNet;

  /// En yeni haftada akışı olan ilk gün (aralığın başı).
  final DateTime sonHaftaIlkGun;

  /// En yeni verinin günü (aralığın sonu ve "veri tarihi").
  final DateTime veriTarihi;

  /// En yeni fon büyüklüğü, TL.
  final double buyukluk;

  /// En yeni günün yatırımcı sayısı; bilinmiyorsa null (satır çizilmez).
  final int? yatirimci;

  /// Bir önceki işlem gününe göre yatırımcı farkı; iki gün de biliniyorsa.
  final int? yatirimciDegisimi;

  /// Son [olayGun] gündeki olaylar, yeniden eskiye, en çok [olayUstu].
  final List<FonBalinaOlayi> olaylar;
}

/// Grafikteki hafta sayısı.
const int haftaSayisi = 8;

/// Olay listesinin kapsadığı gün ve satır üst sınırı.
const int olayGun = 30;
const int olayUstu = 4;

/// En yeni veri bundan eskiyse kart çizilmez. Uzun bayram (9 gün) + hafta
/// sonu + yayın gecikmesi sığar; bundan uzunu kaynağın durduğunu gösterir.
const Duration bayatlikSiniri = Duration(days: 12);

/// İstemcinin sunucudan isteyeceği geriye dönük süre: 3 aylık dönem (90
/// gün) + dönem başını bulmak için pay. ~75 satır.
const Duration akisSorguPenceresi = Duration(days: 105);

/// Dönem başı satırı hedef günden en çok bu kadar eski olabilir (hafta sonu
/// + bayram). Daha eskiyse dönem "1 ay" değildir; oran verilmez.
const int _donemBasiPayi = 9;

/// Günlük satırlardan ve olaylardan kart özeti. Bkz. dosya başlığı.
FonAkisOzeti? fonAkisOzeti(
  List<FonAkisGunu> gunler,
  List<FonBalinaOlayi> olaylar, {
  required DateTime simdi,
}) {
  final sirali = [...gunler]..sort((a, b) => a.tarih.compareTo(b.tarih));
  final akisli = [
    for (final g in sirali)
      if (g.netAkis != null) g,
  ];
  if (akisli.isEmpty) return null;

  final son = sirali.last;
  if (_gunBasi(simdi).difference(son.tarih) > bayatlikSiniri) return null;

  // En yeni AKIŞLI günün haftası "son hafta"dır; ondan geriye 8 hafta.
  final sonHaftaBasi = _pazartesi(akisli.last.tarih);
  final toplam = <DateTime, double>{};
  for (final g in akisli) {
    final h = _pazartesi(g.tarih);
    toplam[h] = (toplam[h] ?? 0) + g.netAkis!;
  }
  final haftalar = [
    for (var i = haftaSayisi - 1; i >= 0; i--)
      () {
        final h = _gunEkle(sonHaftaBasi, -7 * i);
        return HaftaAkisi(baslangic: h, net: toplam[h]);
      }(),
  ];

  final sonHaftaIlk =
      akisli.firstWhere((g) => _pazartesi(g.tarih) == sonHaftaBasi).tarih;

  // Yatırımcı farkı yalnız ARDIŞIK iki satırda da sayı varsa: arada boş gün
  // kalmışsa fark birden çok günün toplamı olurdu.
  int? fark(int i) {
    if (i <= 0) return null;
    final a = sirali[i - 1].yatirimci;
    final b = sirali[i].yatirimci;
    return a != null && b != null ? b - a : null;
  }

  final esik = _gunEkle(son.tarih, -olayGun);
  final gunIndeksi = {
    for (var i = 0; i < sirali.length; i++) sirali[i].tarih: i,
  };
  final pencerede = [
    for (final o in olaylar)
      if (!o.tarih.isBefore(esik) && !o.tarih.isAfter(son.tarih))
        o._yatirimciyla(fark(gunIndeksi[o.tarih] ?? -1)),
  ]..sort((a, b) => a.tarih.compareTo(b.tarih));

  // Ardışık İŞLEM günlerindeki aynı yönlü olaylar tek satır: iki günde çıkan
  // para kullanıcı için tek harekettir (ör. 21 ve 22 Eylül). "Ardışık"
  // takvimle değil satır sırasıyla ölçülür — Cuma ile Pazartesi ardışıktır.
  final birlesik = <FonBalinaOlayi>[];
  for (final o in pencerede) {
    final onceki = birlesik.isEmpty ? null : birlesik.last;
    final i = gunIndeksi[o.tarih];
    final j = onceki == null ? null : gunIndeksi[onceki.tarih];
    if (onceki != null &&
        i != null &&
        j != null &&
        i == j + 1 &&
        onceki.giris == o.giris) {
      birlesik[birlesik.length - 1] = onceki._birles(o);
    } else {
      birlesik.add(o);
    }
  }
  final gosterilen = birlesik.reversed.toList();

  // Üst üste aynı yönlü haftalar, son haftadan geriye. Verisi olmayan ya da
  // sıfır akışlı hafta seriyi keser.
  final sonYon = toplam[sonHaftaBasi]!;
  var seriHafta = 0;
  if (sonYon != 0) {
    for (var h = sonHaftaBasi;; h = _gunEkle(h, -7)) {
      final net = toplam[h];
      if (net == null || net == 0 || (net > 0) != (sonYon > 0)) break;
      seriHafta++;
    }
  }

  return FonAkisOzeti(
    haftalar: haftalar,
    sonHaftaNet: toplam[sonHaftaBasi]!,
    sonHaftaIlkGun: sonHaftaIlk,
    veriTarihi: son.tarih,
    buyukluk: son.portfoyDegeri,
    yatirimci: son.yatirimci,
    yatirimciDegisimi: fark(sirali.length - 1),
    olaylar: gosterilen.take(olayUstu).toList(),
    ay1: _donemAkisi(sirali, 30),
    ay3: _donemAkisi(sirali, 90),
    seri: seriHafta >= 2
        ? HaftaSerisi(hafta: seriHafta, giris: sonYon > 0)
        : null,
  );
}

/// Son haftaya (kartın başlığındaki hafta) düşen ilk büyük hareket; yoksa
/// null. "Haftanın özeti" satırındaki rozet ve sıralama buna bakar.
FonBalinaOlayi? sonHaftaOlayi(FonAkisOzeti ozet) {
  final haftaBasi = ozet.haftalar.last.baslangic;
  for (final o in ozet.olaylar) {
    if (!o.tarih.isBefore(haftaBasi)) return o;
  }
  return null;
}

/// Son [gun] günün akışı. Dönem başı = hedef günde ya da hemen öncesindeki
/// satır; o satırdan sonraki HER günün akışı bilinmeli — eksik gün varsa
/// toplam eksik olurdu, oran verilmez (uydurma yok).
DonemAkisi? _donemAkisi(List<FonAkisGunu> sirali, int gun) {
  final son = sirali.last;
  final hedef = _gunEkle(son.tarih, -gun);
  var bas = -1;
  for (var i = 0; i < sirali.length; i++) {
    if (sirali[i].tarih.isAfter(hedef)) break;
    bas = i;
  }
  if (bas < 0 || bas == sirali.length - 1) return null;
  if (hedef.difference(sirali[bas].tarih).inDays > _donemBasiPayi) return null;

  var para = 0.0;
  for (var i = bas + 1; i < sirali.length; i++) {
    final akis = sirali[i].netAkis;
    if (akis == null) return null;
    para += akis;
  }
  final ilk = sirali[bas].portfoyDegeri;
  return DonemAkisi(
    para: para,
    paraOrani: para / ilk,
    toplamDegisim: (son.portfoyDegeri - ilk) / ilk,
  );
}

/// `2026-10-02` → o günün başı (UTC; saat dilimi kayması günü değiştirmesin).
DateTime? _gun(Object? ham) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${ham ?? ''}');
  if (m == null) return null;
  return DateTime.utc(
      int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

DateTime _gunBasi(DateTime t) => DateTime.utc(t.year, t.month, t.day);

DateTime _gunEkle(DateTime g, int gun) =>
    DateTime.utc(g.year, g.month, g.day + gun);

DateTime _pazartesi(DateTime g) => _gunEkle(g, -(g.weekday - 1));
