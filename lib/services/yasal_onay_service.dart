import 'package:flutter/foundation.dart';
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
  final bool kosulBelgesiAcildi;
  final bool rizaBelgesiAcildi;

  /// Kayıtta onaylanan metinler + her birinin gösterim değişkenleri — saf,
  /// test edilir.
  ///
  /// ## Ne girer, ne girmez
  /// - Kutu(lar): kullanıcının işaretlediği cümle(ler), gördüğü düzende.
  /// - Belgeler: kutu cümlesinin adıyla andığı üç belge. Koşullar ve
  ///   Gizlilik kutudan bağlantıyla açılır; KVKK Aydınlatma Metni cümlede
  ///   ADI geçer ama kayıt ekranından açılan bir bağlantısı YOK ("Yasal
  ///   Koşullar & KVKK Aydınlatma" başlıklı sayfa yalnız Koşulları
  ///   gösterir). Bu `degiskenler`'e yazılır — ispat ne kadar güçlüyse o
  ///   kadarını söylesin.
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
    return [
      ...kutular,
      YasalMetinKatalogu.kosullar()
          .rpcOgesi({'belge_acildi': kosulBelgesiAcildi}),
      YasalMetinKatalogu.gizlilik().rpcOgesi(
          {...belgeDegiskenleri, 'belge_acildi': rizaBelgesiAcildi}),
      YasalMetinKatalogu.kvkk().rpcOgesi(
          {...belgeDegiskenleri, 'kayit_ekraninda_baglanti': false}),
    ];
  }
}

/// Yasal metin onaylarını sunucuya (`yasal_onaylar`, 0102) yazar.
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
/// ## En iyi gayret
/// Hiçbir yöntem fırlatmaz ve akışı beklemez (çağıranlar `unawaited`):
/// onay kaydı düşerse kullanıcı yine devam eder. Bağlantı hatası dışındaki
/// her hata (hash uyuşmazlığı = metin kayması dahil) Crashlytics'e non-fatal
/// gider — kilit testi atlanıp yanlış metin yayına çıkarsa böyle görünür.
/// `disclaimer_acceptances` ve `_AuthGate` kapısı buna DOKUNULMADI.
class YasalOnayService {
  YasalOnayService._();
  static final YasalOnayService instance = YasalOnayService._();

  static const _timeout = Duration(seconds: 15);

  /// Yalnız test: RPC yerine çağrılır (Supabase testte ayağa kalkmaz).
  @visibleForTesting
  static Future<void> Function(Map<String, dynamic> params)? rpcTesti;

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

  /// OTP doğrulandıktan sonra: kayıt kutusu metinleri + andıkları belgeler.
  Future<bool> kayitOnaylariniKaydet(
    KayitOnayBaglami baglam, {
    required String locale,
  }) =>
      _kaydet(baglam.ogeler(), kanal: 'kayit', locale: locale);

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
      return true;
    } catch (e, st) {
      if (!CrashReporter.agHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'YasalOnayService.$kanal');
      }
      return false;
    }
  }
}
