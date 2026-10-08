// "Bugün" kartının hesabı — SAF.
//
// Neden var (2026-09-20): ana ekran her gün aynı görünüyordu. Bir takip
// uygulamasında kullanıcının yapacak "işi" yok, yalnızca bakacak şeyi var;
// aynı görünen ekrana ikinci gün gelinmez. Bu kart her açılışta değişen
// tek bir yüzey verir: bugünün hareketi (ya da piyasa ne zaman açılır),
// enflasyon kıyası ve hedef. (2026-10-08: H düzeninin çizmediği satırlar —
// artıdaki varlık, son 7 gün, aylık özet, yaklaşan olay — hesaptan da
// kalktı; gerekçe `BugunService.hesapla`.)
//
// İlkeler (RETENTION_STRATEJISI §3, §8):
//   · Her satır bir BİLGİ taşır; "bugün de uğra" tarzı boş çağrı yok.
//   · Kayıp gününde bağırmaz: düşüş de aynı sakin satırdır, renk söyler.
//   · Streak / rozet yağmuru yok. Dönüşüm, aynı bilgiyi her gün
//     tekrarlamamak için; kullanıcıyı "kaçırma" hissiyle çekmek için değil.
//
// Widget tarafı `widgets/bugun_karti.dart`; burası ağ ve BuildContext bilmez
// ki `test/bugun_service_test.dart` seansı ve satırları sınayabilsin.
import '../utils/tr_format.dart' show dayKey;
import 'bist_calendar.dart';
import 'daily_summary.dart';
import 'inflation_service.dart' show InflationWindow;

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

/// Portföy hedefi: `hedefTRY <= 0` ise "hedef belirle" çağrısıdır.
class HedefSatiri extends BugunSatiri {
  const HedefSatiri({required this.hedefTRY, required this.deger});
  final int hedefTRY;
  final double deger;

  bool get belirlenmedi => hedefTRY <= 0;
  bool get ulasildi => hedefTRY > 0 && deger >= hedefTRY;
  double get oran => hedefTRY <= 0 ? 0 : (deger / hedefTRY).clamp(0.0, 1.0);
  double get kalan =>
      hedefTRY <= 0 ? 0 : (hedefTRY - deger).clamp(0.0, double.infinity);
}

/// Yıllık reel getiri — "eridim mi?" (2026-09-21, sadeleştirme).
///
/// Eskiden ana ekranda ayrı bir şeritti (`RealReturnStrip`); kart aynı
/// soruyu ("nasıl gidiyorum") cevapladığı için SABİT satır olarak buraya
/// girdi — dönüşüme girmez, markanın kalbi her gün görünür. Sayı yine
/// `RealReturnService.yillik`'ten gelir (tek hesap yolu).
class ReelGetiriSatiri extends BugunSatiri {
  const ReelGetiriSatiri(
      {required this.nominal, required this.inflation, this.pencere});
  final double nominal;
  final double inflation;

  /// İki sayının ölçüldüğü TÜFE penceresi — kutu etiketinde ay aralığı
  /// olarak yazılır (2026-10-02 müşteri testi: Ana "%37,29", Performans 1Y
  /// "%38,84" diyordu ve hangisinin hangi aralık olduğu yazmıyordu).
  /// Bilinmiyorsa etiket "yıllık" der.
  final InflationWindow? pencere;

  /// Puan farkı: getiri − TÜFE.
  double get fark => nominal - inflation;
  bool get onde => fark >= 0;
}

/// Kartın tamamı — H düzeninin çizdiği satırlar (2026-10-08).
///
/// Eskiden D düzeninin satırlarını da taşıyordu (artıdaki varlık, son 7 gün,
/// aylık özet, yaklaşan olay); kart onları 2026-10-04'ten beri çizmiyordu
/// ama hesap üretiyor, son 7 gün için ağdan seri çekiyor ve gösterim ölçümü
/// onları "gösterildi" sayıyordu (`TECHNICAL_DEBT.md`). Çizilmeyen satır
/// hesaplanmaz. En çok oynayan servis dışında (`enCokOynayanBul`, gün içi
/// önbellekten) — burada değil.
class BugunKartiVerisi {
  const BugunKartiVerisi({
    required this.birincil,
    required this.hedef,
    this.reel,
    this.kapaliSoylenir = false,
  });

  /// Günün hareketi ya da "piyasa kapalı"; seri yoksa `null`.
  final BugunSatiri? birincil;

  /// Hedef her gün, her kapsamda (2026-09-30, kullanıcı bulgusu "hedef
  /// belirle kısmı kaybolmuş"): hedef belirlemenin tek giriş noktası.
  final HedefSatiri hedef;

  /// Enflasyon kıyası; veri yoksa null.
  final ReelGetiriSatiri? reel;

  /// Seans dışında "Piyasa kapalı" denebilir mi? Yalnızca portföy TAMAMEN
  /// borsa ürünüyse (kullanıcı kararı 2026-10-01, bkz. `yalnizcaBorsa`).
  /// Karışık portföyde altın/döviz/kripto hafta sonu ve gece de işler;
  /// başlık orada kapalılık değil canlılık söyler.
  final bool kapaliSoylenir;
}

abstract final class BugunService {
  /// BIST sürekli işlem: 10:00 – 18:00 (yarım günde 12:30).
  static const seansAcilisDk = 10 * 60;
  static const seansKapanisDk = 18 * 60;

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
      if (islemGunuMu(gun)) {
        return gun.add(const Duration(minutes: seansAcilisDk));
      }
    }
    // Takvim 20 gün boyunca kapalı olamaz; yine de güvenli bir değer dön.
    return bugunAcilis.add(const Duration(days: 1));
  }

  /// Kartı kurar.
  ///
  /// [ozet] gün içi seri henüz gelmediyse `null`; o zaman birincil satır
  /// yalnızca "piyasa kapalı" olabilir.
  ///
  /// [hedefTRY] çağıranın seçtiği KAPSAMIN hedefidir (`kapsamHedefiProvider`,
  /// 2026-09-30); kendi hedefin birleşik toplama karşı ölçülmez. Piyasa
  /// hareketi ve reel getiri kapsamdan bağımsız hesaplanır.
  ///
  /// 2026-10-08: dönüşümlü içgörü havuzu (artıdaki varlık, son 7 gün),
  /// aylık özet girişi ve yaklaşan olay ayak notu kalktı — H düzeni
  /// (2026-10-04) onları çizmiyordu; o bilgiler Performans › Özet'te.
  static BugunKartiVerisi hesapla({
    required double toplamDeger,
    required DailySummary? ozet,
    required int hedefTRY,
    required DateTime now,
    ReelGetiriSatiri? reel,
    bool yalnizcaBorsa = false,
  }) {
    BugunSatiri? birincil;
    if (ozet != null && ozet.hasChange) {
      birincil = GunlukDegisimSatiri(
          changeTRY: ozet.changeTRY!, changePct: ozet.changePct!);
    } else if (yalnizcaBorsa && !seansAcikMi(now)) {
      // Yalnızca borsa portföyü: rakam gerçekten donuk, "kapalı" doğru.
      // Karışık portföyde bu satır YOK (2026-10-01) — altın/kripto işlerken
      // "Piyasa kapalı" demek yanlış bilgidir; seri gelince hareket çizilir.
      birincil = PiyasaKapaliSatiri(sonrakiAcilis: sonrakiAcilis(now));
    }

    return BugunKartiVerisi(
      birincil: birincil,
      hedef: HedefSatiri(hedefTRY: hedefTRY, deger: toplamDeger),
      reel: reel,
      kapaliSoylenir: yalnizcaBorsa,
    );
  }
}
