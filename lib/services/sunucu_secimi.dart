import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/supabase_config.dart';
import 'crash_reporter.dart';

/// Köprü sürümü (K1): uygulama hangi Supabase projesine bağlanacak?
///
/// **Neden Remote Config bayrağı, ikinci mağaza sürümü değil:** Tokyo →
/// Frankfurt geçişini Frankfurt adresli bir sürüme bağlamak, geçiş gecesinin
/// kritik yoluna mağaza onayını koyuyordu; kullanıcı iki kez güncelliyor,
/// geri dönüş yine mağaza istiyordu. Bu sürüm İKİ yapılandırmayı taşır,
/// seçimi Firebase Console'daki tek anahtar yapar (docs/SUPABASE_FRANKFURT_TASIMA.md,
/// "AÇILIŞ YOL HARİTASI").
///
/// **Karar açılışta, Supabase başlamadan ve AĞ BEKLEMEDEN verilir:** Remote
/// Config'in son ETKİNLEŞTİRİLMİŞ değeri diskte durur; açılışı ağa bağlamak
/// her açılışı yavaşlatırdı. Yeni değer arka planda gelir; aktif sunucudan
/// farklıysa [yenidenBaslatGerekli] kalkar ve kullanıcıya "kapatıp aç" denir.
/// Supabase çalışırken yeniden kurulmaz: servis singleton'ları istemciyi
/// tutuyor, sıcak değişim yarım durum bırakırdı.
///
/// Oturum kendiliğinden ayrılır: `SecureSessionStorage` anahtarı proje
/// ref'inden türetilir — Frankfurt'ta Tokyo oturumu HİÇ okunmaz, kullanıcı
/// bir kez giriş yapar (şifresi taşınmıştır). Kullanıcıya özel tercih ve
/// önbellekler kullanıcı UUID'sine bağlı; taşıma UUID'yi koruduğu için
/// geçerli kalır.
class SunucuSecimi {
  SunucuSecimi._();
  static final SunucuSecimi instance = SunucuSecimi._();

  /// Remote Config anahtarları. Console'da tanımlı değilse varsayılan
  /// (`tokyo`, 0) — yani bayrak kurulmadan davranış değişmez.
  static const anahtar = 'sunucu';
  static const minBuildAndroid = 'min_build_android';
  static const minBuildIos = 'min_build_ios';

  SunucuYapilandirmasi? _aktif;
  final _hazir = Completer<SunucuYapilandirmasi?>();

  /// Bu süreçte bağlanılan sunucu. `baslat` çağrılmadan okunmaz.
  SunucuYapilandirmasi get aktif => _aktif!;

  /// Arayüz metinleri için: test/önizlemede `baslat` çağrılmamış olabilir.
  SunucuYapilandirmasi? get aktifOrNull => _aktif;

  /// Karar verildiğinde biter. Arka plan işleri (Analytics) açılışla YARIŞIR —
  /// `aktif`'i doğrudan okumak yerine bunu bekler.
  Future<SunucuYapilandirmasi?> get hazir => _hazir.future;

  /// Uygulama başka bir sunucuya geçmeli — kapatıp açmak gerek.
  final yenidenBaslatGerekli = ValueNotifier<bool>(false);

  /// Bu derleme artık desteklenmiyor — mağazadan güncellemek gerek.
  final guncellemeGerekli = ValueNotifier<bool>(false);

  int _mevcutBuild = 0;

  /// Açılış kararı. `null` = derlemede hiç sunucu yok (yapılandırma hatası).
  Future<SunucuYapilandirmasi?> baslat() async {
    var istenen = '';
    var minBuild = 0;
    try {
      final rc = FirebaseRemoteConfig.instance;
      // Diskteki son etkin değerleri yükler — AĞA ÇIKMAZ.
      await rc.ensureInitialized();
      istenen = rc.getString(anahtar);
      minBuild = rc.getInt(minBuildAnahtari);
    } catch (e, st) {
      // Firebase kurulamadıysa (config yok, ilk açılış) varsayılan sunucu.
      CrashReporter.report(e, st, reason: 'SunucuSecimi.baslat');
    }
    _aktif = sunucuSec(
      istenen: istenen,
      birincilUrl: supabaseUrl,
      birincilKey: supabaseAnonKey,
      euUrl: supabaseUrlEu,
      euKey: supabaseAnonKeyEu,
    );
    try {
      _mevcutBuild = int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    } catch (_) {}
    guncellemeGerekli.value =
        guncellemeGerekliMi(mevcutBuild: _mevcutBuild, minBuild: minBuild);
    if (!_hazir.isCompleted) _hazir.complete(_aktif);
    return _aktif;
  }

  /// Remote Config yeni değerleri ETKİNLEŞTİRDİKTEN sonra çağrılır
  /// (açılış fetch'i ve gerçek zamanlı güncelleme — `RemoteConfigService`).
  void rcGuncellendi({required String istenen, required int minBuild}) {
    final aktif = _aktif;
    if (aktif == null) return;
    final yeni = sunucuSec(
      istenen: istenen,
      birincilUrl: supabaseUrl,
      birincilKey: supabaseAnonKey,
      euUrl: supabaseUrlEu,
      euKey: supabaseAnonKeyEu,
    );
    if (yeni != null && yeni.url != aktif.url) yenidenBaslatGerekli.value = true;
    guncellemeGerekli.value =
        guncellemeGerekliMi(mevcutBuild: _mevcutBuild, minBuild: minBuild);
  }

  /// Platforma göre min build anahtarı — `RemoteConfigService` de okur.
  /// Android versionCode ile iOS build numarası ayrı sayar, bu yüzden iki anahtar.
  static String get minBuildAnahtari =>
      defaultTargetPlatform == TargetPlatform.iOS ? minBuildIos : minBuildAndroid;

  @visibleForTesting
  void testIcinKur(SunucuYapilandirmasi aktif, {int mevcutBuild = 0}) {
    _aktif = aktif;
    _mevcutBuild = mevcutBuild;
    yenidenBaslatGerekli.value = false;
    guncellemeGerekli.value = false;
  }
}

/// Seçilen sunucu. [ulke]/[ulkede] bilinen projeler için dolu; bilinmeyen
/// (yerel yığın) için `null` — rıza metni ülke uydurmaz.
@immutable
class SunucuYapilandirmasi {
  const SunucuYapilandirmasi({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  String get ref => Uri.tryParse(url)?.host.split('.').first ?? '';

  /// `tokyo` | `frankfurt` | `bilinmiyor` — Analytics kullanıcı özelliği.
  String get ad => supabaseProjeUlkeleri[ref]?.ad ?? 'bilinmiyor';
  String? get ulke => supabaseProjeUlkeleri[ref]?.ulke;
  String? get ulkede => supabaseProjeUlkeleri[ref]?.ulkede;
}

/// SAF karar: istenen sunucu + derlemedeki yapılandırmalar → bağlanılacak.
///
/// * `frankfurt` isteniyor ve derlemede EU varsa → EU.
/// * Aksi hâlde birincil (bugün Tokyo; K5'ten sonra birincil zaten Frankfurt
///   olur ve EU boş kalır — bayrak etkisizleşir, kod değişmez).
/// * Birincil boş ama EU doluysa → EU (yalnız EU'lu derleme).
/// * İkisi de boşsa `null` → yapılandırma hatası ekranı.
///
/// Bilinmeyen değer (yazım hatası, boş) birincile düşer: Console'da yanlış
/// yazılmış bir değer herkesi bilinmeyen bir yere GÖNDERMEZ.
SunucuYapilandirmasi? sunucuSec({
  required String istenen,
  required String birincilUrl,
  required String birincilKey,
  required String euUrl,
  required String euKey,
}) {
  final euVar = euUrl.isNotEmpty && euKey.isNotEmpty;
  final birincilVar = birincilUrl.isNotEmpty && birincilKey.isNotEmpty;
  if (istenen.trim().toLowerCase() == 'frankfurt' && euVar) {
    return SunucuYapilandirmasi(url: euUrl, anonKey: euKey);
  }
  if (birincilVar) return SunucuYapilandirmasi(url: birincilUrl, anonKey: birincilKey);
  if (euVar) return SunucuYapilandirmasi(url: euUrl, anonKey: euKey);
  return null;
}

/// SAF karar: bu derleme zorunlu güncelleme kapısına takılıyor mu?
///
/// `minBuild <= 0` (Console'da tanımsız) → hayır. `mevcutBuild` okunamadıysa
/// (0) → hayır: bilinmeyen durumda kullanıcıyı kilitlemek, açık bırakmaktan
/// kötüdür (kapı geçişte Tokyo'nun dondurulmasıyla birlikte çalışır — tek
/// başına veri koruması değil).
bool guncellemeGerekliMi({required int mevcutBuild, required int minBuild}) =>
    minBuild > 0 && mevcutBuild > 0 && mevcutBuild < minBuild;
