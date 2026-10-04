/// Fon para akışı özeti (Balina B1, 2026-10-04) — SAF hesap.
///
/// Veri sunucudan gelir (`fon_akis_gunluk`, `balina_olay`; 0103). Günlük net
/// akışı ve "büyük giriş/çıkış" kararını SUNUCU verir (`_shared/balina.ts`);
/// burada yalnızca gösterim için toplanır: haftalara bölme, son haftanın
/// toplamı, yatırımcı sayısı farkı. Kural burada yeniden yazılmaz — kart,
/// olay listesi ve ileride bildirim aynı satırı okumalı.
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
  });

  final DateTime tarih;

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
  });

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

/// İstemcinin sunucudan isteyeceği geriye dönük süre: 8 hafta + pay.
const Duration akisSorguPenceresi = Duration(days: 63);

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
  final gosterilen = [
    for (final o in olaylar)
      if (!o.tarih.isBefore(esik) && !o.tarih.isAfter(son.tarih))
        o._yatirimciyla(fark(gunIndeksi[o.tarih] ?? -1)),
  ]..sort((a, b) => b.tarih.compareTo(a.tarih));

  return FonAkisOzeti(
    haftalar: haftalar,
    sonHaftaNet: toplam[sonHaftaBasi]!,
    sonHaftaIlkGun: sonHaftaIlk,
    veriTarihi: son.tarih,
    buyukluk: son.portfoyDegeri,
    yatirimci: son.yatirimci,
    yatirimciDegisimi: fark(sirali.length - 1),
    olaylar: gosterilen.take(olayUstu).toList(),
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
