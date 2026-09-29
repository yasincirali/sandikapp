import 'package:flutter/foundation.dart';

import '../services/remote_config_service.dart';
import '../utils/friendly_error.dart' show KullaniciMesajli;

/// "Örnek portföyle dene" (F1) açık mı — ve açıkken dünyaya çıkan her
/// yolun tek kapısı.
///
/// ## Neden statik bir bayrak (ADR-1, `docs/BUYUME_OZELLIKLERI_TEKNIK_PLAN_2026_09.md`)
/// Demo sunucuya HİÇ dokunmaz: Supabase çağrısı, yazma, push kaydı yok.
/// Verinin kendisi `DemoKabugu`'nun kendi `ProviderContainer`'ında yaşar
/// (sağlayıcılar orada demo sürümleriyle değiştirilir). Ama ekranların bir
/// kısmı singleton servisleri doğrudan çağırıyor (`InflationService`,
/// `HistoryService` gözlem kaynağı, tercih yazımları…); bunlar Riverpod
/// kapsamını görmez. Onlara "demo açık mı" sorusunu soracak tek yer bu.
///
/// Gerçek akışta [aktif] HER ZAMAN false: yalnızca `DemoKabugu` açar
/// (initState) ve kapatır (dispose). Bayrak kapalıyken eklenen kapıların
/// hiçbiri davranış değiştirmez — tek satırlık `if (DemoModu.aktif)`.
class DemoModu {
  DemoModu._();

  /// Sayaç, bool değil: kabuk bir şekilde iki kez kurulursa (hot reload,
  /// test) ilk `dispose` ikincisi hâlâ açıkken bayrağı indirmesin.
  static int _derinlik = 0;

  static bool get aktif => _derinlik > 0;

  /// `DemoKabugu.initState` çağırır.
  static void ac() => _derinlik++;

  /// `DemoKabugu.dispose` çağırır. Sıfırın altına inmez.
  static void kapat() {
    if (_derinlik > 0) _derinlik--;
  }

  // ── Sunucu kapısı ─────────────────────────────────────────────────────────

  static final List<String> _ihlaller = [];

  /// Demo açıkken sunucuya uzanmaya çalışan yollar — test bunun BOŞ
  /// olduğunu doğrular. Kapı istisnası çağıranın `catch`'inde yutulsa bile
  /// (servislerin çoğu hatayı sessizce boş listeye çevirir) iz burada kalır.
  @visibleForTesting
  static List<String> get ihlaller => List.unmodifiable(_ihlaller);

  @visibleForTesting
  static void ihlalleriSifirla() => _ihlaller.clear();

  /// Sunucu geçidinin (`SupabaseService`) demo kapısı: izi bırakır ve
  /// fırlatılacak istisnayı döndürür. Çağıran `throw` eder — istek ağa
  /// hiç çıkmaz.
  static DemoSunucuEngeli sunucuEngeli(String nerede) {
    // Yığının başı iz olarak saklanır: test kırıldığında HANGİ ekran/servis
    // çağrısının kaçtığını söylesin, yalnızca "SupabaseService" değil.
    // Liste üretimde de yaşar (kapı hep açık); sızıntı döngüdeyse belleği
    // büyütmesin diye ilk 50 iz yeter.
    if (_ihlaller.length < 50) {
      final yigin = StackTrace.current.toString().split('\n').take(10);
      _ihlaller.add('$nerede\n${yigin.join('\n')}');
    }
    return DemoSunucuEngeli(nerede);
  }

  // ── Yazma girişimi ────────────────────────────────────────────────────────

  static void Function(String neden)? _yazmaDinleyicisi;

  /// Kabuk "Kaydetmek için hesap oluştur" sayfasını açan işlevi bağlar;
  /// dönen işlev bağı çözer.
  static VoidCallback yazmaDinleyicisiniBagla(void Function(String) f) {
    _yazmaDinleyicisi = f;
    return () {
      if (identical(_yazmaDinleyicisi, f)) _yazmaDinleyicisi = null;
    };
  }

  /// Arayüzdeki yazma girişlerinin tek satırlık kapısı:
  /// `if (DemoModu.yazmaKapisi('alarm')) return;`
  ///
  /// Demo kapalıyken `false` döner ve HİÇBİR ŞEY yapmaz. Açıkken kabuğa
  /// "hesap oluştur" sayfasını açtırır ve `true` döner; çağıran eylemi
  /// başlatmadan çıkar. [neden] `demo_converted` olayının `from` alanıdır.
  static bool yazmaKapisi(String neden) {
    if (!aktif) return false;
    _yazmaDinleyicisi?.call(neden);
    return true;
  }

  /// Sağlayıcı katmanının güvenlik ağı: arayüz kapısından kaçan bir yazma
  /// buraya düşer. Sayfayı açtırır ve [DemoYazmaEngeli] fırlatır — çağıran
  /// "kaydedildi" başarı yoluna hiç girmez, sunucuya hiçbir şey gitmez.
  static Never yazmaEngeli(String neden) {
    _yazmaDinleyicisi?.call(neden);
    throw DemoYazmaEngeli(neden);
  }

  // ── Giriş noktası bayrağı ─────────────────────────────────────────────────

  /// Giriş ekranındaki "Önce bir göz at" düğmesi çizilsin mi.
  ///
  /// Remote Config `demo_mode_enabled` (debug'da açık, yayında kapalı).
  /// İşlev olarak tutulur ki test bayrağı kapalı hâliyle deneyebilsin —
  /// `RemoteConfigService` testte Firebase'siz varsayılana düşer ve o
  /// varsayılan debug'da `true`.
  static bool Function() girisDugmesiAcik =
      () => RemoteConfigService.instance.demoModeEnabled;
}

/// Demo açıkken sunucu geçidine ulaşan çağrının istisnası.
class DemoSunucuEngeli implements Exception {
  const DemoSunucuEngeli(this.nerede);
  final String nerede;

  @override
  String toString() => 'DemoSunucuEngeli($nerede)';
}

/// Demo verisine yazma girişimi — sağlayıcı katmanında durdurulur.
///
/// [KullaniciMesajli]: `friendlyError` / `showAppError` mesajı olduğu gibi
/// gösterir ("Bir şeyler ters gitti" değil); ham teknik metin taşımaz.
class DemoYazmaEngeli implements KullaniciMesajli {
  const DemoYazmaEngeli(this.neden);
  final String neden;

  @override
  String get message =>
      'Örnek portföyde değişiklik kaydedilmez. Kaydetmek için hesap oluştur.';

  @override
  String toString() => message;
}
