import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'crash_reporter.dart';
import 'disclaimer_service.dart';
import 'remote_config_service.dart';
import 'yasal_metin_katalogu.dart';

/// Kayıt ekranında kullanıcının GÖRDÜĞÜ onay düzeni — `RegisterScreen`
/// gönderim anında kurar, `OtpVerificationScreen` doğrulamadan sonra
/// [YasalOnayService.kayitOnaylariniKaydet]'e verir (oturum ancak OTP
/// doğrulanınca açılır; kayıt ekranında `auth.uid()` yok).
@immutable
class KayitOnayBaglami {
  const KayitOnayBaglami({
    required this.tekKutu,
    required this.dil,
    required this.kutuUlkesi,
    required this.belgeDegiskenleri,
    required this.kosulBelgesiAcildi,
    required this.rizaBelgesiAcildi,
    this.kvkkBelgesiAcildi = false,
    this.gizlilikBelgesiAcildi = false,
  });

  /// Bayrak `tek_onay_kutusu` ekran açılışında açık mıydı.
  final bool tekKutu;

  /// Tek kutu l10n'dan çizilir → arayüz dili (`tr`/`en`). İki kutu ve
  /// belgeler her dilde Türkçe gösterilir; onlar için kullanılmaz.
  final String dil;

  /// Kutu metnindeki `{SUPABASE_ULKE}` yerine ekranda yazan değer.
  final String kutuUlkesi;

  /// Belgelerdeki yer tutucuların gösterim değerleri
  /// (`LegalDocs.yerTutucuDegerleri`).
  final Map<String, String> belgeDegiskenleri;

  /// Kullanıcı bağlantıdan belgeyi en az bir kez açtı mı (kanıt notu).
  /// [rizaBelgesiAcildi]: "açık rıza" bağlantısı — 1.2'den beri Açık Rıza
  /// Metni'ni açar (1.1'de Gizlilik Politikası'nı açıyordu).
  final bool kosulBelgesiAcildi;
  final bool rizaBelgesiAcildi;
  final bool kvkkBelgesiAcildi;
  final bool gizlilikBelgesiAcildi;

  /// Kayıtta onaylanan metinler + her birinin gösterim değişkenleri — saf,
  /// test edilir.
  ///
  /// ## Ne girer, ne girmez
  /// - Kutu(lar): kullanıcının işaretlediği cümle(ler), gördüğü düzende.
  /// - Belgeler: dört belgenin dördü de ([YasalBelge]). Koşullar, KVKK ve
  ///   açık rıza kutu cümlesinde adıyla geçer; Gizlilik Politikası iki
  ///   kutulu düzende kutu metninde adıyla, her düzende Koşullar §1'de
  ///   atıfla. Dördü de kayıt ekranından bağlantıyla açılır (KVKK
  ///   2026-10-04'ten, Açık Rıza Metni ve Gizlilik'in kendi bağlantısı
  ///   1.2'den beri). Açılıp açılmadığı `belge_acildi` ile yazılır — ispat
  ///   ne kadar güçlüyse o kadarını söylesin. Yer tutucu değerleri yalnız
  ///   o belgede geçenler ([YasalMetinKatalogu.belgeDegiskenleri]).
  /// - Yatırım uyarısı (`disclaimerText`) GİRMEZ: kayıt ekranında
  ///   gösterilmiyor. Kutunun "yatırım tavsiyesi değildir" maddesi kutu
  ///   metninin içinde zaten kayıtlı. (`disclaimer_acceptances` eskisi gibi
  ///   OTP sonrası yazılır — bozmama kuralı; o kaydın gösterilmemiş bir
  ///   metnin hash'ini taşıdığı YAPMAN'da avukat sorusu.)
  List<Map<String, dynamic>> ogeler() {
    final kutular = tekKutu
        ? [
            YasalMetinKatalogu.kayitTekKutu(dil)
                .rpcOgesi({'SUPABASE_ULKE': kutuUlkesi}),
          ]
        : [
            YasalMetinKatalogu.kayitKutuKosullar().rpcOgesi(),
            YasalMetinKatalogu.kayitKutuRiza()
                .rpcOgesi({'SUPABASE_ULKE': kutuUlkesi}),
          ];
    Map<String, dynamic> belge(YasalMetin m, bool acildi) => m.rpcOgesi({
          ...YasalMetinKatalogu.belgeDegiskenleri(m, belgeDegiskenleri),
          'belge_acildi': acildi,
        });
    return [
      ...kutular,
      belge(YasalMetinKatalogu.kosullar(), kosulBelgesiAcildi),
      belge(YasalMetinKatalogu.gizlilik(), gizlilikBelgesiAcildi),
      belge(YasalMetinKatalogu.kvkk(), kvkkBelgesiAcildi),
      belge(YasalMetinKatalogu.acikRiza(), rizaBelgesiAcildi),
    ];
  }
}

/// Yeniden onay kapısının kararı — kullanıcının hangi zorunlu metinlerin
/// GÜNCEL sürümüne etkin onayı eksik.
@immutable
class YasalKapiDurumu {
  const YasalKapiDurumu({this.eksik = const {}, this.oncekiSurum = const {}});

  /// Kapı yok: onaylar tam, bayrak kapalı ya da sorgu düştü (fail-open).
  static const tamam = YasalKapiDurumu();

  /// Eksik türler: belgeler ([YasalBelge] türleri) ve kayıt kutusu
  /// taahhütleri için [YasalOnayService.kutuAnahtari].
  final Set<String> eksik;

  /// Tür → kullanıcının etkin onayı olan EN YENİ sürüm (eksik olsa bile —
  /// "güncellendi" mi yoksa "ilk kez" mi sorusunun cevabı).
  final Map<String, String> oncekiSurum;

  bool get gerekli => eksik.isNotEmpty;

  /// Kayıt kutusu taahhütleri (18+, yurt dışı aktarım açık rızası) eksik
  /// mi — kapı kutuları gösterir.
  bool get kutuEksik => eksik.contains(YasalOnayService.kutuAnahtari);

  /// Belgelerden en az birinin eski sürümü onaylı: başlık "Güncellenen
  /// belgeler" der; hiç yoksa (sosyal girişle ilk kez, 0102 öncesi hesap)
  /// "Yasal belgeler".
  bool get guncellemeMi => YasalMetinKatalogu.zorunluBelgeler()
      .any((m) => oncekiSurum.containsKey(m.tur));
}

/// Kapı ekranının kurduğu kutu düzeni (kayıt ekranıyla aynı karar:
/// `tek_onay_kutusu` açıksa tek kutu, değilse iki kutu).
@immutable
class KapiKutuBaglami {
  const KapiKutuBaglami({
    required this.tekKutu,
    required this.dil,
    required this.kutuUlkesi,
  });

  final bool tekKutu;
  final String dil;
  final String kutuUlkesi;

  List<Map<String, dynamic>> ogeler() => tekKutu
      ? [
          YasalMetinKatalogu.kayitTekKutu(dil)
              .rpcOgesi({'SUPABASE_ULKE': kutuUlkesi}),
        ]
      : [
          YasalMetinKatalogu.kayitKutuKosullar().rpcOgesi(),
          YasalMetinKatalogu.kayitKutuRiza()
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
/// ## Neden ayrı servis, neden bayrak
/// `disclaimer_acceptances` yalnız yatırım uyarısını tutuyordu; kayıt
/// kutuları (koşullar, KVKK, yurt dışı aktarım açık rızası) hiç
/// kaydedilmiyordu. 0102 her metni (tür, sürüm, dil, hash) ile saklar ve
/// onayı RPC ile alır. Remote Config `yasal_onay_kaydi` varsayılan KAPALI:
/// 0102 iki sunucuya dağıtılmadan açılırsa her kayıtta "fonksiyon yok"
/// hatası üretir. Kapalıyken hiçbir ağ çağrısı yapılmaz — davranış birebir
/// eski.
///
/// ## Yeniden onay kapısı (kullanıcı kararı 2026-10-04)
/// *"Eski rıza metnini onaylayanlar için ilk login'de güncel doküman
/// sunulup onay istenmeli."* [kapiDurumu] kullanıcının zorunlu metinlerin
/// GÜNCEL sürümüne etkin onayı var mı diye bakar; yoksa `_AuthGate`
/// `YasalOnayKapisiScreen`'i gösterir. Metin sürümü her arttığında
/// kendiliğinden çalışır (cihaz izinin anahtarında sürümler var). Bayrak
/// `yasal_kapi_en_yeni` (KAPALI) yalnız `yasal_onay_kaydi` de açıkken
/// etkilidir: kayıt yazılamazsa kapı her açılışta yeniden sorardı.
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

  /// Kapı etkin mi — iki bayrak birden.
  static bool get kapiEtkin =>
      RemoteConfigService.instance.yasalOnayKaydi &&
      RemoteConfigService.instance.yenidenOnayKapisi;

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
  /// Kayıt kutusu taahhütleri iki düzenin biriyle tamamlanır: iki kutu
  /// (koşullar kutusu + yurt dışı aktarım rızası kutusu) YA DA tek kutu.
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
    const kutu = YasalMetinKatalogu.kutuSurumu;
    final kutuTamam = tamamMi(YasalTur.kayitTekKutu, kutu) ||
        (tamamMi(YasalTur.kayitKutuKosullar, kutu) &&
            tamamMi(YasalTur.kayitKutuRiza, kutu));
    if (!kutuTamam) eksik.add(kutuAnahtari);
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
  static bool uygulamaEski(Iterable<(String, String)> sunucuSurumleri) {
    final benim = <String, String>{
      for (final m in YasalMetinKatalogu.zorunluBelgeler()) m.tur: m.surum,
      YasalTur.kayitTekKutu: YasalMetinKatalogu.kutuSurumu,
      YasalTur.kayitKutuKosullar: YasalMetinKatalogu.kutuSurumu,
      YasalTur.kayitKutuRiza: YasalMetinKatalogu.kutuSurumu,
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
  /// Sıra: bayraklar → sürmekte olan kayıt yazımı → bellek → cihaz izi →
  /// sunucu. Onayı tam olan kullanıcı için ağa YALNIZ BİR KEZ gidilir (iz
  /// konur); her açılışta gidiş-dönüş eklenmez. Sorgu düşerse
  /// [YasalKapiDurumu.tamam] (fail-open, iz yok → sonraki açılışta yine).
  Future<YasalKapiDurumu> kapiDurumu(String userId) async {
    if (!kapiEtkin) return YasalKapiDurumu.tamam;
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

  /// Kapı ekranında "Okudum, kabul ediyorum": dört güncel belge (zaten
  /// onaylı olan tekrar yazılmaz — sunucu `on conflict do nothing`, ilk an
  /// korunur), [kutu] verildiyse kayıt kutusu taahhütleri,
  /// [yatirimUyarisiDahil] ise ekranda gösterilen yatırım uyarısı.
  /// Kanal `yeniden_onay`.
  Future<KapiKayitSonucu> kapiOnaylariniKaydet({
    required String userId,
    required YasalKapiDurumu durum,
    required Map<String, String> belgeDegiskenleri,
    required Set<String> acilanBelgeler,
    KapiKutuBaglami? kutu,
    bool yatirimUyarisiDahil = false,
    required String locale,
  }) async {
    if (!RemoteConfigService.instance.yasalOnayKaydi) {
      return KapiKayitSonucu.sunucuHatasi;
    }
    final ogeler = kapiOgeleri(
      durum: durum,
      belgeDegiskenleri: belgeDegiskenleri,
      acilanBelgeler: acilanBelgeler,
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

  /// Kapının yazdığı öğeler — saf, test edilir. Her belgeye `onceki_surum`
  /// (yoksa null = ilk onay) ve `belge_acildi` kanıt notu girer.
  static List<Map<String, dynamic>> kapiOgeleri({
    required YasalKapiDurumu durum,
    required Map<String, String> belgeDegiskenleri,
    required Set<String> acilanBelgeler,
    KapiKutuBaglami? kutu,
    bool yatirimUyarisiDahil = false,
  }) =>
      [
        if (kutu != null) ...kutu.ogeler(),
        for (final m in YasalMetinKatalogu.zorunluBelgeler())
          m.rpcOgesi({
            ...YasalMetinKatalogu.belgeDegiskenleri(m, belgeDegiskenleri),
            'belge_acildi': acilanBelgeler.contains(m.tur),
            'onceki_surum': durum.oncekiSurum[m.tur],
          }),
        if (yatirimUyarisiDahil) YasalMetinKatalogu.yatirimUyarisi().rpcOgesi(),
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
  Future<bool> yatirimUyarisiniKaydet({required String locale}) => _kaydet(
        [YasalMetinKatalogu.yatirimUyarisi().rpcOgesi()],
        kanal: 'yatirim_uyarisi_ekrani',
        locale: locale,
      );

  /// Zirve açık rızası sunucuya yazıldıktan sonra: kartın metni.
  /// Geri çekme sunucuda (`zirve_rizasi_ayarla`) aynı işlemde damgalanır.
  Future<bool> zirveRizasiniKaydet({required String locale}) => _kaydet(
        [YasalMetinKatalogu.zirveRiza().rpcOgesi()],
        kanal: 'zirve',
        locale: locale,
      );

  Future<bool> _kaydet(
    List<Map<String, dynamic>> ogeler, {
    required String kanal,
    required String locale,
  }) async {
    if (!RemoteConfigService.instance.yasalOnayKaydi) return false;
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
