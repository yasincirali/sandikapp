// "Bugün" kartının hesabı — SAF.
//
// Neden var (2026-09-20): ana ekran her gün aynı görünüyordu. Bir takip
// uygulamasında kullanıcının yapacak "işi" yok, yalnızca bakacak şeyi var;
// aynı görünen ekrana ikinci gün gelinmez. Bu kart her açılışta değişen
// tek bir yüzey verir: bugünün hareketi (ya da piyasa ne zaman açılır),
// günün içgörüsü (dönüşümlü) ve ayın ilk günlerinde aylık özet girişi.
//
// İlkeler (RETENTION_STRATEJISI §3, §8):
//   · Her satır bir BİLGİ taşır; "bugün de uğra" tarzı boş çağrı yok.
//   · Kayıp gününde bağırmaz: düşüş de aynı sakin satırdır, renk söyler.
//   · Streak / rozet yağmuru yok. Dönüşüm, aynı bilgiyi her gün
//     tekrarlamamak için; kullanıcıyı "kaçırma" hissiyle çekmek için değil.
//
// Widget tarafı `widgets/bugun_karti.dart`; burası ağ ve BuildContext bilmez
// ki `test/bugun_service_test.dart` takvimi ve dönüşümü sınayabilsin.
import '../utils/tr_format.dart' show dayKey;
import 'bist_calendar.dart';
import 'daily_summary.dart';

/// Yaklaşan olay türleri — hepsi ULUSAL takvimden, uydurma sebep yok.
enum BugunOlayTuru {
  /// TÜİK enflasyonu ayın 3'ünde 10:00'da açıklar; reel getiri rozeti
  /// o gün değişir.
  tuikAciklamasi,

  /// BIST resmî tatil (`BistTakvimi`); "neden fiyatlar değişmiyor"
  /// sorusunu önceden yanıtlar.
  bistTatili,

  /// Ay sonu — aylık özetin hazır olacağı gün.
  aySonu,
}

sealed class BugunSatiri {
  const BugunSatiri();
}

/// Bugünün ölçülmüş değişimi (nakit akışından arındırılmış, kilit ekranı
/// ve widget ile aynı hesap — `DailySummary`).
class GunlukDegisimSatiri extends BugunSatiri {
  const GunlukDegisimSatiri({required this.changeTRY, required this.changePct});
  final double changeTRY;
  final double changePct;

  /// Yuvarlanınca sıfır: yön taşımaz, "değişmedi" diye okunur.
  bool get flat => changeTRY.abs().round() == 0 && changePct.abs() < 0.005;
}

/// Seans kapalı — bir sonraki açılış anı.
class PiyasaKapaliSatiri extends BugunSatiri {
  const PiyasaKapaliSatiri({required this.sonrakiAcilis});
  final DateTime sonrakiAcilis;
}

/// Kaç varlık artıda (ömürlük kâr/zarar üzerinden).
class YesilOranSatiri extends BugunSatiri {
  const YesilOranSatiri({required this.yesil, required this.toplam});
  final int yesil;
  final int toplam;
}

/// Portföy hedefi: `hedefTRY <= 0` ise "hedef belirle" çağrısıdır.
class HedefSatiri extends BugunSatiri {
  const HedefSatiri({required this.hedefTRY, required this.deger});
  final int hedefTRY;
  final double deger;

  bool get belirlenmedi => hedefTRY <= 0;
  bool get ulasildi => hedefTRY > 0 && deger >= hedefTRY;
  double get oran => hedefTRY <= 0 ? 0 : (deger / hedefTRY).clamp(0.0, 1.0);
  double get kalan => hedefTRY <= 0 ? 0 : (hedefTRY - deger).clamp(0.0, double.infinity);
}

class YaklasanOlaySatiri extends BugunSatiri {
  const YaklasanOlaySatiri({
    required this.tur,
    required this.tarih,
    required this.gunKaldi,
  });
  final BugunOlayTuru tur;
  final DateTime tarih;

  /// 0 = bugün, 1 = yarın …
  final int gunKaldi;
}

/// Ayın ilk günlerinde: geçen ayın özetine giriş.
class AylikOzetSatiri extends BugunSatiri {
  const AylikOzetSatiri({required this.ay});

  /// Özetlenen ayın 1'i.
  final DateTime ay;
}

/// Kartın tamamı. [birincil] hareket satırı, [ikincil] günün içgörüleri
/// (en fazla [BugunService.ikincilSayisi]), [aylik] ayın başında girişi.
class BugunKartiVerisi {
  const BugunKartiVerisi({
    required this.birincil,
    required this.ikincil,
    required this.aylik,
  });
  final BugunSatiri? birincil;
  final List<BugunSatiri> ikincil;
  final AylikOzetSatiri? aylik;

  bool get bos => birincil == null && ikincil.isEmpty && aylik == null;
}

abstract final class BugunService {
  /// BIST sürekli işlem: 10:00 – 18:00 (yarım günde 12:30).
  static const seansAcilisDk = 10 * 60;
  static const seansKapanisDk = 18 * 60;

  /// Yaklaşan olay ufku (gün).
  static const olayUfkuGun = 10;

  /// Aylık özet girişinin göründüğü günler: ayın 1–3'ü.
  static const aylikOzetGunSayisi = 3;

  /// Kartta aynı anda gösterilen içgörü sayısı.
  static const ikincilSayisi = 2;

  /// Bir işlem günü mü (hafta içi ve tatil değil)?
  static bool islemGunuMu(DateTime t) =>
      t.weekday < DateTime.saturday && !BistTakvimi.tatilMi(t);

  /// Seans şu an açık mı? Cihaz saatinin TR olduğu varsayılır — uygulama
  /// Türkiye pazarına özel; yurt dışındaki kullanıcıda satır bir saat
  /// dilimi kadar kayar, yanlış sayı üretmez.
  static bool seansAcikMi(DateTime now) {
    if (!islemGunuMu(now)) return false;
    final dk = now.hour * 60 + now.minute;
    final kapanis = BistTakvimi.yarimGunMu(now)
        ? BistTakvimi.yarimGunKapanisDk
        : seansKapanisDk;
    return dk >= seansAcilisDk && dk < kapanis;
  }

  /// Bir sonraki seans açılışı (10:00). Bugün açılış öncesiyse bugün.
  static DateTime sonrakiAcilis(DateTime now) {
    var gun = dayKey(now);
    final bugunAcilis = gun.add(const Duration(minutes: seansAcilisDk));
    if (islemGunuMu(gun) && now.isBefore(bugunAcilis)) return bugunAcilis;
    for (var i = 0; i < 20; i++) {
      gun = DateTime(gun.year, gun.month, gun.day + 1);
      if (islemGunuMu(gun)) return gun.add(const Duration(minutes: seansAcilisDk));
    }
    // Takvim 20 gün boyunca kapalı olamaz; yine de güvenli bir değer dön.
    return bugunAcilis.add(const Duration(days: 1));
  }

  /// Ufuk içindeki ulusal olaylar, tarihe göre sıralı.
  static List<YaklasanOlaySatiri> yaklasanOlaylar(DateTime now, {int ufuk = olayUfkuGun}) {
    final bugun = dayKey(now);
    final out = <YaklasanOlaySatiri>[];

    // TÜİK: bu ayın 3'ü geçmediyse o, geçtiyse gelecek ayın 3'ü.
    var tuik = DateTime(now.year, now.month, 3, 10);
    if (now.isAfter(tuik)) tuik = DateTime(now.year, now.month + 1, 3, 10);
    final tuikGun = dayKey(tuik);
    final tuikKalan = tuikGun.difference(bugun).inDays;
    if (tuikKalan >= 0 && tuikKalan <= ufuk) {
      out.add(YaklasanOlaySatiri(
          tur: BugunOlayTuru.tuikAciklamasi, tarih: tuik, gunKaldi: tuikKalan));
    }

    // BIST tatili: hafta içine düşen ilk tatil.
    for (var i = 0; i <= ufuk; i++) {
      final g = DateTime(bugun.year, bugun.month, bugun.day + i);
      if (g.weekday < DateTime.saturday && BistTakvimi.tatilMi(g)) {
        out.add(YaklasanOlaySatiri(
            tur: BugunOlayTuru.bistTatili, tarih: g, gunKaldi: i));
        break;
      }
    }

    // Ay sonu: son 3 gün.
    final aySonu = DateTime(now.year, now.month + 1, 0);
    final aySonuKalan = aySonu.difference(bugun).inDays;
    if (aySonuKalan >= 0 && aySonuKalan <= 2) {
      out.add(YaklasanOlaySatiri(
          tur: BugunOlayTuru.aySonu, tarih: aySonu, gunKaldi: aySonuKalan));
    }

    out.sort((a, b) => a.gunKaldi.compareTo(b.gunKaldi));
    return out;
  }

  /// Kartı kurar.
  ///
  /// [karZararlar]: açık pozisyonların ömürlük kâr/zararı (TRY) — yeşil oran
  /// için. [ozet] gün içi seri henüz gelmediyse `null`; o zaman birincil satır
  /// yalnızca "piyasa kapalı" olabilir.
  ///
  /// Dönüşüm: içgörü adayları günün tarihine göre kaydırılır ki iki ardışık
  /// günde aynı satır aynı sırada çıkmasın. Tarihe bağlı olması bilinçli —
  /// rastgele olsaydı aynı gün içinde her açılışta değişir, "az önce
  /// gördüğüm neredeydi" sorusu doğardı.
  static BugunKartiVerisi hesapla({
    required List<double> karZararlar,
    required double toplamDeger,
    required DailySummary? ozet,
    required int hedefTRY,
    required DateTime now,
  }) {
    BugunSatiri? birincil;
    if (ozet != null && ozet.hasChange) {
      birincil = GunlukDegisimSatiri(
          changeTRY: ozet.changeTRY!, changePct: ozet.changePct!);
    } else if (!seansAcikMi(now)) {
      birincil = PiyasaKapaliSatiri(sonrakiAcilis: sonrakiAcilis(now));
    }

    final adaylar = <BugunSatiri>[];
    if (karZararlar.isNotEmpty) {
      adaylar.add(YesilOranSatiri(
        yesil: karZararlar.where((k) => k > 0).length,
        toplam: karZararlar.length,
      ));
    }
    adaylar.add(HedefSatiri(hedefTRY: hedefTRY, deger: toplamDeger));
    final olaylar = yaklasanOlaylar(now);
    if (olaylar.isNotEmpty) adaylar.add(olaylar.first);

    final ikincil = <BugunSatiri>[];
    if (adaylar.isNotEmpty) {
      final bas = now.difference(DateTime(now.year)).inDays % adaylar.length;
      for (var i = 0; i < adaylar.length && ikincil.length < ikincilSayisi; i++) {
        ikincil.add(adaylar[(bas + i) % adaylar.length]);
      }
    }

    final aylik = now.day <= aylikOzetGunSayisi
        ? AylikOzetSatiri(ay: DateTime(now.year, now.month - 1, 1))
        : null;

    return BugunKartiVerisi(birincil: birincil, ikincil: ikincil, aylik: aylik);
  }
}
