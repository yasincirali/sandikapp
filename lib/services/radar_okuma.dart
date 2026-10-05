/// Radar kartlarının "okunuşu" (Balina F1 tamamlama, 2026-10-05) — SAF.
///
/// ## Neden ayrı bir dosya
/// Kullanıcı kararı (2026-10-05): *"heryere açıklama düzenlemek yerine bir ux
/// deneyimi oluşturmalısın"*. Kartlardaki açıklama paragrafları kalktı; yerine
/// her kartın tepesinde veriden üretilen düz bir cümle ve üç kademeli bir
/// ölçek geldi ("sakin / hareketli / çok hareketli"). Cümle ile ölçek AYNI
/// sayıdan, aynı kuralla çıkmalı — kart "olağandan fazla para girdi" derken
/// ölçek "sakin" gösteremez, sayı eksiyken cümle "girdi" diyemez. Bu yüzden
/// karar widget'ta değil burada, tek yerde ve testli
/// (`test/radar_okuma_test.dart`).
///
/// ## Ölçek neye göre: varlığın KENDİ olağanı
/// "₺412 mn" tek başına büyük mü küçük mü belli değil; 50 mr'lik fonda
/// gürültü, 500 mn'lik fonda haber. Mutlak eşik yerine her varlık kendi
/// geçmişiyle kıyaslanır:
///   · fon: son haftanın |net akışı| / önceki haftaların |net akışı| ortalaması,
///   · hisse/kripto hacmi: son günün hacmi / önceki 20 günün ortalaması
///     (sunucudaki olay kuralının penceresi),
///   · kripto alıcı payı: %50'den uzaklık (yön değil, isteğin şiddeti).
/// Geçmiş yetmiyorsa ölçek HİÇ verilmez (`null`) — kısa pencereden "olağan"
/// uydurulmaz; kart yalnız yönü söyler.
///
/// ## Eşikler
/// Sunucunun "büyük hareket / olağandışı hacim" kuralıyla çelişmeyecek
/// biçimde: sunucu bir olay işaretlediyse kademe her zaman en üsttedir
/// (rozet "Büyük giriş" iken ölçek "hareketli" göstermesin). Olay yoksa
/// oran eşikleri uygulanır; olay kuralından gevşektir, çünkü ölçek "haber"
/// değil "bağlam" verir.
library;

import 'fon_akisi.dart';
import 'hisse_hacmi.dart';

/// Varlığın kendi olağanına göre hareketin şiddeti.
enum Kademe { sakin, hareketli, cokHareketli }

/// Yön: kart cümlesinin öznesi ve renk.
enum Yon { giris, cikis, denge }

/// Fon kademesi eşikleri: son hafta / önceki haftaların ortalaması.
const double fonHareketliKat = 1.5;
const double fonCokHareketliKat = 3;

/// Ortalamanın kurulabilmesi için gereken en az önceki hafta.
const int fonAsgariHafta = 3;

/// Hacim kademesi eşikleri: son gün / önceki 20 gün ortalaması. Sunucu olay
/// kuralı kat ≥ 2 VE z ≥ 3 (`_shared/hacim.ts`); ölçek yalnız katı kullanır.
const double hacimHareketliKat = 1.3;
const double hacimCokHareketliKat = 2;

/// Kripto alıcı payının %50'den uzaklığı. Sunucudaki not rozeti 0,55 / 0,45
/// (`_shared/analiz.ts`): "çok" kademesi onunla aynı sınırda başlar.
const double kriptoHareketliFark = 0.02;
const double kriptoCokHareketliFark = 0.05;

/// Fon kartının okunuşu.
class FonOkunusu {
  const FonOkunusu(
      {required this.yon, this.kademe, this.kat, this.karsiYonOlay = false});

  final Yon yon;

  /// Haftanın büyük hareketi net yönün TERSİ (ör. Pazartesi büyük çıkış,
  /// hafta toplamı yine giriş). Cümle o zaman yön söylemez: "olağanın çok
  /// üstünde para girdi" yazıp altına "Büyük çıkış" rozeti koymak çelişir.
  final bool karsiYonOlay;

  /// `null` = geçmiş yetmedi, ölçek çizilmez.
  final Kademe? kademe;

  /// Son hafta / olağan hafta (|net|). Ayrıntı ekranında "olağanın N katı".
  final double? kat;
}

/// Son haftanın yönü ve kademesi. Son haftada büyük hareket (sunucu olayı)
/// varsa kademe en üst.
FonOkunusu fonOkunusu(FonAkisOzeti o) {
  final net = o.sonHaftaNet;
  final yon = net > 0
      ? Yon.giris
      : net < 0
          ? Yon.cikis
          : Yon.denge;
  final onceki = [
    for (final h in o.haftalar.take(o.haftalar.length - 1))
      if (h.net != null) h.net!.abs(),
  ];
  double? kat;
  if (onceki.length >= fonAsgariHafta) {
    final ort = onceki.reduce((a, b) => a + b) / onceki.length;
    if (ort > 0) kat = net.abs() / ort;
  }
  final olay = sonHaftaOlayi(o);
  final Kademe? kademe;
  if (olay != null) {
    kademe = Kademe.cokHareketli;
  } else if (kat == null) {
    kademe = null;
  } else {
    kademe = _katKademesi(kat, fonHareketliKat, fonCokHareketliKat);
  }
  return FonOkunusu(
    yon: yon,
    kademe: kademe,
    kat: kat,
    karsiYonOlay: olay != null && yon != (olay.giris ? Yon.giris : Yon.cikis),
  );
}

/// Hisse/kripto hacminin okunuşu: kademe son günün katından; son gün
/// olağandışı hacim günüyse en üst.
Kademe? hacimKademesi(HacimOzeti o) {
  if (o.olaylar.any((x) => x.tarih == o.sonGun.tarih)) {
    return Kademe.cokHareketli;
  }
  final kat = o.kat;
  if (kat == null) return null;
  return _katKademesi(kat, hacimHareketliKat, hacimCokHareketliKat);
}

/// Kripto alıcı payının okunuşu.
class KriptoOkunusu {
  const KriptoOkunusu({required this.yon, required this.kademe});

  /// giris = alıcılar daha istekli, cikis = satıcılar, denge = ±2 puan içinde.
  final Yon yon;
  final Kademe kademe;
}

KriptoOkunusu? kriptoOkunusu(HacimOzeti o) {
  final p = o.aliciPayi;
  if (p == null) return null;
  // Kayan nokta payı: 0,45 − 0,5 = −0,04999… çıkar; sunucu rozeti (≤ 0,45)
  // ile sınırda aynı karar verilmeli.
  final fark = (p - 0.5).abs() + 1e-9;
  final kademe = fark >= kriptoCokHareketliFark
      ? Kademe.cokHareketli
      : fark >= kriptoHareketliFark
          ? Kademe.hareketli
          : Kademe.sakin;
  final yon = kademe == Kademe.sakin
      ? Yon.denge
      : p > 0.5
          ? Yon.giris
          : Yon.cikis;
  return KriptoOkunusu(yon: yon, kademe: kademe);
}

Kademe _katKademesi(double kat, double hareketli, double cok) => kat >= cok
    ? Kademe.cokHareketli
    : kat >= hareketli
        ? Kademe.hareketli
        : Kademe.sakin;

/// Saatlik kripto satırı (`kripto_hacim_saatlik`, 0115).
class KriptoSaati {
  const KriptoSaati(
      {required this.saat, required this.paraHacmi, required this.aliciPayi});

  /// Saatin başı (UTC).
  final DateTime saat;
  final double paraHacmi;
  final double aliciPayi;

  /// Alıcı hacmi − satıcı hacmi, USDT (sunucudaki `netAlim` ile aynı formül).
  double get netAlim => 2 * paraHacmi * aliciPayi - paraHacmi;

  static KriptoSaati? satirdan(Map<String, dynamic> r) {
    final saat = DateTime.tryParse('${r['saat'] ?? ''}');
    final para = (r['para_hacmi'] as num?)?.toDouble();
    final pay = (r['alici_payi'] as num?)?.toDouble();
    if (saat == null ||
        para == null ||
        pay == null ||
        !para.isFinite ||
        para < 0 ||
        pay < 0 ||
        pay > 1) {
      return null;
    }
    return KriptoSaati(saat: saat.toUtc(), paraHacmi: para, aliciPayi: pay);
  }
}

/// Son 24 saatin saatlik net alımı. Pencere en yeni satırın saatinden geriye
/// 24 saat; arada eksik saat BOŞ kalır (sıfır çizilmez). En yeni satır
/// [bayatSaat]'ten eskiyse `null` (kaynak durmuş).
class SaatlikAkis {
  const SaatlikAkis({required this.saatler, required this.enIstekli});

  /// 24 öğe, eskiden yeniye; verisi olmayan saat `null`.
  final List<KriptoSaati?> saatler;

  /// En büyük pozitif net alımlı saat; hiç yoksa null.
  final KriptoSaati? enIstekli;
}

const int bayatSaat = 3;

SaatlikAkis? saatlikAkis(List<KriptoSaati> satirlar,
    {required DateTime simdi}) {
  if (satirlar.isEmpty) return null;
  final sirali = [...satirlar]..sort((a, b) => a.saat.compareTo(b.saat));
  final son = sirali.last.saat;
  if (simdi.toUtc().difference(son).inHours > bayatSaat) return null;
  final harita = {for (final s in sirali) s.saat: s};
  final saatler = [
    for (var i = 23; i >= 0; i--) harita[son.subtract(Duration(hours: i))],
  ];
  KriptoSaati? enIstekli;
  for (final s in saatler.nonNulls) {
    if (s.netAlim > 0 && (enIstekli == null || s.netAlim > enIstekli.netAlim)) {
      enIstekli = s;
    }
  }
  return SaatlikAkis(saatler: saatler, enIstekli: enIstekli);
}

/// Kategori sırası satırı (`fon_kategori_akis_sirasi`, 0115).
class KategoriSirasi {
  const KategoriSirasi({
    required this.sira,
    required this.fonKodu,
    required this.netAkis,
    required this.kendi,
    required this.kategori,
    required this.fonSayisi,
  });

  final int sira;
  final String fonKodu;
  final double netAkis;
  final bool kendi;
  final String kategori;
  final int fonSayisi;

  static KategoriSirasi? satirdan(Map<String, dynamic> r) {
    final sira = (r['sira'] as num?)?.toInt();
    final kod = r['fon_kodu'] as String?;
    final net = (r['net_akis'] as num?)?.toDouble();
    final adet = (r['fon_sayisi'] as num?)?.toInt();
    final kategori = r['kategori'] as String?;
    if (sira == null ||
        kod == null ||
        net == null ||
        adet == null ||
        kategori == null ||
        sira < 1 ||
        adet < 2) {
      return null;
    }
    return KategoriSirasi(
      sira: sira,
      fonKodu: kod,
      netAkis: net,
      kendi: r['kendi'] == true,
      kategori: kategori,
      fonSayisi: adet,
    );
  }
}
