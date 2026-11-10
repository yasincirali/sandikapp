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

/// Takvim notu — tatilden önceki iş günü ya da arife sabahı (2026-11-10).
///
/// Neden: tatil günü Bugün kartı "Piyasa kapalı" diyordu ama bunu kullanıcı
/// ancak o sabah görüyordu; alım/satım planı olan biri bir gün önce bilmek
/// ister. `BistTakvimi` istemcide olduğundan bilgi uydurmadan verilebilir.
/// Tek satır, yalnız o gün; hesap [BugunService.tatilOncesiSatiri].
///
/// [kapanis] doluysa arife ("bugün 12:30'da kapanır"), değilse "yarın
/// kapalı" ve [sonrakiIslemGunu] tatil sonrası ilk işlem günüdür. Fon kesim
/// saati yazılmaz: fonun kendi kesimi var, borsa saatiyle karışır.
class TatilOncesiSatiri extends BugunSatiri {
  const TatilOncesiSatiri.arife({required DateTime this.kapanis})
      : sonrakiIslemGunu = null;
  const TatilOncesiSatiri.yarinKapali({required DateTime this.sonrakiIslemGunu})
      : kapanis = null;

  /// Yarım günün kapanış anı (arife); "yarın kapalı" satırında null.
  final DateTime? kapanis;

  /// Tatil sonrası ilk işlem günü (gün başı); arifede null.
  final DateTime? sonrakiIslemGunu;

  bool get arife => kapanis != null;
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

  /// "Geçen yılki 100 liran bugün kaç lira?" — alım gücü, tek sayı.
  ///
  /// **Neden (benchmark revizesi, kullanıcı seçimi 2026-10-09):** sekiz
  /// uygulamanın hiçbiri enflasyon kıyası göstermiyor; gösterdiğimizde de
  /// "24,2 puan geride" finans dışı kullanıcıya hiçbir şey söylemiyordu
  /// (2026-10-09 müşteri gözüyle inceleme). Alım gücü araçlarının ortak
  /// çerçevesi "paran bugün ne alır": 100 lira pencerenin başında
  /// yatırılsaydı, nominal getiriyle büyür, aynı dönemin TÜFE'siyle
  /// bölünür. `(1+n)/(1+e)` Performans'taki bileşik reel getiriyle aynı
  /// formül (akış yokken `RealReturnService.hizaliGetiri` ile birebir);
  /// iki yüzey iki farklı sayı söylemez.
  double get yuzLiraBugun => 100 * (1 + nominal / 100) / (1 + inflation / 100);
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
    this.takvimNotu,
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

  /// Tatil öncesi / arife notu; çoğu gün null. Birincil satırın yerini
  /// almaz, altında ayrı tek satırdır (birincil günün hareketini söyler).
  final TatilOncesiSatiri? takvimNotu;
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

  /// Bugünkü seansın kapanış anı; işlem günü değilse `null`. Eşik
  /// [seansAcikMi] ile aynı (yarım günde 12:30).
  static DateTime? seansKapanisi(DateTime now) {
    if (!islemGunuMu(now)) return null;
    final kapanis = BistTakvimi.yarimGunMu(now)
        ? BistTakvimi.yarimGunKapanisDk
        : seansKapanisDk;
    return dayKey(now).add(Duration(minutes: kapanis));
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

  /// Tatil öncesi / arife notu ya da null — SAF, en fazla bir satır.
  ///
  /// Kurallar (2026-11-10):
  ///   · Bugün işlem günü olmalı; tatil ya da hafta sonu içinde not yok.
  ///   · Arife (yarım gün) kapanıştan ÖNCE: "bugün 12:30'da kapanır".
  ///     Kapanıştan sonra ertesi gün tatilse "yarın kapalı"ya döner —
  ///     sabah daha acil olan söylenir, öğleden sonra sıradaki.
  ///   · Yarın RESMÎ tatilse (hafta sonu değil — hafta sonunu herkes bilir,
  ///     her Cuma satır çıkması gürültü olurdu): "yarın kapalı" + sonraki
  ///     işlem günü, takvimden yürüyerek.
  ///   · Takvimin kapsamadığı yılda (bugünün ya da sonraki işlem gününün
  ///     yılı) not yok: dinî bayram orada BİLİNMEZ, "sonraki işlem günü"
  ///     uydurma olur (`BistTakvimi` kural 1).
  static TatilOncesiSatiri? tatilOncesiSatiri(DateTime now) {
    if (!BistTakvimi.yilKapsaniyor(now.year) || !islemGunuMu(now)) {
      return null;
    }
    final gun = dayKey(now);
    if (BistTakvimi.yarimGunMu(now)) {
      final kapanis =
          gun.add(const Duration(minutes: BistTakvimi.yarimGunKapanisDk));
      if (now.isBefore(kapanis)) {
        return TatilOncesiSatiri.arife(kapanis: kapanis);
      }
    }
    final yarin = DateTime(gun.year, gun.month, gun.day + 1);
    if (yarin.weekday >= DateTime.saturday || !BistTakvimi.tatilMi(yarin)) {
      return null;
    }
    var sonraki = yarin;
    for (var i = 0; i < 20; i++) {
      sonraki = DateTime(sonraki.year, sonraki.month, sonraki.day + 1);
      if (islemGunuMu(sonraki)) {
        if (!BistTakvimi.yilKapsaniyor(sonraki.year)) return null;
        return TatilOncesiSatiri.yarinKapali(sonrakiIslemGunu: sonraki);
      }
    }
    return null;
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

    // Takvim notu "Piyasa kapalı" satırıyla çakışmasın: kapanıştan sonra
    // kapalı satırı başlıkta zaten tatil sonrası açılışı söylüyor
    // ("Pazartesi 10:00 açılır"); aynı bilgiyi ikinci kez yazmayız. Açılış
    // öncesinde kapalı satırı BUGÜN 10:00'ı söyler — not tamamlayıcıdır.
    var takvimNotu = tatilOncesiSatiri(now);
    if (takvimNotu != null &&
        !takvimNotu.arife &&
        birincil is PiyasaKapaliSatiri &&
        dayKey(birincil.sonrakiAcilis) != dayKey(now)) {
      takvimNotu = null;
    }

    return BugunKartiVerisi(
      birincil: birincil,
      hedef: HedefSatiri(hedefTRY: hedefTRY, deger: toplamDeger),
      reel: reel,
      kapaliSoylenir: yalnizcaBorsa,
      takvimNotu: takvimNotu,
    );
  }
}
