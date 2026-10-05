import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';
import 'disclaimer_service.dart';
import 'yasal_metin_katalogu.dart';

/// Kayıt ekranında kullanıcının GÖRDÜĞÜ onay düzeni — `RegisterScreen`
/// gönderim anında kurar, `OtpVerificationScreen` doğrulamadan sonra
/// [YasalOnayService.kayitOnaylariniKaydet]'e verir (oturum ancak OTP
/// doğrulanınca açılır; kayıt ekranında `auth.uid()` yok).
@immutable
class KayitOnayBaglami {
  const KayitOnayBaglami({
    required this.dil,
    required this.kutuUlkesi,
    required this.belgeDegiskenleri,
    required this.kosulBelgesiAcildi,
    this.kvkkBelgesiAcildi = false,
    this.gizlilikBelgesiAcildi = false,
    this.sonunaKadarOkunanlar = const {},
    this.yatirimUyarisiOnaylandi = false,
  });

  // NOT: `rizaBelgesiAcildi` 2026-10-05'te kalktı (okuma sadeleştirme):
  // Açık Rıza Metni yalnız sonuna kadar okunup sonunda onaylanınca kayda
  // girer ([sonunaKadarOkunanlar]) — okunduysa açılmıştır, ayrı not gerekmez.

  // NOT: `tekKutu` alanı 2026-10-05'te kalktı — kayıt ekranı yalnız tek
  // kutuyu çizer (bayrak `tek_onay_kutusu` kalıcı açık). Eski iki kutunun
  // metinleri (`kayit_kutu_kosullar` / `kayit_kutu_riza`) katalogda durur:
  // onları onaylamış kullanıcıların kayıtları o hash'lerle eşleşir.

  /// Tek kutu l10n'dan çizilir → arayüz dili (`tr`/`en`). Belgeler her
  /// dilde Türkçe gösterilir; onlar için kullanılmaz.
  final String dil;

  /// Kutu metnindeki `{SUPABASE_ULKE}` yerine ekranda yazan değer.
  final String kutuUlkesi;

  /// Belgelerdeki yer tutucuların gösterim değerleri
  /// (`LegalDocs.yerTutucuDegerleri`).
  final Map<String, String> belgeDegiskenleri;

  /// Bilgilendirme/kabul belgesi (Koşullar, Gizlilik, KVKK) bağlantıdan en
  /// az bir kez açıldı mı — kanıt notu (`belge_acildi`).
  final bool kosulBelgesiAcildi;
  final bool kvkkBelgesiAcildi;
  final bool gizlilikBelgesiAcildi;

  /// Sonuna kadar okunup metnin sonunda onaylanan türler (`YasalTur`):
  /// 1.4'ten beri Açık Rıza Metni ve yatırım uyarısı. Açık Rıza Metni
  /// YALNIZ burada varsa kayda girer.
  final Set<String> sonunaKadarOkunanlar;

  /// Yatırım uyarısının TAM metni (`disclaimerText`) kayıt ekranında
  /// sonuna kadar okunup onaylandı. Yalnız o zaman `yatirim_uyarisi` öğesi
  /// kayda girer ve OTP sonrası `disclaimer_acceptances` yazılır.
  final bool yatirimUyarisiOnaylandi;

  /// Kayıtta onaylanan metinler + her birinin gösterim değişkenleri — saf,
  /// test edilir.
  ///
  /// ## Ne girer, ne girmez (1.4, okuma sadeleştirme 2026-10-05)
  /// - Kutu: kullanıcının işaretlediği tek cümle (`kayit_tek_kutu` 1.1):
  ///   Koşulların kabulü + 18+ + Gizlilik ve KVKK ile bilgilendirildim.
  /// - Koşullar, Gizlilik, KVKK ([YasalBelge.kutuylaAlinanlar]): kutuyla
  ///   birlikte HER ZAMAN girer — sunuldular ve kutu onları adıyla anar.
  ///   `nitelik` kaydın neyin kanıtı olduğunu söyler (Koşullar `kabul`,
  ///   ikisi `bilgilendirme`); `belge_acildi` bağlantıdan açılıp açılmadığı;
  ///   `sonuna_kadar_okundu: false` — artık okutulmuyor, ispat ne kadar
  ///   güçlüyse o kadarını söylesin. Yer tutucu değerleri yalnız o belgede
  ///   geçenler ([YasalMetinKatalogu.belgeDegiskenleri]).
  /// - Açık Rıza Metni YALNIZ sonuna kadar okunup sonunda onaylandıysa
  ///   ([sonunaKadarOkunanlar]) girer: rıza o düğmeyle verilir, kutunun yan
  ///   etkisi değildir. Kayıt ekranı onaysız göndermez; bağlam başka yoldan
  ///   kurulursa rıza YAZILMAZ (uydurma rıza olmaz).
  /// - Yatırım uyarısı (`disclaimerText`) YALNIZ zorunlu okumada girer
  ///   ([yatirimUyarisiOnaylandi]): tam metni sonuna kadar okunup onaylandı,
  ///   kanal `kayit` (0104 eşlemeye ekledi). Onaylanmadıysa girmez; uyarı
  ///   OTP'den sonra kendi ekranında tam metniyle sorulur (2026-10-04'e
  ///   kadar OTP gösterilmemiş tam metnin hash'iyle `disclaimer_acceptances`
  ///   yazıyordu — kapanan hata).
  List<Map<String, dynamic>> ogeler() {
    bool acildi(YasalBelge b) => switch (b) {
          YasalBelge.kosullar => kosulBelgesiAcildi,
          YasalBelge.gizlilik => gizlilikBelgesiAcildi,
          YasalBelge.kvkk => kvkkBelgesiAcildi,
          YasalBelge.acikRiza => true,
        };
    return [
      YasalMetinKatalogu.kayitTekKutu(dil)
          .rpcOgesi({'SUPABASE_ULKE': kutuUlkesi}),
      for (final b in YasalBelge.kutuylaAlinanlar)
        YasalOnayService.belgeOgesi(b, belgeDegiskenleri,
            acildi: acildi(b), okundu: false),
      if (sonunaKadarOkunanlar.contains(YasalTur.acikRiza))
        YasalOnayService.belgeOgesi(YasalBelge.acikRiza, belgeDegiskenleri,
            acildi: true, okundu: true),
      if (yatirimUyarisiOnaylandi)
        YasalMetinKatalogu.yatirimUyarisi().rpcOgesi({
          'belge_acildi': true,
          'sonuna_kadar_okundu': true,
        }),
    ];
  }
}

/// Yeniden onay kapısının kararı — kullanıcının hangi zorunlu metinlerin
/// GÜNCEL sürümüne etkin onayı eksik.
@immutable
class YasalKapiDurumu {
  const YasalKapiDurumu({this.eksik = const {}, this.oncekiSurum = const {}});

  /// Kapı yok: onaylar tam ya da sorgu düştü (fail-open).
  static const tamam = YasalKapiDurumu();

  /// Eksik türler: belgeler ([YasalBelge] türleri) ve kayıt kutusu
  /// taahhütleri için [YasalOnayService.kutuAnahtari].
  final Set<String> eksik;

  /// Tür → kullanıcının etkin onayı olan EN YENİ sürüm (eksik olsa bile —
  /// "güncellendi" mi yoksa "ilk kez" mi sorusunun cevabı).
  final Map<String, String> oncekiSurum;

  bool get gerekli => eksik.isNotEmpty;

  /// Kutu taahhüdünün güncel sürümü (1.1: Koşullar kabulü + 18+ +
  /// bilgilendirildim) eksik mi.
  bool get kutuEksik => eksik.contains(YasalOnayService.kutuAnahtari);

  /// Kapı kutuyu göstermeli mi: kutu eksik YA DA kutuyla alınan bir belge
  /// (Koşullar, Gizlilik, KVKK) eksik. 1.4'ten beri Koşulların kabulü ve
  /// bilgilendirme belgelerinin "bilgilendirildim"i KUTUYLA verilir — belge
  /// sonu onayı yok; kutusuz bir kapı bu belgeleri onaysız yazardı.
  bool get kutuGerekli =>
      kutuEksik ||
      YasalBelge.kutuylaAlinanlar.any((b) => eksik.contains(b.tur));

  /// Açık Rıza Metni'nin güncel sürümü eksik mi — kapı onu sonuna kadar
  /// okutur. Eksik değilse bağlantı olarak (salt okunur) listelenir;
  /// geçerli rıza ikinci kez istenmez.
  bool get rizaEksik => eksik.contains(YasalTur.acikRiza);

  /// Belgelerden en az birinin eski sürümü onaylı: başlık "Güncellenen
  /// belgeler" der; hiç yoksa (sosyal girişle ilk kez, 0102 öncesi hesap)
  /// "Yasal belgeler".
  bool get guncellemeMi => YasalMetinKatalogu.zorunluBelgeler()
      .any((m) => oncekiSurum.containsKey(m.tur));
}

/// Kapı ekranının kurduğu kutu — kayıt ekranıyla aynı tek kutu. (İki
/// kutulu düzen `tek_onay_kutusu` bayrağıyla 2026-10-05'te kalktı.) Kutu
/// verilirse kapı Koşullar/Gizlilik/KVKK öğelerini de yazar
/// ([YasalOnayService.kapiOgeleri]).
@immutable
class KapiKutuBaglami {
  const KapiKutuBaglami({
    required this.dil,
    required this.kutuUlkesi,
  });

  final String dil;
  final String kutuUlkesi;

  List<Map<String, dynamic>> ogeler() => [
        YasalMetinKatalogu.kayitTekKutu(dil)
            .rpcOgesi({'SUPABASE_ULKE': kutuUlkesi}),
      ];
}

/// Kapı ekranındaki kaydın sonucu.
enum KapiKayitSonucu {
  /// Yazıldı; cihaz izi kondu.
  tamam,

  /// Bağlantı hatası — ekran hata gösterir, kullanıcı yeniden dener.
  agHatasi,

  /// Sunucu reddetti (hash kayması, fonksiyon yok…) — raporlandı; kullanıcı
  /// kilitlenmez, bir sonraki açılışta kapı yeniden sorar.
  sunucuHatasi,
}

/// Yasal metin onaylarını sunucuya (`yasal_onaylar`, 0102) yazar ve
/// yeniden onay kapısının kararını verir.
///
/// ## Neden ayrı servis
/// `disclaimer_acceptances` yalnız yatırım uyarısını tutuyordu; kayıt
/// kutuları (koşullar, KVKK, yurt dışı aktarım açık rızası) hiç
/// kaydedilmiyordu. 0102 her metni (tür, sürüm, dil, hash) ile saklar ve
/// onayı RPC ile alır. Remote Config `yasal_onay_kaydi` 0102 iki sunucuya
/// dağıtılana kadar KAPALI tutuldu ("fonksiyon yok" hatası); 2026-10-04'te
/// açıldı, 2026-10-05'te bayrak kalktı — yazım koşulsuz.
///
/// ## Yeniden onay kapısı (kullanıcı kararı 2026-10-04)
/// *"Eski rıza metnini onaylayanlar için ilk login'de güncel doküman
/// sunulup onay istenmeli."* [kapiDurumu] kullanıcının zorunlu metinlerin
/// GÜNCEL sürümüne etkin onayı var mı diye bakar; yoksa `_AuthGate`
/// `YasalOnayKapisiScreen`'i gösterir. Metin sürümü her arttığında
/// kendiliğinden çalışır (cihaz izinin anahtarında sürümler var). Bayrak
/// `yasal_kapi_en_yeni` (yalnız `yasal_onay_kaydi` de açıkken etkiliydi:
/// kayıt yazılamazsa kapı her açılışta yeniden sorardı) 2026-10-05'te
/// kalktı; kapı koşulsuz. Eski anahtar `yeniden_onay_kapisi` Console'da
/// KALICI `false`: onu okuyan eski sürümlerin kapısı açılmasın.
///
/// ## En iyi gayret / fail-open
/// Kayıt yöntemleri fırlatmaz. Kapı sorgusu düşerse kullanıcı KİLİTLENMEZ
/// (kapı yok sayılır, iz konmaz, sonraki açılışta yeniden sorulur).
/// Bağlantı hatası dışındaki her hata (hash uyuşmazlığı = metin kayması
/// dahil) Crashlytics'e non-fatal gider. `disclaimer_acceptances` ve onun
/// `_AuthGate` kapısı buna DOKUNULMADI.
class YasalOnayService {
  YasalOnayService._();
  static final YasalOnayService instance = YasalOnayService._();

  static const _timeout = Duration(seconds: 15);

  /// Kapı sorgusunun süresi — splash bunu bekler; veri bekleme supabıyla
  /// (10 sn) hizalı.
  static const _kapiTimeout = Duration(seconds: 10);

  /// [YasalKapiDurumu.eksik] içinde kayıt kutusu taahhütlerinin anahtarı.
  static const kutuAnahtari = 'kayit_kutusu';

  /// Yalnız test: RPC yerine çağrılır (Supabase testte ayağa kalkmaz).
  @visibleForTesting
  static Future<void> Function(Map<String, dynamic> params)? rpcTesti;

  /// Yalnız test: kapı sorgusu yerine çağrılır; kullanıcının etkin
  /// onaylarını (tür, sürüm) döner.
  @visibleForTesting
  static Future<List<(String, String)>> Function(String userId)? sorguTesti;

  /// Yalnız test: sunucudaki metin sürümleri (tür, sürüm) sorgusu yerine.
  @visibleForTesting
  static Future<List<(String, String)>> Function()? sunucuSurumTesti;

  /// userId → kapı tamam (bu süreçte doğrulandı).
  final Set<String> _tamam = {};

  /// userId → sürmekte olan kayıt yazımı (OTP sonrası). Kapı sorgusu önce
  /// bunu bekler: yazım bitmeden sorulursa yeni kullanıcı kapıyı görürdü.
  final Map<String, Future<bool>> _bekleyen = {};

  @visibleForTesting
  void testSifirla() {
    _tamam.clear();
    _bekleyen.clear();
  }

  /// `yasal_onay_kaydet` parametreleri — saf, test edilir.
  static Map<String, dynamic> parametreler({
    required List<Map<String, dynamic>> ogeler,
    required String kanal,
    required String appVersion,
    required String platform,
    required String locale,
  }) =>
      {
        'p_ogeler': ogeler,
        'p_kanal': kanal,
        'p_app_version': appVersion,
        'p_platform': platform,
        'p_locale': locale,
      };

  // ── Sürüm karşılaştırma ve eksik hesabı (saf) ──────────────────────────

  /// `1.10` > `1.9`; sayısal parçalar sayı olarak, diğerleri metin olarak.
  /// Zirve sürümleri tarih (`2026-10-01`) — aynı kural doğru sıralar.
  static int surumKarsilastir(String a, String b) {
    final pa = a.split(RegExp(r'[.\-]'));
    final pb = b.split(RegExp(r'[.\-]'));
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : '0';
      final y = i < pb.length ? pb[i] : '0';
      final nx = int.tryParse(x);
      final ny = int.tryParse(y);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return 0;
  }

  /// Etkin onaylar (tür, sürüm) → kapı kararı. Saf.
  ///
  /// Bir tür, kullanıcının o türde katalogdaki sürüme EŞİT ya da DAHA YENİ
  /// bir etkin onayı varsa tamamdır. "Daha yeni" şart: kullanıcı yeni
  /// sürümü yeni bir cihazda onaylamışsa eski istemci onu eski sürüme
  /// geri onaylatmasın.
  ///
  /// Kutu taahhüdü YALNIZ tek kutunun güncel sürümüyle ([YasalMetinKatalogu
  /// .kutuSurumu], 1.1) tamamlanır. 2026-10-05'e kadar iki eski kutu
  /// (`kayit_kutu_kosullar` + `kayit_kutu_riza`, 1.0) da tamamlıyordu;
  /// kutu 1.1'e çıkınca 1.0 satırları (iki kutulu ya da tek kutulu) tamam
  /// sayılmaz — gerekçe `kutuSurumu` notunda.
  static YasalKapiDurumu eksikleriHesapla(Iterable<(String, String)> onaylar) {
    final enYeni = <String, String>{};
    for (final (tur, surum) in onaylar) {
      final mevcut = enYeni[tur];
      if (mevcut == null || surumKarsilastir(surum, mevcut) > 0) {
        enYeni[tur] = surum;
      }
    }
    bool tamamMi(String tur, String gereken) {
      final s = enYeni[tur];
      return s != null && surumKarsilastir(s, gereken) >= 0;
    }

    final eksik = <String>{
      for (final m in YasalMetinKatalogu.zorunluBelgeler())
        if (!tamamMi(m.tur, m.surum)) m.tur,
    };
    if (!tamamMi(YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu)) {
      eksik.add(kutuAnahtari);
    }
    return YasalKapiDurumu(eksik: eksik, oncekiSurum: enYeni);
  }

  /// Uygulama, kapının soracağı metinlerden birinin sunucudaki EN YENİ
  /// sürümünü taşımıyor mu? Saf.
  ///
  /// Kullanıcı kuralı (2026-10-04): *"eğer yeni güncel bir sürüm geldiyse
  /// ve onaylatılacaksa en yeni sürüm onaylatılmalı; çift onay olmamalı 2
  /// güncelleme geldiyse."* Uygulama yalnız kendi taşıdığı metni
  /// gösterebilir. Sunucuda daha yenisi varsa eskiyi onaylatmak, uygulama
  /// güncellenince ikinci bir onay doğurur. Bu durumda kapı HİÇ açılmaz
  /// (kısmi onay da sorulmaz) ve iz konmaz: güncel uygulama hepsini tek
  /// seferde sorar. Kullanıcının onayı zaten tamsa bu kontrol devreye girmez.
  ///
  /// [uygulamaSurumleri] (tür → sürüm) yalnız test içindir: yayındaki ESKİ
  /// bir istemcinin taşıdığı sürümleri canlandırır (ör. 1.2 taşıyan sürüm
  /// sunucuda 1.3'ü görünce, 0105). Verilmezse bu derlemenin kataloğu.
  static bool uygulamaEski(
    Iterable<(String, String)> sunucuSurumleri, {
    Map<String, String>? uygulamaSurumleri,
  }) {
    final benim = uygulamaSurumleri ??
        <String, String>{
          for (final m in YasalMetinKatalogu.zorunluBelgeler()) m.tur: m.surum,
          YasalTur.kayitTekKutu: YasalMetinKatalogu.kutuSurumu,
          YasalTur.kayitKutuKosullar: YasalMetinKatalogu.eskiKutuSurumu,
          YasalTur.kayitKutuRiza: YasalMetinKatalogu.eskiKutuSurumu,
        };
    for (final (tur, surum) in sunucuSurumleri) {
      final b = benim[tur];
      if (b != null && surumKarsilastir(surum, b) > 0) return true;
    }
    return false;
  }

  /// Cihaz izinin anahtarı — gereken sürümleri taşır: herhangi bir metnin
  /// sürümü artınca iz kendiliğinden geçersiz olur (`DisclaimerService`
  /// `_deviceKey` deseni).
  @visibleForTesting
  static String izAnahtari(String userId) {
    final imza = [
      for (final m in YasalMetinKatalogu.zorunluBelgeler())
        '${m.tur}@${m.surum}',
      '$kutuAnahtari@${YasalMetinKatalogu.kutuSurumu}',
    ].join('|');
    return 'yasal_onay_tam_${imza}_$userId';
  }

  Future<void> _tamamIsaretle(String userId) async {
    _tamam.add(userId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(izAnahtari(userId), true);
    } catch (_) {
      // Disk yazılamazsa bellekteki iz bu süreçte yeter; sonraki açılış
      // sunucuya sorar.
    }
  }

  // ── Kapı ───────────────────────────────────────────────────────────────

  /// Kullanıcıya yeniden onay kapısı gösterilmeli mi?
  ///
  /// Sıra: sürmekte olan kayıt yazımı → bellek → cihaz izi →
  /// sunucu. Onayı tam olan kullanıcı için ağa YALNIZ BİR KEZ gidilir (iz
  /// konur); her açılışta gidiş-dönüş eklenmez. Sorgu düşerse
  /// [YasalKapiDurumu.tamam] (fail-open, iz yok → sonraki açılışta yine).
  Future<YasalKapiDurumu> kapiDurumu(String userId) async {
    final bekleyen = _bekleyen[userId];
    if (bekleyen != null) {
      try {
        await bekleyen.timeout(_timeout);
      } catch (_) {}
    }
    if (_tamam.contains(userId)) return YasalKapiDurumu.tamam;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(izAnahtari(userId)) == true) {
        _tamam.add(userId);
        return YasalKapiDurumu.tamam;
      }
    } catch (_) {}
    try {
      final (onaylar, sunucu) = await (
        _etkinOnaylar(userId),
        _sunucuSurumleri(),
      ).wait.timeout(_kapiTimeout);
      final durum = eksikleriHesapla(onaylar);
      if (!durum.gerekli) {
        await _tamamIsaretle(userId);
        return durum;
      }
      // Sunucuda daha yeni metin var: eskiyi onaylatma (bkz.
      // [uygulamaEski]). İz konmaz; güncel uygulama en yeniyi sorar.
      if (uygulamaEski(sunucu)) return YasalKapiDurumu.tamam;
      return durum;
    } catch (e, st) {
      if (!CrashReporter.agHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'YasalOnayService.kapiDurumu');
      }
      return YasalKapiDurumu.tamam;
    }
  }

  /// Sunucudaki tüm metin sürümleri (tür, sürüm) — `yasal_metinler`
  /// herkese okunur ve küçüktür (tür × sürüm × dil).
  Future<List<(String, String)>> _sunucuSurumleri() async {
    final test = sunucuSurumTesti;
    if (test != null) return test();
    final rows = await Supabase.instance.client
        .from('yasal_metinler')
        .select('tur, surum');
    return [
      for (final r in rows)
        if (r case {'tur': final String t, 'surum': final String s}) (t, s),
    ];
  }

  /// Kullanıcının etkin (geri çekilmemiş) onaylarının (tür, sürüm)
  /// çiftleri. RLS yalnız kendi satırını ve hesabı silinmemiş satırı
  /// gösterir; `yasal_metinler` herkese okunur — yeni RPC gerekmez.
  Future<List<(String, String)>> _etkinOnaylar(String userId) async {
    final test = sorguTesti;
    if (test != null) return test(userId);
    final rows = await Supabase.instance.client
        .from('yasal_onaylar')
        .select('yasal_metinler!inner(tur, surum)')
        .eq('user_id', userId)
        .isFilter('geri_cekildi_at', null);
    return [
      for (final r in rows)
        if (r['yasal_metinler']
            case {'tur': final String t, 'surum': final String s})
          (t, s),
    ];
  }

  /// Kapı ekranında "Okudum, kabul ediyorum" — öğeler [kapiOgeleri]'nde.
  /// Zaten onaylı olan tekrar yazılmaz (sunucu `on conflict do nothing`,
  /// ilk an korunur). Kanal `yeniden_onay`.
  Future<KapiKayitSonucu> kapiOnaylariniKaydet({
    required String userId,
    required YasalKapiDurumu durum,
    required Map<String, String> belgeDegiskenleri,
    required Set<String> acilanBelgeler,
    Set<String> sonunaKadarOkunanlar = const {},
    KapiKutuBaglami? kutu,
    bool yatirimUyarisiDahil = false,
    required String locale,
  }) async {
    final ogeler = kapiOgeleri(
      durum: durum,
      belgeDegiskenleri: belgeDegiskenleri,
      acilanBelgeler: acilanBelgeler,
      sonunaKadarOkunanlar: sonunaKadarOkunanlar,
      kutu: kutu,
      yatirimUyarisiDahil: yatirimUyarisiDahil,
    );
    try {
      await _rpc(ogeler, kanal: 'yeniden_onay', locale: locale);
      await _tamamIsaretle(userId);
      return KapiKayitSonucu.tamam;
    } catch (e, st) {
      if (CrashReporter.agHatasiMi(e)) return KapiKayitSonucu.agHatasi;
      CrashReporter.report(e, st, reason: 'YasalOnayService.yeniden_onay');
      return KapiKayitSonucu.sunucuHatasi;
    }
  }

  /// Bir belgenin RPC öğesi — kayıt ve kapı AYNI biçimi yazar. Saf.
  ///
  /// `degiskenler`: belgede geçen yer tutucuların gösterim değerleri,
  /// `nitelik` ([YasalBelge.nitelik]), `belge_acildi`, `sonuna_kadar_okundu`
  /// ve verilirse ([oncekiEkle]) `onceki_surum` (null = ilk kez).
  static Map<String, dynamic> belgeOgesi(
    YasalBelge b,
    Map<String, String> belgeDegiskenleri, {
    required bool acildi,
    required bool okundu,
    bool oncekiEkle = false,
    String? oncekiSurum,
  }) {
    final m = YasalMetinKatalogu.belge(b);
    return m.rpcOgesi({
      ...YasalMetinKatalogu.belgeDegiskenleri(m, belgeDegiskenleri),
      'nitelik': b.nitelik,
      'belge_acildi': acildi,
      'sonuna_kadar_okundu': okundu,
      if (oncekiEkle) 'onceki_surum': oncekiSurum,
    });
  }

  /// Kapının yazdığı öğeler — saf, test edilir (1.4, okuma sadeleştirme).
  ///
  /// - [kutu] verildiyse (kapı kutuyu gösterdi ve işaretlendi —
  ///   [YasalKapiDurumu.kutuGerekli]): kutu + Koşullar, Gizlilik, KVKK'nın
  ///   güncel sürümü (`sonuna_kadar_okundu: false`). Kutu yoksa bu üçü
  ///   YAZILMAZ: kabulleri/bilgilendirmeleri kutuyla verilir.
  /// - Açık Rıza Metni YALNIZ [sonunaKadarOkunanlar]'daysa (sonuna kadar
  ///   okundu, sonunda onaylandı). Kapı rızayı yalnız eksikse okutur;
  ///   geçerli rıza yeniden yazılmaz.
  /// - Her belgeye `onceki_surum` (yoksa null = ilk kez) girer.
  static List<Map<String, dynamic>> kapiOgeleri({
    required YasalKapiDurumu durum,
    required Map<String, String> belgeDegiskenleri,
    required Set<String> acilanBelgeler,
    Set<String> sonunaKadarOkunanlar = const {},
    KapiKutuBaglami? kutu,
    bool yatirimUyarisiDahil = false,
  }) =>
      [
        if (kutu != null) ...[
          ...kutu.ogeler(),
          for (final b in YasalBelge.kutuylaAlinanlar)
            belgeOgesi(b, belgeDegiskenleri,
                acildi: acilanBelgeler.contains(b.tur),
                okundu: false,
                oncekiEkle: true,
                oncekiSurum: durum.oncekiSurum[b.tur]),
        ],
        if (sonunaKadarOkunanlar.contains(YasalTur.acikRiza))
          belgeOgesi(YasalBelge.acikRiza, belgeDegiskenleri,
              acildi: true,
              okundu: true,
              oncekiEkle: true,
              oncekiSurum: durum.oncekiSurum[YasalTur.acikRiza]),
        if (yatirimUyarisiDahil)
          YasalMetinKatalogu.yatirimUyarisi().rpcOgesi({
            if (sonunaKadarOkunanlar.contains(YasalTur.yatirimUyarisi)) ...{
              'belge_acildi': true,
              'sonuna_kadar_okundu': true,
            },
          }),
      ];

  // ── Kayıtlar ───────────────────────────────────────────────────────────

  /// OTP doğrulandıktan sonra: kayıt kutusu metinleri + andıkları belgeler.
  /// [userId] verilirse yazım kapıya "sürüyor" diye bildirilir ve başarıda
  /// cihaz izi konur: e-postayla yeni kayıt olan kullanıcı aynı sürümleri
  /// az önce onayladı, kapıyı GÖRMEZ.
  Future<bool> kayitOnaylariniKaydet(
    KayitOnayBaglami baglam, {
    required String locale,
    String? userId,
  }) {
    final f = () async {
      final ok = await _kaydet(baglam.ogeler(), kanal: 'kayit', locale: locale);
      if (ok && userId != null) await _tamamIsaretle(userId);
      return ok;
    }();
    if (userId != null) {
      _bekleyen[userId] = f;
      CrashReporter.arkaPlan(f.whenComplete(() {
        if (identical(_bekleyen[userId], f)) _bekleyen.remove(userId);
      }), reason: 'YasalOnayService.bekleyenTemizle');
    }
    return f;
  }

  /// `DisclaimerAcceptanceScreen` onaylanınca: yatırım uyarısı.
  /// [sonunaKadarOkundu]: zorunlu okumada metnin sonuna ulaşıldı.
  Future<bool> yatirimUyarisiniKaydet({
    required String locale,
    bool sonunaKadarOkundu = false,
  }) =>
      _kaydet(
        [
          YasalMetinKatalogu.yatirimUyarisi()
              .rpcOgesi({if (sonunaKadarOkundu) 'sonuna_kadar_okundu': true}),
        ],
        kanal: 'yatirim_uyarisi_ekrani',
        locale: locale,
      );

  /// Zirve açık rızası sunucuya yazıldıktan sonra: kartın metni.
  /// Geri çekme sunucuda (`zirve_rizasi_ayarla`) aynı işlemde damgalanır.
  Future<bool> zirveRizasiniKaydet({
    required String locale,
    bool sonunaKadarOkundu = false,
  }) =>
      _kaydet(
        [
          YasalMetinKatalogu.zirveRiza()
              .rpcOgesi({if (sonunaKadarOkundu) 'sonuna_kadar_okundu': true}),
        ],
        kanal: 'zirve',
        locale: locale,
      );

  Future<bool> _kaydet(
    List<Map<String, dynamic>> ogeler, {
    required String kanal,
    required String locale,
  }) async {
    try {
      await _rpc(ogeler, kanal: kanal, locale: locale);
      return true;
    } catch (e, st) {
      if (!CrashReporter.agHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'YasalOnayService.$kanal');
      }
      return false;
    }
  }

  /// RPC'nin kendisi — fırlatır; çağıran hatayı sınıflandırır.
  Future<void> _rpc(
    List<Map<String, dynamic>> ogeler, {
    required String kanal,
    required String locale,
  }) async {
    final params = parametreler(
      ogeler: ogeler,
      kanal: kanal,
      appVersion: await DisclaimerService.surumEtiketi(),
      platform: DisclaimerService.platformEtiketi(defaultTargetPlatform),
      locale: locale,
    );
    final test = rpcTesti;
    if (test != null) {
      await test(params);
    } else {
      await Supabase.instance.client
          .rpc<dynamic>('yasal_onay_kaydet', params: params)
          .timeout(_timeout);
    }
  }
}
