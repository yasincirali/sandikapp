import 'package:flutter/foundation.dart' show immutable;

import '../services/yillik_rapor.dart' show yillikSatisSatiri;
import '../utils/tr_format.dart' show dayKey;
import 'asset.dart';
import 'elde_tutma.dart';
import 'position.dart' show aktifLotlar, positionKey;

/// "Tümünü sat" sonrası kapanış özeti: ne kadar tuttun, ne gerçekleşti.
///
/// ## Neden
/// Pozisyonu kapatan satış, uygulamada iz bırakmadan bitiyordu: sheet
/// kapanıyor, satır listeden düşüyordu. Kullanıcı "bu işten ne çıktı"
/// sorusunun cevabını yıl sonunda raporda görüyordu. Kapanış anı o sorunun
/// sorulduğu an; cevap tek sayfada, bir kez.
///
/// ## Kurallar
/// - **Kâr yıllık raporla aynı sayı.** `yillikSatisSatiri` (satış − maliyet
///   − komisyon, satış günü kuru) okunur; formül burada yeniden yazılmaz.
///   Yüzde aynı satırın maliyetine bölünür.
/// - **Uydurma sayı yok.** Bugünkü elde tutmada maliyeti bilinmeyen alış
///   varsa, kapanan satış satırı "maliyet bilinmiyor" işaretliyse ya da
///   satış fiyatı yoksa tutar ve yüzde `null`: özet yalnız süreyi söyler.
/// - **Yıllık ortalama yalnız ≥ 12 ayda.** Kısa sürede yıllıklandırma
///   yanıltır (bir ayda %5 "yıllık %80" olur). Hesap Varlık ekranının
///   "yıllık ortalama" satırıyla aynı (`eldeTutma`, para ağırlıklı; temettü
///   akışları dahil): satıştan bir gün önce o satırda ne yazıyorsa kapanışta
///   da o yazar. Bugünkü değer yerine satışta ele geçen tutar verilir.
/// - **Süre bugünkü elde tutmadan.** Pozisyon daha önce kapanıp yeniden
///   alındıysa süre YENİ ilk alıştan sayılır (`eldeTutma` ile aynı kural).
///
/// Saf: ağ yok, Flutter yok. Ekran: `kapanis_ozeti_sheet.dart`.
@immutable
class KapanisOzeti {
  const KapanisOzeti({
    required this.ad,
    required this.yil,
    required this.ay,
    required this.gun,
    this.karTry,
    this.karPct,
    this.yillikPct,
  });

  final String ad;

  /// Süre parçaları: 12 aydan uzunsa yıl + ay, bir aydan uzunsa ay, daha
  /// kısaysa gün. Kullanılmayan parça 0. Aynı gün kapanan pozisyonda üçü
  /// de 0 ("bir günden kısa").
  final int yil;
  final int ay;
  final int gun;

  /// Gerçekleşen kâr/zarar (₺) ve maliyete oranı (%); bilinmiyorsa `null`.
  final double? karTry;
  final double? karPct;

  /// Yıllık ortalama getiri (%); yalnız ≥ 12 ay tutulduysa.
  final double? yillikPct;

  /// Paylaş düğmesi ve değerlendirme istemi yalnız kazançta.
  bool get kazanc => (karTry ?? 0) > 0;

  @override
  bool operator ==(Object other) =>
      other is KapanisOzeti &&
      other.ad == ad &&
      other.yil == yil &&
      other.ay == ay &&
      other.gun == gun &&
      other.karTry == karTry &&
      other.karPct == karPct &&
      other.yillikPct == yillikPct;

  @override
  int get hashCode => Object.hash(ad, yil, ay, gun, karTry, karPct, yillikPct);
}

/// Değerlendirme istemi eşiği (%): küçük kazanç "mutlu an" sayılmaz.
const kapanisDegerlendirmeEsigiPct = 5.0;

/// [satis] pozisyonu kapatan satış satırı; [defter] ham defter (satış
/// satırı içinde olabilir, olmayabilir). Pozisyon bu satışla kapanmıyorsa
/// ya da bugünkü elde tutmanın alışı bulunamıyorsa `null`.
KapanisOzeti? kapanisOzeti({
  required Iterable<Asset> defter,
  required Asset satis,
}) {
  if (!satis.isSell) return null;
  final anahtar = positionKey(satis);
  final hareketler = [
    for (final a in defter)
      if (a.id != satis.id &&
          a.isActive &&
          a.userId == satis.userId &&
          (satis.portfoyId == null || a.portfoyId == satis.portfoyId) &&
          (a.isBuy || a.isSell || a.isDividend) &&
          !a.addedDate.isAfter(satis.addedDate) &&
          positionKey(a) == anahtar)
        a,
  ]..sort((x, y) => x.addedDate.compareTo(y.addedDate));

  // Bugünkü elde tutmanın başı: net miktarın son kez sıfıra indiği
  // satıştan sonraki ilk hareket (`eldeTutma` ile aynı yürüyüş).
  var net = 0.0;
  var bas = 0;
  for (var i = 0; i < hareketler.length; i++) {
    final a = hareketler[i];
    if (a.isBuy) net += a.quantity;
    if (a.isSell) {
      net -= a.quantity;
      if (net <= _kirinti) {
        net = 0;
        bas = i + 1;
      }
    }
  }
  // Bu satış pozisyonu kapatmıyorsa özet yok (kısmi satış).
  // Pay göreli: 0,1 + 0,2 gibi ondalık artıkları kısmi satış sayılmasın.
  if ((net - satis.quantity).abs() > 1e-6 * (1 + net)) return null;
  final tur = hareketler.sublist(bas);
  final ilkAlis = tur.where((a) => a.isBuy).firstOrNull;
  if (ilkAlis == null) return null;

  final basGun = dayKey(ilkAlis.addedDate);
  final sonGun = dayKey(satis.addedDate);
  var aylar = (sonGun.year - basGun.year) * 12 + sonGun.month - basGun.month;
  if (sonGun.day < basGun.day) aylar -= 1;
  if (aylar < 0) aylar = 0;
  final gun = aylar == 0 ? sonGun.difference(basGun).inDays : 0;

  final maliyetBilinmiyor =
      satis.maliyetBilinmiyor == true ||
      tur.any((a) => a.isBuy && a.maliyetBilinmiyor == true);
  final satir = maliyetBilinmiyor ? null : yillikSatisSatiri(satis);
  double? karTry;
  double? karPct;
  double? yillikPct;
  if (satir != null && satir.maliyetTry > 0) {
    karTry = satir.karTry;
    karPct = karTry / satir.maliyetTry * 100;
    if (aylar >= 12) {
      yillikPct = eldeTutma(
        lotlar: tur,
        guncelDegerTRY: satir.satisTry - satir.komisyonTry,
        simdi: satis.addedDate,
      )?.yillikPct;
    }
  }
  return KapanisOzeti(
    ad: satis.name,
    yil: aylar >= 12 ? aylar ~/ 12 : 0,
    ay: aylar >= 12 ? aylar % 12 : aylar,
    gun: gun < 0 ? 0 : gun,
    karTry: karTry,
    karPct: karPct,
    yillikPct: yillikPct,
  );
}

/// Ondalık miktar artığı (0,1 + 0,2 − 0,3): bunun altı "kapalı".
const _kirinti = 1e-9;

/// "Sattıkların" listesinin bir satırı: tamamı satılmış pozisyon ve onu
/// kapatan satışın özeti.
@immutable
class KapanmisPozisyon {
  const KapanmisPozisyon({
    required this.anahtar,
    required this.satis,
    required this.ozet,
  });

  /// Sahip + `positionKey` (liste anahtarı).
  final String anahtar;

  /// Pozisyonu son kez kapatan satış satırı.
  final Asset satis;

  final KapanisOzeti ozet;
}

/// Ham defterden kapanmış pozisyonlar, en son kapanan önde.
///
/// ## Neden (Sattıkların, 2026-11-12)
/// Kapanış özeti "Tümünü sat"ın hemen ardından bir kez açılıyordu; sayfa
/// kapanınca kapatılan pozisyonun ne kazandırdığına bakmanın yolu yoktu.
/// Liste aynı özeti ([kapanisOzeti]) yeniden kurar: ikinci formül yok,
/// sayı kapanış anında görülenle aynı.
///
/// ## Kurallar
/// - **Kapanmış = ham defterde satış var VE `aktifLotlar` boş** (CLAUDE.md
///   "Kapanmış pozisyon"). Kısmi satış listeye girmez; kapanıp yeniden
///   alınan pozisyon bugün açık olduğu için girmez.
/// - Silinmiş pozisyon (lotları `deletedAt`lı) girmez: kullanıcı onu
///   sildi, satmadı.
/// - Sahip başına gruplanır: `positionKey` sahip taşımaz; durumda ortak
///   lotları da bulunabilir.
/// - Özet en SON kapanıştan: pozisyon iki kez açılıp kapandıysa son tur.
///   Aynı anda kaydedilmiş birden çok satış varsa kapatanı bulunana kadar
///   denenir.
/// - Maliyet bilinmiyorsa özet yalnız süreyi taşır (uydurma sayı yok);
///   alışı bulunamayan (yalnız satış satırı olan) pozisyon listeye girmez.
List<KapanmisPozisyon> kapanmisPozisyonlar(Iterable<Asset> defter) {
  final gruplar = <String, List<Asset>>{};
  for (final a in defter) {
    if (!a.isActive || !(a.isBuy || a.isSell || a.isDividend)) continue;
    gruplar.putIfAbsent('${a.userId}|${positionKey(a)}', () => []).add(a);
  }
  final sonuc = <KapanmisPozisyon>[];
  gruplar.forEach((anahtar, lotlar) {
    final satislar = [
      for (final a in lotlar)
        if (a.isSell) a,
    ];
    if (satislar.isEmpty || aktifLotlar(lotlar).isNotEmpty) return;
    satislar.sort((x, y) => y.addedDate.compareTo(x.addedDate));
    final son = satislar.first.addedDate;
    for (final s in satislar.takeWhile((s) => s.addedDate == son)) {
      final ozet = kapanisOzeti(defter: lotlar, satis: s);
      if (ozet != null) {
        sonuc.add(KapanmisPozisyon(anahtar: anahtar, satis: s, ozet: ozet));
        return;
      }
    }
  });
  sonuc.sort((x, y) => y.satis.addedDate.compareTo(x.satis.addedDate));
  return sonuc;
}

/// "Sattıkların" sayfasının başındaki özet: gerçekleşen toplam ve neyin
/// toplama girmediği.
@immutable
class SattiklarinToplami {
  const SattiklarinToplami({
    required this.karTry,
    required this.bilinen,
    required this.bilinmeyen,
  });

  /// Maliyeti bilinen pozisyonların gerçekleşen kâr/zarar toplamı (₺).
  /// Hiçbirinin maliyeti bilinmiyorsa `null`: sıfır yazmak "başa baş"
  /// demek olurdu (uydurma sayı yok).
  final double? karTry;

  /// Toplama giren / girmeyen pozisyon sayısı.
  final int bilinen;
  final int bilinmeyen;

  @override
  bool operator ==(Object other) =>
      other is SattiklarinToplami &&
      other.karTry == karTry &&
      other.bilinen == bilinen &&
      other.bilinmeyen == bilinmeyen;

  @override
  int get hashCode => Object.hash(karTry, bilinen, bilinmeyen);
}

/// [liste]'nin gerçekleşen toplamı (Sattıkların özet satırı, 2026-11-13).
///
/// ## Kurallar
/// - **Satırlarla aynı sayı.** Her satırın [KapanisOzeti.karTry]'si
///   toplanır; ikinci formül yok. Satırlar zaten ₺: `yillikSatisSatiri`
///   yabancı para birimli satışı satış günü kuruyla TL'ye çevirir, yani
///   karışık para birimi listede TL karşılığı olarak durur. Toplam da o
///   TL karşılıklarının toplamıdır; kendi kur çevirisi yapmaz.
/// - **Maliyeti bilinmeyen toplama girmez** (`karTry == null`), sayısı
///   [SattiklarinToplami.bilinmeyen]'de döner: ekran onu dipnotla söyler,
///   toplam sessizce eksik kalmaz.
/// - Saf: Flutter yok; ekran `build()` içinde yürümez, provider önbelleğe
///   alır (`sattiklarinToplamiProvider`).
SattiklarinToplami sattiklarinToplami(Iterable<KapanmisPozisyon> liste) {
  var toplam = 0.0;
  var bilinen = 0;
  var bilinmeyen = 0;
  for (final k in liste) {
    final kar = k.ozet.karTry;
    if (kar == null) {
      bilinmeyen++;
    } else {
      toplam += kar;
      bilinen++;
    }
  }
  return SattiklarinToplami(
    karTry: bilinen == 0 ? null : toplam,
    bilinen: bilinen,
    bilinmeyen: bilinmeyen,
  );
}
