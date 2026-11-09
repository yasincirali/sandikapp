import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../demo/demo_modu.dart';
import '../models/kayitli_cihaz.dart';
import '../models/user_model.dart';
import '../utils/friendly_error.dart';
import 'auth_service.dart';
import 'crash_reporter.dart';
import 'push_message_router.dart' show cihazKimligiUret;
import 'remote_push_service.dart';
import 'secure_session_storage.dart' show KeychainKasasi, SessionVault;
import 'supabase_service.dart';

/// Giriş sonrası cihaz kapısının kararı.
enum CihazKapisi {
  /// İçeri. Tek cihaz kuralı işliyor (ya da hesap muaf).
  serbest,

  /// Kayıtlı olmayan cihaz — e-posta kodu istenmeli.
  otpGerekli,

  /// Hesap başka cihazda açıldı; bu cihaz oturumu kapatmalı.
  atildi,

  /// Karar verilemedi (ağ) ve bu cihaz daha önce hiç onaylanmamış.
  hata,
}

/// Tek aktif cihaz + kayıtlı cihazlar (migration 0098).
///
/// ## Neden (kullanıcı kararı, 2026-10-03)
/// "Aynı hesap aynı anda 2 cihazda açılamamalı, kayıtlı cihaz listesi
/// olmalı, onu da mail OTP ile kontrol ettirmeliyiz."
///
/// ## Akış
/// 1. Girişten sonra [degerlendir]: sunucu cihazı tanıyor mu?
///    - kayıtlı / ilk cihaz → [_oturumuAl] → serbest
///    - yeni → e-posta kodu ([kodGonder] / [kodDogrula]) → kayıt → serbest
/// 2. [_oturumuAl]: `oturum_al` bu cihazı hesabın TEK aktif cihazı yapar,
///    ardından diğer oturumların refresh token'ları iptal edilir.
/// 3. [izle]: `aktif_cihaz` satırı Realtime'dan dinlenir; başka cihaz
///    oturumu alınca bu cihaz kendini kapatır. Realtime koparsa öne dönüşte
///    [hâlâAktifMi] aynı kontrolü yapar.
///
/// Kurallar SUNUCUDADIR (kodsuz kayıt reddi, yerinden edilen cihazın geri
/// kapamaması); buradaki istemci yalnızca yönlendirir.
class CihazOturumuService {
  static final CihazOturumuService instance = CihazOturumuService._();
  CihazOturumuService._();

  RealtimeChannel? _kanal;
  String? _izlenenKullanici;

  /// Hesap başına kalıcı cihaz kimliği.
  ///
  /// `push_device_id`'den AYRI: o çıkışta silinir (2026-09 L14) ve her
  /// girişte yeni kimlik doğardı — kayıtlı cihaz her girişte yeniden kod
  /// isterdi. Bu kimlik çıkışta KALIR; anahtar kullanıcıya özeldir, böylece
  /// aynı telefondaki iki hesap sunucuda aynı kimlikle eşleştirilemez.
  ///
  /// **Uygulama silinse de kalır (yasin kararı 2026-11-05):** "OTP alınmış
  /// cihazdan uygulama silinse de kod istememeli, ama eşleşmiş cihazdan
  /// kaldırılan cihaz için tekrardan OTP istemeli; liste distinct olmalı."
  /// Eskiden kimlik yalnız SharedPreferences'taydı ve "uygulama silinince
  /// kaybolur → yeniden kod" bilinçli sayılmıştı. Ama oturum Keychain'de
  /// durduğu için silip kurunca hesap AÇIK geliyor, yalnız telefon "yeni
  /// cihaz" sayılıp kod istiyordu; kayıtlı listede aynı iPhone dört kez
  /// birikti. Artık Apple platformlarında kimlik oturumla aynı kasada
  /// ([KeychainKasasi], `first_unlock`) — silip kurmaya dayanır. "Kaldır"
  /// kuralı sunucuda değişmez: satır silinince aynı kimlik `yeni` döner ve
  /// kod istenir.
  ///
  /// Sıra: kasa → SharedPreferences (eski kurulumun kimliği kasaya taşınır,
  /// kimse yeniden kod görmez) → yeni rastgele kimlik. Kasa okunamazsa
  /// (iOS ilk kilit açılışından önce arka plan başlatması) ve elde yerel
  /// kimlik de yoksa YENİ kimlik üretilmez: hata atılır, kapı "karar
  /// verilemedi" yoluna düşer. Yoksa okunamayan kasanın yerine yeni kimlik
  /// yazılır ve telefon bir kez daha çoğalırdı.
  ///
  /// Android'de kasa (Keystore) uygulamayla silinir; orada silip kurunca
  /// kod yine istenir (açık iş, YAPMAN_GEREKENLER değil TECHNICAL_DEBT).
  Future<String> cihazKimligi(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final anahtar = 'cihaz_kimligi_v1_$userId';
    final yerel = prefs.getString(anahtar);
    final yerelGecerli = cihazKimligiGecerli(yerel);
    if (!_appleKasasi) {
      if (yerelGecerli) return yerel!;
      final yeni = _rastgeleKimlik();
      await prefs.setString(anahtar, yeni);
      return yeni;
    }
    String? kasadaki;
    try {
      kasadaki = await _kasa.read(anahtar);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'CihazOturumuService.kasaOku');
      if (yerelGecerli) return yerel!;
      throw StateError('cihaz kimliği okunamadı (kasa kilitli)');
    }
    if (cihazKimligiGecerli(kasadaki)) {
      if (yerel != kasadaki) await prefs.setString(anahtar, kasadaki!);
      return kasadaki!;
    }
    final kimlik = yerelGecerli ? yerel! : _rastgeleKimlik();
    if (!yerelGecerli) await prefs.setString(anahtar, kimlik);
    try {
      await _kasa.write(anahtar, kimlik);
    } catch (e, st) {
      // Kasaya yazılamazsa bu kurulumda yerel kopya yeter; bir sonraki
      // çağrı yeniden dener.
      CrashReporter.report(e, st, reason: 'CihazOturumuService.kasaYaz');
    }
    return kimlik;
  }

  static bool cihazKimligiGecerli(String? v) =>
      v != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(v);

  String _rastgeleKimlik() {
    final r = Random.secure();
    return cihazKimligiUret(() => r.nextInt(256));
  }

  SessionVault? _kasaYerine;
  bool? _appleYerine;

  /// Test kancası: kasa ve platform (Apple mı) yerine geçenler.
  @visibleForTesting
  void testKasasi(SessionVault? kasa, {bool? apple}) {
    _kasaYerine = kasa;
    _appleYerine = apple;
  }

  SessionVault get _kasa => _kasaYerine ??= KeychainKasasi();
  bool get _appleKasasi =>
      _appleYerine ?? (!kIsWeb && (Platform.isIOS || Platform.isMacOS));

  /// Bu cihaz bu hesap için bir kez sunucuca onaylandı mı — ağ yokken
  /// kapının içeri alıp almayacağını bu belirler (yerel bilgi, kanıt değil;
  /// sunucu kuralları ağ gelince yine işler).
  Future<bool> _yereldeOnayli(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('cihaz_onayli_v1_$userId') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _yereldeOnayla(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cihaz_onayli_v1_$userId', true);
    } catch (_) {}
  }

  String get _platform => Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
          ? 'android'
          : 'unknown';

  /// Listede görünecek ad: "Google Pixel 7", "iPhone · iOS 18.1".
  /// Okunamazsa platform adı — ad yalnızca kullanıcının tanıması için.
  Future<String> cihazAdi() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final uretici = a.manufacturer.trim();
        final model = a.model.trim();
        final ad = model.toLowerCase().startsWith(uretici.toLowerCase())
            ? model
            : '${_buyukHarf(uretici)} $model';
        return ad.trim().isEmpty ? 'Android' : ad.trim();
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        final model = i.model.trim().isEmpty ? 'iPhone' : i.model.trim();
        return '$model · iOS ${i.systemVersion}';
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'CihazOturumuService.cihazAdi');
    }
    return Platform.isIOS ? 'iPhone' : 'Android';
  }

  static String _buyukHarf(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Sunucu hatasından kural adını çıkarır (`otp_gerekli`, `yerinden_edildi`…).
  static String? kuralHatasi(Object e) {
    if (e is! PostgrestException) return null;
    for (final k in const [
      'otp_gerekli',
      'yerinden_edildi',
      'aktif_cihaz_silinemez',
      'cihaz_siniri',
    ]) {
      if (e.message.contains(k)) return k;
    }
    return null;
  }

  /// Migration henüz bu sunucuda yoksa (istemci önce yayına çıkarsa)
  /// kapı içeri alır: kimseyi dışarıda bırakmamak, kuralı bir sürüm
  /// geciktirmekten iyidir. Crashlytics'te görünür.
  static bool _fonksiyonYok(Object e) =>
      e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');

  /// Girişten sonra kapının kararı.
  Future<CihazKapisi> degerlendir(AppUser user) async {
    if (DemoModu.aktif) return CihazKapisi.serbest;
    try {
      // Kimlik okunamazsa (kasa kilitli) aşağıdaki "karar verilemedi"
      // yoluna düşer: yerelde onaylıysa içeri, değilse yeniden dene.
      final cihazId = await cihazKimligi(user.id);
      final durum = await SupabaseService.instance.cihazDurumu(cihazId);
      if (durum == null) throw StateError('cihaz_durumu: beklenmeyen yanıt');
      switch (durum) {
        case CihazDurumu.muaf:
          return CihazKapisi.serbest;
        case CihazDurumu.kayitli:
        case CihazDurumu.ilk:
          // Kayıtlıda ad/son görülme tazelenir; ilkte cihaz kodsuz yazılır.
          await _kaydet(cihazId);
          await _oturumuAl(user.id, cihazId);
          return CihazKapisi.serbest;
        case CihazDurumu.yeni:
          // Az önce kayıt ya da şifre sıfırlama koduyla girdiyse e-posta
          // sahipliği zaten kanıtlı: sunucu kaydı kabul eder, ikinci kod
          // sorulmaz. Kanıt yoksa `otp_gerekli` döner.
          try {
            await _kaydet(cihazId);
          } on PostgrestException catch (e) {
            if (kuralHatasi(e) == 'otp_gerekli') {
              return user.email.trim().isEmpty
                  ? _epostasizHesap(user)
                  : CihazKapisi.otpGerekli;
            }
            rethrow;
          }
          await _oturumuAl(user.id, cihazId);
          return CihazKapisi.serbest;
      }
    } catch (e, st) {
      if (kuralHatasi(e) == 'yerinden_edildi') return CihazKapisi.atildi;
      if (_fonksiyonYok(e)) {
        CrashReporter.report(e, st,
            reason: 'CihazOturumuService: 0098 bu sunucuda yok');
        return CihazKapisi.serbest;
      }
      if (await _yereldeOnayli(user.id)) return CihazKapisi.serbest;
      if (!baglantiHatasiMi(e)) {
        CrashReporter.report(e, st, reason: 'CihazOturumuService.degerlendir');
      }
      return CihazKapisi.hata;
    }
  }

  /// E-postası olmayan hesap kod alamaz. Kapıda kilitli kalmasın; ölçülsün.
  CihazKapisi _epostasizHesap(AppUser user) {
    CrashReporter.report(StateError('cihaz kapısı: e-postasız hesap'),
        StackTrace.current, reason: 'CihazOturumuService.epostasiz');
    return CihazKapisi.serbest;
  }

  Future<void> kodGonder(AppUser user) =>
      AuthService.instance.cihazKoduGonder(user.email);

  /// Kodu doğrular, cihazı kaydeder ve oturumu alır.
  Future<void> kodDogrula(AppUser user, String kod) async {
    await AuthService.instance.cihazKoduDogrula(email: user.email, kod: kod);
    final cihazId = await cihazKimligi(user.id);
    await _kaydet(cihazId);
    await _oturumuAl(user.id, cihazId);
  }

  Future<void> _kaydet(String cihazId) async {
    await SupabaseService.instance.cihazKaydet(
      cihazId: cihazId,
      ad: await cihazAdi(),
      platform: _platform,
    );
  }

  Future<void> _oturumuAl(String userId, String cihazId) async {
    await SupabaseService.instance.oturumAl(
      cihazId: cihazId,
      pushCihazId: await RemotePushService.instance.mevcutCihazKimligi(),
      pushToken: RemotePushService.instance.mevcutToken,
    );
    await _yereldeOnayla(userId);
    // Sıra önemli: önce aktif satır bu cihaza geçer (eski cihaz Realtime'dan
    // duyar), sonra refresh token'ları iptal edilir.
    CrashReporter.arkaPlan(AuthService.instance.digerOturumlariKapat(),
        reason: 'CihazOturumuService.digerOturumlariKapat');
  }

  /// Hesap hâlâ bu cihazda mı? Ağ hatasında `true` — ağ yokluğu atma
  /// sebebi değildir; kural ağ gelince işler.
  Future<bool> halaAktifMi(String userId) async {
    try {
      final cihazId = await cihazKimligi(userId);
      final aktif = await SupabaseService.instance.aktifCihazId(userId);
      return aktif == null || aktif == cihazId;
    } catch (_) {
      return true;
    }
  }

  /// `aktif_cihaz` satırını dinler; başka cihaz oturumu alınca [atildi].
  Future<void> izle(String userId, void Function() atildi) async {
    if (DemoModu.aktif) return;
    if (_izlenenKullanici == userId && _kanal != null) return;
    await birak();
    _izlenenKullanici = userId;
    final cihazId = await cihazKimligi(userId);
    final client = Supabase.instance.client;
    _kanal = client.channel('aktif-cihaz-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'aktif_cihaz',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final yeni = payload.newRecord['cihaz_id'];
          if (yeni is String && yeni.isNotEmpty && yeni != cihazId) atildi();
        },
      )
      ..subscribe();
  }

  Future<void> birak() async {
    final kanal = _kanal;
    _kanal = null;
    _izlenenKullanici = null;
    if (kanal != null) {
      try {
        await Supabase.instance.client.removeChannel(kanal);
      } catch (_) {}
    }
  }

  Future<List<KayitliCihaz>> liste(String userId) =>
      SupabaseService.instance.kayitliCihazlar(userId);

  Future<void> sil(String cihazId) async {
    await SupabaseService.instance.cihazSil(cihazId);
  }
}
