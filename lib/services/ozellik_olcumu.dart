import 'package:shared_preferences/shared_preferences.dart';

import '../config/pref_keys.dart';
import 'analytics_service.dart';
import 'crash_reporter.dart';
import 'temettu_gecmisi.dart' show trGunu;

/// Ölçülen ekran-içi özellikler. Analitik kodu SABİT: Firebase panosu ve
/// 19 Kasım sadeleştirme turu bu dizelere bağlanır; değiştirme, yalnız ekle.
///
/// Serbest metin yolu kasıtlı olarak yok: olay yalnız bu enum'u alır, bir
/// çağrı noktası sembol / tutar / arama metni geçiremez
/// (`ozellik_olcumu_test` kilitler).
enum Ozellik {
  /// Genel aramada "sayı + birim" hızlı hesap satırına dokunuş.
  hizliHesap('hizli_hesap'),

  /// Takip listesinde sürükleyerek sıra değişimi ya da sıralama seçimi.
  takipSirasi('takip_sirasi'),

  /// Varlık eklemede Tutar kipiyle KAYIT (kipe geçiş değil, bkz. kayıt).
  tutarKipi('tutar_kipi'),

  /// Hata ekranında "Sorun sürüyorsa bize yaz" dokunuşu.
  bizeYaz('bize_yaz'),

  /// Yatay tam ekran grafiğin açılması (düğmeyle ya da yan çevirerek).
  yatayGrafik('yatay_grafik'),

  /// Tam ekran grafikte çizim aracıyla bir çizimin tamamlanması.
  cizim('cizim'),

  /// iOS tek varlık widget'ından gelen açılış.
  varlikWidget('varlik_widget'),

  /// Tam ekran grafiğin görsel olarak paylaşılması (Ar-Ge 25 Eki §2):
  /// paylaşım sayfası hatasız açıldığında sayılır, düğmeye dokunuşta değil.
  grafikPaylas('grafik_paylas'),

  /// Boş takip listesindeki öneri çipiyle (Gram altın / Dolar / BIST 100)
  /// takibe alma. Soru: boş durum ilk takibi başlatıyor mu, yoksa çipler
  /// görülüp geçiliyor mu (görülmezse 19 Kasım turunda kalkar).
  takipOnerisi('takip_onerisi'),

  /// Genel aramanın boş hâlindeki "Son baktıkların" satırına dokunuş.
  /// Soru: kısayol geri dönüşte kullanılıyor mu, yoksa eylemlerin üstünde
  /// yalnız yer mi kaplıyor.
  sonBakilan('son_bakilan');

  const Ozellik(this.kod);
  final String kod;
}

/// Dün gelen özelliklerin kullanımını sayar (Ar-Ge 25 Eki §3).
///
/// ## Neden
/// 19 Kasım "ölü yüzey" turu ekran ölçümüne (`EkranOlcumu`) dayanıyor; bu
/// özellikler ekran değil ekranın İÇİNDE. Ölçülmezse kullanılmayanı
/// ayırt edemeyiz, "kullanılmayan yüzeyi kaldır" ilkesi yeni özelliklere
/// uygulanamaz.
///
/// ## Neden günde bir kez
/// Soru "kaç kişi, kaç gün kullanıyor"; kaç dokunuş değil. Her sürükleme ya
/// da çizim ayrı olay olsaydı sayı kullanım yoğunluğunu ölçer, panoyu
/// şişirirdi. Gün TR takvimidir (`trGunu`, UTC+3): yurt dışındaki
/// kullanıcının günü TR raporlarının gününden kaymasın.
///
/// ## Neden diskte (bellekte değil)
/// `AyarOlcumu` oturum belleğiyle tekilleştirir; burada gün sınırı lazım
/// ve aynı gün uygulama birkaç kez açılır. İşaret `shared_preferences`'ta
/// ([PrefKeys.ozellikOlcumuPrefix]; neden cihaza özel olduğu orada).
///
/// ## Kapı
/// Gönderim `AnalyticsService` üzerinden: Firebase hazır değilse ya da
/// toplama kapalıysa (debug) olay düşer, servisin kendi sözleşmesi.
/// Soğuk açılışta (widget dokunuşu) analytics ertelenmiş başlatılır; olay
/// [AnalyticsService.hazir]'ı bekler, yoksa ilk açılışın olayı kaybolurdu.
///
/// ## Gizlilik
/// Yalnız özellik kodu gider. Yasal metinde Firebase Analytics ve uygulama
/// kullanım verisi zaten var; yeni alıcı ya da amaç yok.
class OzellikOlcumu {
  OzellikOlcumu({
    Future<void> Function(Ozellik o)? gonder,
    DateTime Function()? saat,
  })  : _gonder = gonder ?? _varsayilanGonder,
        _saat = saat ?? DateTime.now;

  static final OzellikOlcumu instance = OzellikOlcumu();

  final Future<void> Function(Ozellik o) _gonder;
  final DateTime Function() _saat;

  /// Bu süreçte sayılan son gün. Disk okuması beklenirken gelen ikinci
  /// dokunuş (hızlı çift sürükleme) aynı günü ikinci kez göndermesin.
  final Map<Ozellik, String> _bellek = {};

  static Future<void> _varsayilanGonder(Ozellik o) async {
    await AnalyticsService.instance.hazir;
    await AnalyticsService.instance.logOzellikKullanildi(o);
  }

  /// TR takvim günü, `yyyy-aa-gg`.
  static String gunAnahtari(DateTime an) {
    final g = trGunu(an);
    String iki(int n) => n.toString().padLeft(2, '0');
    return '${g.year}-${iki(g.month)}-${iki(g.day)}';
  }

  /// Çağrı noktalarının tek yolu: sonucu beklemez, hata Crashlytics'e.
  static void say(Ozellik o) => CrashReporter.arkaPlan(
      instance.kullanildi(o),
      reason: 'OzellikOlcumu.say');

  /// Bugün [o] henüz sayılmadıysa olayı gönderir. Gönderildiyse `true`.
  Future<bool> kullanildi(Ozellik o) async {
    final gun = gunAnahtari(_saat());
    if (_bellek[o] == gun) return false;
    _bellek[o] = gun;
    final sp = await SharedPreferences.getInstance();
    final anahtar = '${PrefKeys.ozellikOlcumuPrefix}${o.kod}';
    if (sp.getString(anahtar) == gun) return false;
    await sp.setString(anahtar, gun);
    await _gonder(o);
    return true;
  }

  /// Testte bellek işaretini sıfırlar (disk `setMockInitialValues` ile).
  void sifirlaTest() => _bellek.clear();
}
