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
  hizliHesap('hizli_hesap', 'Aramada hızlı hesap'),

  /// Takip listesinde sürükleyerek sıra değişimi ya da sıralama seçimi.
  takipSirasi('takip_sirasi', 'Takip listesi sıralama'),

  /// Varlık eklemede Tutar kipiyle KAYIT (kipe geçiş değil, bkz. kayıt).
  tutarKipi('tutar_kipi', 'Varlık eklemede Tutar kipi'),

  /// Hata ekranında "Sorun sürüyorsa bize yaz" dokunuşu.
  bizeYaz('bize_yaz', 'Hata ekranında Bize yaz'),

  /// Yatay tam ekran grafiğin açılması. Tek giriş yan çevirmek (dik
  /// ekrandaki çip 2026-09-17'de kalktı; kod adı sabit).
  yatayGrafik('yatay_grafik', 'Yatay tam ekran grafik'),

  /// Tam ekran grafikte çizim aracıyla bir çizimin tamamlanması.
  cizim('cizim', 'Grafikte çizim'),

  /// iOS tek varlık widget'ından gelen açılış.
  varlikWidget('varlik_widget', 'Tek varlık widget\'ı'),

  /// Tam ekran grafiğin görsel olarak paylaşılması (Ar-Ge 25 Eki §2):
  /// paylaşım sayfası hatasız açıldığında sayılır, düğmeye dokunuşta değil.
  grafikPaylas('grafik_paylas', 'Grafiği görsel paylaşma', premium: true),

  /// Boş takip listesindeki öneri çipiyle (Gram altın / Dolar / BIST 100)
  /// takibe alma. Soru: boş durum ilk takibi başlatıyor mu, yoksa çipler
  /// görülüp geçiliyor mu (görülmezse 19 Kasım turunda kalkar).
  takipOnerisi('takip_onerisi', 'Boş takip listesinde öneri'),

  /// Genel aramanın boş hâlindeki "Son baktıkların" satırına dokunuş.
  /// Soru: kısayol geri dönüşte kullanılıyor mu, yoksa eylemlerin üstünde
  /// yalnız yer mi kaplıyor.
  sonBakilan('son_bakilan', 'Aramada Son baktıkların'),

  /// Takip listesi satırındaki alarm çanına dokunuş (o varlığın alarmları
  /// açılır). Soru: satırdaki hedef bilgisi yetiyor mu, yoksa kullanıcı
  /// alarmlara oradan da gidiyor mu.
  takipAlarmCani('takip_alarm_cani', 'Takip satırında alarm çanı'),

  /// Günlük yüzde alarmı KURULMASI (0169, Ar-Ge 27 Eki §1). Soru: altın,
  /// döviz ve kripto tutan kişi "bugün sert oynarsa" alarmını kuruyor mu,
  /// yoksa sabit hedef fiyat mı yetiyor.
  yuzdeAlarm('yuzde_alarm', 'Günlük yüzde alarmı'),

  /// Gösterge alarmı KURULMASI (0170, yasin 2026-10-29). Soru: Premium
  /// kullanıcı "EMA50'yi keserse" alarmını kuruyor mu.
  gostergeAlarm('gosterge_alarm', 'Gösterge alarmı', premium: true),

  /// Yatay grafikte trend çizgisi / ışından çizgi alarmı kurulması (0170).
  cizimAlarm('cizim_alarm', 'Çizgiden alarm', premium: true),

  /// Yatay grafikte yatay çizgiden fiyat alarmı kurulması (0170). Soru:
  /// çizimden alarm kısayolu, zilden kurmaya göre kullanılıyor mu.
  yatayCizgiAlarm('yatay_cizgi_alarm', 'Yatay çizgiden fiyat alarmı', premium: true),

  // ── Ölçüm boşluğu turu (yasin 2026-11-21, "hangi featureların
  // kullanıldığını net şekilde görmeliyiz"). Premium yüzeyler kilit AÇIKKEN
  // sayılır (kilitli kartın görülmesi kullanım değil); kod, aynı yüzeyin
  // paywall `kaynak`ıyla aynı ki iki rapor yan yana okunsun. Ücretsiz
  // özellikler sayfa açılınca (`showSandikSheet(olcum: …)`).

  /// Aylık getiri kartının açık hâli çizildi.
  aylikGetiri('aylik_getiri', 'Aylık getiri kartı', premium: true),

  /// Portföy panelinde "Başa baş için %X yükselmeli" satırı göründü.
  basaBas('basa_bas', 'Başa baş satırı (portföy)', premium: true),

  /// Varlık sayfasında başa baş satırı göründü.
  varlikBasaBas('varlik_basa_bas', 'Başa baş satırı (varlık)', premium: true),

  /// Dönem özetinde en iyi / en zor gün kartının açık hâli.
  enIyiGun('en_iyi_gun', 'En iyi ve en zor gün', premium: true),

  /// Fon sayfasında dağılım kartının açık hâli.
  fonXray('fon_xray', 'Fon dağılımı (X-Ray)', premium: true),

  /// Varlık sayfasında geçmiş fiyat tablosunun açık hâli.
  gecmisFiyatlar('gecmis_fiyatlar', 'Geçmiş fiyatlar tablosu', premium: true),

  /// Hisse sayfasında hacim radarı kartının açık hâli.
  hacimRadari('hacim_radari', 'Hisse hacim radarı', premium: true),

  /// Kripto sayfasında alıcı baskısı kartının açık hâli.
  kriptoBaski('kripto_baski', 'Kripto alıcı baskısı', premium: true),

  /// Fon sayfasında para akışı kartının açık hâli.
  paraAkisi('para_akisi_karti', 'Fon para akışı', premium: true),

  /// Döviz bazlı varlıkta kur ve fiyat etkisinin ayrı satırı.
  kurAyrismasi('kur_ayrismasi', 'Kur ayrışması', premium: true),

  /// Varlık sayfasında masraf kartının kalem dökümüyle açık hâli.
  masrafDokumu('masraf_dokumu', 'Masraf dökümü', premium: true),

  /// Kapanmış pozisyonlar sayfası açıldı (kilit açıkken).
  sattiklarin('sattiklarin', 'Sattıkların', premium: true),

  /// Temettü kartında maliyete göre verim satırı göründü.
  temettuVerimi('temettu_verimi', 'Maliyetine göre temettü verimi', premium: true),

  /// Elde tutma satırının yıllık oranı göründü.
  yillikGetiri('yillik_getiri', 'Elde tutma yıllık getirisi', premium: true),

  /// Zirve portföyünde fon/BES içerik kartının açık hâli.
  zirveXray('zirve_xray', 'Zirve portföy içeriği', premium: true),

  /// Portföy yorumu kartının açık hâli.
  portfoyYorumu('portfoy_yorumu', 'AI portföy yorumu', premium: true),

  /// Varlık sayfasında yorum kartının açık hâli.
  varlikYorumu('varlik_yorumu', 'AI varlık yorumu', premium: true),

  /// Sinyal kartının Premium göstergelerle açık hâli.
  sinyalGosterge('sinyal_gosterge', 'Teknik sinyaller', premium: true),

  /// Hedef sayfasında tahmini tarih satırı açık.
  hedefTarihi('hedef_tarihi', 'Hedefe ulaşma tarihi', premium: true),

  /// İçe aktarmada AI sütun eşlemesi istendi ve yanıt geldi.
  ekstreAi('ekstre_ai', 'Ekstreyi AI ile eşleme', premium: true),

  /// Zekât hesabı sayfası açıldı.
  zekat('zekat', 'Zekât hesabı'),

  /// Hedef sayfası açıldı.
  hedef('hedef', 'Hedef koyma'),

  /// Bedelli artırım sayfası açıldı.
  bedelli('bedelli', 'Bedelli artırım'),

  /// Kilometre taşı sayfası açıldı.
  kilometreTasi('kilometre_tasi', 'Kilometre taşı'),

  /// Ortakla paylaşım sayfası açıldı.
  ortakPaylasim('ortak_paylasim', 'Ortak portföy paylaşımı'),

  /// Portföyler arası kısmi aktarım sayfası açıldı.
  kismiAktarim('kismi_aktarim', 'Kısmi aktarım'),

  /// İşleme not yazma sayfası açıldı.
  islemNotu('islem_notu', 'İşlem notu'),

  /// Tümü satılınca kapanış özeti sayfası açıldı.
  kapanisOzeti('kapanis_ozeti', 'Kapanış özeti'),

  /// Getiri paylaşım kartı sayfası açıldı.
  paylasimKarti('paylasim_karti', 'Paylaşım kartı'),

  /// Hızlı al / sat penceresi açıldı.
  hizliAlSat('hizli_al_sat', 'Hızlı al / sat');

  const Ozellik(this.kod, this.ad, {this.premium = false});
  final String kod;

  /// Haftalık GA4 raporundaki Türkçe ad. `tool/ga4_ekran_raporu.py` bu
  /// dosyayı okur: ad ve Premium işareti tek yerde, raporla kayamaz.
  final String ad;

  /// Premium'a ait yüzey (raporda işaretli).
  final bool premium;
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
