import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../demo/demo_modu.dart';
import '../utils/friendly_error.dart' show baglantiHatasiMi;
import 'crash_reporter.dart';

/// Kayıt hunisinin istemci adımları — sunucudaki `huni_olaylari_adim_chk`
/// ile BİREBİR (migration 0097; `huni_kaydi_test` iki listeyi karşılaştırır).
///
/// `kayit` ve `ilk_varlik` burada YOK: onları sunucu kendi kayıtlarından
/// (`auth.users`, `assets.created_at`) bilir. İstemci yalnızca sunucunun
/// göremediği adımları yazar — bkz. migration başlığı "Sunucu doğrusu önce
/// gelir".
enum HuniAdimi {
  ilkAcilis('ilk_acilis'),
  kayitEkrani('kayit_ekrani'),
  kayitFormu('kayit_formu'),
  otpGonderildi('otp_gonderildi'),
  otpDogrulandi('otp_dogrulandi'),
  kayitHatasi('kayit_hatasi'),
  ilkGiris('ilk_giris'),
  yasalOnay('yasal_onay'),
  kullaniciAdi('kullanici_adi'),
  tur('tur'),
  anaEkran('ana_ekran');

  const HuniAdimi(this.kod);
  final String kod;
}

/// Kayıt hunisinin SUNUCU ayağı: adımları `huni_kaydet` RPC'sine yazar ki
/// kontrol paneli "indiren → kayıt ekranı → kayıt → ilk giriş → ilk
/// varlık" hunisini gösterebilsin (2026-10-02).
///
/// Firebase'deki `signup_step` olayları yerinde kalır; bu onların yerine
/// geçmez. Fark: panel Firebase'i okuyamaz ve Firebase kişiyi kayıtlarıyla
/// (hata, ilk varlık) birleştiremez.
///
/// ## Kimlik
/// Cihazda bir kez üretilen rastgele `kurulum_id`. Cihaz kimliği, reklam
/// kimliği, e-posta YOK. Oturum açılınca sunucu bu kurulumun satırlarını
/// `auth.uid()` ile kişiye bağlar — istemci user_id göndermez.
///
/// ## Yalnızca YENİ kurulumlar
/// Bu sürüme GÜNCELLEME ile gelen cihaz huniye girmez: onun "ilk açılışı"
/// aylar önceydi ve ilk girişi şimdi yazılsaydı yeni kullanıcı gibi
/// sayılırdı. Ayırt edici, [RetentionTracker]'ın kurulum günüdür — o anahtar
/// zaten varsa cihaz eskidir. Bu yüzden [hazirla] RetentionTracker'dan
/// ÖNCE çağrılmalı (main, `initPreferencesCache` ardından).
///
/// ## Teslim
/// Olay önce diske (bekleyen kuyruğu), sonra sunucuya: kayıt ekranı çoğu
/// zaman zayıf bağlantıda açılır ve kaybolan olay huniyi olduğundan kötü
/// gösterir. Kuyruk sırayla boşalır; ilk başarısızlıkta durur, sonraki
/// olayda ya da açılışta yeniden dener. Her adım kurulum başına bir kez
/// (sunucuda da tekil indeks var — çift teslim zararsız).
class HuniKaydi {
  HuniKaydi._();
  static final HuniKaydi instance = HuniKaydi._();

  @visibleForTesting
  static const kurulumAnahtari = 'huni_kurulum_id';
  @visibleForTesting
  static const aktifAnahtari = 'huni_aktif';
  @visibleForTesting
  static const gonderilenAnahtari = 'huni_gonderilen';
  @visibleForTesting
  static const bekleyenAnahtari = 'huni_bekleyen';

  /// `RetentionTracker._kInstallDay` — eski kurulumun izi.
  @visibleForTesting
  static const eskiKurulumIzi = 'retention_install_day';

  /// Kuyruk tavanı: uzun çevrimdışı dönemde tercih dosyası şişmesin.
  /// Huninin bütün adımları + birkaç hata buna sığar.
  static const _kuyrukTavani = 30;

  /// Sunucuya giden tek çağrı. Testte değiştirilir.
  @visibleForTesting
  Future<void> Function(Map<String, dynamic> params) gonderici = _rpc;

  @visibleForTesting
  DateTime Function() saat = DateTime.now;

  Future<void>? _hazir;
  Future<void>? _akan;
  bool _aktif = false;
  String? _kurulumId;
  String? _surum;
  bool _hataBildirildi = false;

  /// Kurulumu tanır; yeni kurulumsa `ilk_acilis`'i kuyruğa koyar.
  /// Ağ kullanmaz — Supabase kurulmadan çağrılabilir.
  Future<void> hazirla() => _hazir ??= _hazirla();

  Future<void> _hazirla() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kayitli = prefs.getString(kurulumAnahtari);
      if (kayitli != null) {
        _kurulumId = kayitli;
        _aktif = prefs.getBool(aktifAnahtari) ?? false;
        return;
      }
      final yeni = prefs.getInt(eskiKurulumIzi) == null;
      _kurulumId = const Uuid().v4();
      _aktif = yeni;
      await prefs.setString(kurulumAnahtari, _kurulumId!);
      await prefs.setBool(aktifAnahtari, yeni);
      if (yeni) await _kuyrugaKoy(prefs, HuniAdimi.ilkAcilis, '');
    } catch (e, st) {
      _aktif = false;
      CrashReporter.report(e, st, reason: 'HuniKaydi.hazirla');
    }
  }

  /// Adımı kaydeder. Eski kurulumda, demoda ya da adım zaten yazılmışsa
  /// hiçbir şey yapmaz. Hata FIRLATMAZ — huni ölçümü akışı bozamaz.
  Future<void> kaydet(HuniAdimi adim, {String detay = ''}) async {
    if (DemoModu.aktif) return;
    final hazir = _hazir;
    if (hazir == null) return; // hazirla() çağrılmadı (test, eski yol).
    await hazir;
    if (!_aktif) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _kuyrugaKoy(prefs, adim, detay);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HuniKaydi.kaydet');
      return;
    }
    await bosalt();
  }

  /// Kayıt/giriş sırasında alınan hata. [asama]: kayit | otp | otp_tekrar |
  /// giris | sosyal. Detay yalnızca hata SINIFI ve KODU taşır, mesaj asla
  /// (mesaj e-posta içerebilir; sunucu biçimi ayrıca kısıtlar).
  Future<void> hata(String asama, Object e) =>
      kaydet(HuniAdimi.kayitHatasi, detay: hataDetayi(asama, e));

  /// Firebase `signup_step` adının huni karşılığı; tanınmayan ad `null`.
  static HuniAdimi? signupStepten(String step) => switch (step) {
        'form_opened' => HuniAdimi.kayitFormu,
        'otp_sent' => HuniAdimi.otpGonderildi,
        'otp_verified' => HuniAdimi.otpDogrulandi,
        'disclaimer_accepted' => HuniAdimi.yasalOnay,
        'username_set' => HuniAdimi.kullaniciAdi,
        'tour_done' => HuniAdimi.tur,
        'home_first_seen' => HuniAdimi.anaEkran,
        _ => null,
      };

  /// "asama:kod" — sunucu biçimi `^[a-z0-9_]{1,24}:[a-z0-9_]{1,40}$`.
  /// Nokta ve @ hiç yok: biçime uymayan detayı sunucu 'gecersiz' yapar,
  /// burada da aynı alfabeye indirgenir ki gerçek kod kaybolmasın.
  static String hataDetayi(String asama, Object e) =>
      '${_parca(asama, 24)}:${_parca(hataKodu(e), 40)}';

  static String _parca(String s, int azami) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    if (t.isEmpty) return 'bilinmiyor';
    return t.length > azami ? t.substring(0, azami) : t;
  }

  /// Hatanın sınıfı — mesajına BAKMADAN. GoTrue kodu en ayırt edici olanı
  /// (`weak_password`, `otp_expired`, `over_email_send_rate_limit`).
  static String hataKodu(Object e) {
    if (e is AuthException) {
      final kod = e.code ?? e.statusCode;
      return 'auth_${kod ?? 'kodsuz'}';
    }
    if (e is TimeoutException) return 'zaman_asimi';
    if (baglantiHatasiMi(e)) return 'ag';
    if (e is PostgrestException) return 'pg_${e.code ?? 'kodsuz'}';
    return 'diger';
  }

  /// Bekleyenleri sırayla gönderir. Aynı anda tek boşaltma.
  Future<void> bosalt() => _akan ??= _bosalt().whenComplete(() => _akan = null);

  Future<void> _bosalt() async {
    if (!_aktif || _kurulumId == null) return;
    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    while (true) {
      final bekleyen = _bekleyenler(prefs);
      if (bekleyen.isEmpty) return;
      final o = bekleyen.first;
      try {
        await gonderici({
          'p_kurulum': _kurulumId,
          'p_adim': o['a'],
          'p_detay': o['d'],
          'p_platform': _platform(),
          'p_surum': await _surumEtiketi(),
          'p_ts': DateTime.fromMillisecondsSinceEpoch(o['t'] as int, isUtc: true)
              .toIso8601String(),
        });
      } catch (e, st) {
        // Ağ hatası beklenen durum (kayıt ekranı çoğu zaman zayıf
        // bağlantıda). Başka bir hata — ör. migration henüz dağıtılmadı
        // (PGRST202) — süreç başına BİR kez bildirilir; her açılışta
        // Crashlytics'i doldurmasın.
        if (!baglantiHatasiMi(e) && !_hataBildirildi) {
          _hataBildirildi = true;
          CrashReporter.report(e, st, reason: 'HuniKaydi.gonder');
        }
        return;
      }
      final kalan = _bekleyenler(prefs)..removeWhere((x) => _anahtar(x) == _anahtar(o));
      final gonderilen = prefs.getStringList(gonderilenAnahtari) ?? const [];
      await prefs.setStringList(gonderilenAnahtari, [...gonderilen, _anahtar(o)]);
      await prefs.setString(bekleyenAnahtari, jsonEncode(kalan));
    }
  }

  Future<void> _kuyrugaKoy(SharedPreferences prefs, HuniAdimi adim, String detay) async {
    final o = {'a': adim.kod, 'd': detay, 't': saat().toUtc().millisecondsSinceEpoch};
    final anahtar = _anahtar(o);
    final gonderilen = prefs.getStringList(gonderilenAnahtari) ?? const [];
    if (gonderilen.contains(anahtar)) return;
    final bekleyen = _bekleyenler(prefs);
    if (bekleyen.any((x) => _anahtar(x) == anahtar)) return;
    if (bekleyen.length >= _kuyrukTavani) return;
    await prefs.setString(bekleyenAnahtari, jsonEncode([...bekleyen, o]));
  }

  static String _anahtar(Map<String, dynamic> o) {
    final d = o['d'] as String? ?? '';
    return d.isEmpty ? o['a'] as String : '${o['a']}|$d';
  }

  List<Map<String, dynamic>> _bekleyenler(SharedPreferences prefs) {
    final ham = prefs.getString(bekleyenAnahtari);
    if (ham == null || ham.isEmpty) return [];
    try {
      return (jsonDecode(ham) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      // Bozuk kuyruk huniyi durdurmasın: at, baştan başla.
      return [];
    }
  }

  static String _platform() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        _ => 'diger',
      };

  Future<String?> _surumEtiketi() async {
    if (_surum != null) return _surum;
    try {
      final b = await PackageInfo.fromPlatform();
      return _surum = '${b.version}+${b.buildNumber}';
    } catch (_) {
      return null; // Sürümsüz satır geçerli; uydurma sürüm yazılmaz.
    }
  }

  static Future<void> _rpc(Map<String, dynamic> params) =>
      Supabase.instance.client
          .rpc<void>('huni_kaydet', params: params)
          .timeout(const Duration(seconds: 10));

  @visibleForTesting
  void sifirlaTestIcin() {
    _hazir = null;
    _akan = null;
    _aktif = false;
    _kurulumId = null;
    _surum = 'test+1';
    _hataBildirildi = false;
    gonderici = _rpc;
    saat = DateTime.now;
  }

  @visibleForTesting
  String? get kurulumId => _kurulumId;
}
