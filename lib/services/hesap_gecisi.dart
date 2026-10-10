import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_model.dart';
import 'auth_service.dart' hide AuthException;
import 'cihaz_oturumu_service.dart';
import 'crash_reporter.dart';
import 'daily_summary.dart' show IntradaySeriesCache;
import 'disclaimer_service.dart';
import 'hesap_kasasi.dart';
import 'home_widget_service.dart';
import 'live_activity_service.dart';
import 'portfolio_cache.dart';
import 'remote_config_service.dart';
import 'remote_push_service.dart';
import 'supabase_service.dart';

/// Aktif hesap kasaya alındıktan sonra bir hesaba daha yer var mı. Saf.
bool eklenebilir(List<KayitliHesap> liste, String aktifUid) {
  final kayitli = liste.any((h) => h.uid == aktifUid);
  final sayi = liste.length + (kayitli ? 0 : 1);
  return sayi < HesapKasasi.enCok;
}

/// Geçiş sırasında üstte duran perdenin içeriği.
class HesapGecisPerdesi {
  final String basHarf;
  final String ad;
  final String alt;
  const HesapGecisPerdesi(
      {required this.basHarf, required this.ad, required this.alt});
}

/// Geçilmek istenen hesabın saklı oturumu sunucuda geçersiz.
class HesapOturumuDustu implements Exception {
  final KayitliHesap hesap;
  const HesapOturumuDustu(this.hesap);
}

/// Sınır dolu (Instagram gibi 5).
class HesapSiniriDolu implements Exception {
  const HesapSiniriDolu();
}

/// Çoklu hesap ve hesaplar arası geçiş (bayrak `coklu_hesap`, 2026-10-10).
///
/// ## Neden geçişte bütün sağlayıcı kapsamı yeniden kurulur
/// Kullanıcı sorusu (2026-10-09): "her müşterinin cihazdaki verileri
/// birbirine karışacak mı?" 28 sağlayıcının yalnız 13'ü `authProvider`'ı
/// izliyor; kalanların hangisinin hesaba ait veri tuttuğunu tek tek
/// izlemek, bir sonraki yeni sağlayıcıda unutulacak bir kuraldır. Bunun
/// yerine her geçiş [nesil]'i artırır ve `UygulamaKabugu` kök
/// `ProviderScope`'u o anahtarla BAŞTAN kurar — önceki hesabın hiçbir
/// sağlayıcı durumu yeni hesaba ulaşamaz (`hesap_gecisi_test` kilitler).
/// Süreç boyu yaşayan tekil servislerin hesaba bağlı önbellekleri ve
/// cihaz geneli yüzeyler (widget, Live Activity) [_ayril]'da ayrıca silinir.
///
/// ## Oturumlar
/// Supabase istemcisi aynı anda TEK oturum tutar; bu değişmedi. Diğer
/// hesapların oturumu [HesapKasasi]'nda (Keychain/Keystore) bekler. Geçiş:
/// (1) aktif oturum kasaya, (2) hedefin yenileme anahtarıyla `setSession` —
/// ağa gider, böylece sunucuda iptal edilmiş (başka telefonda açılmış)
/// oturum ilk adımda yakalanır ve kullanıcı yarım bir hesaba düşmez.
/// Başarısızsa önceki oturum geri yüklenir.
///
/// ## Kapalıyken
/// Bayrak kapalı ya da kasa boşken hiçbir şey yazılmaz; giriş/çıkış birebir
/// eski yoldan yürür.
class HesapGecisi {
  HesapGecisi._();
  static final HesapGecisi instance = HesapGecisi._();

  HesapKasasi get _kasa => HesapKasasi.instance;
  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Kök `ProviderScope`'un anahtarı — artınca kapsam baştan kurulur.
  final ValueNotifier<int> nesil = ValueNotifier(0);

  /// Doluyken uygulamanın üstünde geçiş perdesi durur.
  final ValueNotifier<HesapGecisPerdesi?> perde = ValueNotifier(null);

  /// "Hesap ekle" sırasında kenara alınan hesap — giriş ekranındaki
  /// "Vazgeç" buna döner. Süreç ölürse kaybolur; giriş ekranı yine kasadaki
  /// hesapları listeler, kullanıcı oradan döner.
  final ValueNotifier<KayitliHesap?> eklemedenDonulecek = ValueNotifier(null);

  /// Kasadaki hesaplar — seçici ve giriş ekranı izler.
  final ValueNotifier<List<KayitliHesap>> hesaplar = ValueNotifier(const []);

  /// "Oturumu düşmüş" hesaba tekrar girerken giriş ekranına önerilen
  /// e-posta (bir kez okunur).
  String? onerilenEposta;

  /// Geçişten sonra işlenecek bildirim (pasif hesabın bildirimine dokunuldu).
  Map<String, dynamic>? bekleyenBildirim;

  StreamSubscription<AuthState>? _abonelik;
  bool _mesgul = false;

  bool get acik => RemoteConfigService.instance.cokluHesap;

  /// Açılışta bir kez (Supabase hazır olduktan sonra). Yenileme anahtarı
  /// her yenilemede döner (rotation açık): kasadaki kopyası tazelenmezse
  /// bir sonraki geçişte "oturum düştü" görünürdü.
  Future<void> baslat() async {
    _abonelik ??= _auth.onAuthStateChange.listen((d) {
      final s = d.session;
      if (s == null || _mesgul) return;
      if (d.event == AuthChangeEvent.tokenRefreshed ||
          d.event == AuthChangeEvent.signedIn ||
          d.event == AuthChangeEvent.userUpdated) {
        CrashReporter.arkaPlan(
            _kasa.oturumuTazele(s.user.id, jsonEncode(s.toJson())),
            reason: 'HesapGecisi.oturumuTazele');
      }
    }, onError: (Object _) {});
    await listeyiTazele();
  }

  Future<void> listeyiTazele() async {
    hesaplar.value = await _kasa.liste();
  }

  static KayitliHesap _meta(AppUser u) => KayitliHesap(
        uid: u.id,
        eposta: u.email,
        ad: (u.username?.isNotEmpty ?? false) ? u.username! : u.displayName,
        sonKullanim: DateTime.now(),
      );

  /// `_AuthGate` her yeni oturum kullanıcısında çağırır.
  ///
  /// Hesap kasada yalnız iki durumda tutulur: kasada zaten varsa (bilgisi
  /// ve oturumu tazelenir) ya da bir "hesap ekle" akışı bekliyorsa (yeni
  /// hesap eklenir). Tek hesaplı kullanıcının oturumu ikinci bir anahtara
  /// boşuna kopyalanmaz.
  Future<void> aktifHesapGirdi(AppUser u) async {
    if (!acik) return;
    final s = _auth.currentSession;
    if (s == null || s.user.id != u.id) return;
    final liste = await _kasa.liste();
    final kayitli = liste.any((h) => h.uid == u.id);
    final ekleniyor = eklemedenDonulecek.value != null;
    if (!kayitli && !ekleniyor && liste.isEmpty) return;
    if (!kayitli && liste.length >= HesapKasasi.enCok) {
      // Sınır dolu: hesap yine açılır, yalnız kasaya girmez.
      eklemedenDonulecek.value = null;
      return;
    }
    await _kasa.kaydet(_meta(u), oturumJson: jsonEncode(s.toJson()));
    eklemedenDonulecek.value = null;
    // Bu hesap artık bu cihazın AKTİF hesabı: pasif push bağı varsa çözülür
    // (birincil satırı `claim_push_token` yazar).
    await _pushCoz();
    await listeyiTazele();
  }

  // ── Geçiş ────────────────────────────────────────────────────────────────

  /// [hedefUid] hesabına geçer. [aktif] şu anki kullanıcı (yoksa oturumsuz
  /// hâlden geçiş: "Vazgeç" ya da çıkış sonrası sıradaki hesap).
  Future<void> gec(String hedefUid, {AppUser? aktif}) async {
    if (_mesgul) return;
    final liste = await _kasa.liste();
    final hedef = liste.where((h) => h.uid == hedefUid).firstOrNull;
    if (hedef == null) return;
    if (aktif?.id == hedefUid) return;
    _mesgul = true;
    perde.value = HesapGecisPerdesi(
        basHarf: hedef.basHarf, ad: hedef.ad, alt: 'hesabına geçiliyor');
    String? oncekiJson;
    try {
      if (aktif != null) oncekiJson = await _ayril(aktif);
      final yenileme = _yenilemeAnahtari(await _kasa.oturum(hedefUid));
      if (yenileme == null) throw HesapOturumuDustu(hedef);
      final AuthResponse r;
      try {
        r = await _auth.setSession(yenileme);
      } on AuthException catch (e) {
        if (_agHatasi(e)) rethrow;
        throw HesapOturumuDustu(hedef);
      }
      final s = r.session;
      // Aynı anda süren otomatik yenileme `setSession`'a ESKİ hesabın
      // yanıtını döndürebilir (gotrue tek yenileme kuyruğu) — oturum
      // düşmüş sayılmaz, yalnız bu deneme olmaz.
      if (s == null || s.user.id != hedefUid) {
        throw StateError('hesap gecisi: beklenmeyen oturum');
      }
      await _kasa.kaydet(
        hedef.kopya(sonKullanim: DateTime.now(), oturumDustu: false),
        oturumJson: jsonEncode(s.toJson()),
      );
      eklemedenDonulecek.value = null;
      // Oturum değişti; yeni kapsam kurulmadan önce cihaz yüzeyleri
      // silinir — kilit ekranında önceki hesabın tutarı bir kare bile
      // kalmasın. Yeni hesabın verisi geldikçe yeniden yazılır.
      await _cihazYuzeyleriniTemizle();
      await _pushCoz();
      await listeyiTazele();
      _yenidenKur();
    } catch (e) {
      if (e is HesapOturumuDustu) {
        await _kasa.isaretle(hedefUid, oturumDustu: true);
        await listeyiTazele();
      }
      // Önceki hesap yerinde kalır. Geçersiz yenileme anahtarında gotrue
      // yerel oturumu siler (sunucuya gitmeden); o durumda ağsız geri
      // yüklenir. Sağlayıcılar hiç değişmediği için yeniden kurulum yok.
      if (oncekiJson != null && _auth.currentUser?.id != aktif?.id) {
        try {
          await _auth.recoverSession(oncekiJson);
        } catch (e2, st) {
          CrashReporter.report(e2, st, reason: 'HesapGecisi.geriYukle');
        }
      }
      perde.value = null;
      rethrow;
    } finally {
      _mesgul = false;
    }
  }

  /// Yeni hesap ekleme akışını başlatır: aktif hesap kasaya alınır, istemci
  /// oturumsuz kalır (sunucudaki oturum İPTAL EDİLMEDEN) ve giriş ekranı
  /// açılır. Giriş/kayıt/Apple/Google, cihaz kodu, yasal onay ve kullanıcı
  /// adı kapıları bugünkü yollarından aynen geçer; yeni hesap
  /// [aktifHesapGirdi] ile kasaya girer.
  Future<void> eklemeyiBaslat(AppUser aktif) async {
    if (_mesgul) return;
    if (!eklenebilir(await _kasa.liste(), aktif.id)) {
      throw const HesapSiniriDolu();
    }
    _mesgul = true;
    perde.value = const HesapGecisPerdesi(
        basHarf: '+', ad: 'Hesap ekle', alt: 'giriş ekranı açılıyor');
    try {
      await _ayril(aktif);
      eklemedenDonulecek.value = _meta(aktif);
      await _cihazYuzeyleriniTemizle();
      await _yereldeBirak();
      await listeyiTazele();
      _yenidenKur();
    } catch (e, st) {
      perde.value = null;
      CrashReporter.report(e, st, reason: 'HesapGecisi.eklemeyiBaslat');
      rethrow;
    } finally {
      _mesgul = false;
    }
  }

  /// Bu hesaptan çık ([AuthNotifier.logout] sunucu iptali + temizliği
  /// yaptıktan sonra çağrılır): sıradaki hesap varsa ona geçilir.
  Future<bool> cikistanSonraSiradakine(String cikanUid) async {
    await _kasa.sil(cikanUid);
    await listeyiTazele();
    final sonraki = siradakiHesap(await _kasa.liste(), cikanUid);
    if (sonraki == null) return false;
    try {
      await gec(sonraki.uid);
      return true;
    } catch (_) {
      // Oturumu düşmüşse giriş ekranı listeyle açılır (uyarıyla).
      return false;
    }
  }

  /// "Tüm hesaplardan çık": aktif dışındaki her hesabın oturumu sunucuda
  /// da iptal edilir, pasif push bağı çözülür, kasa boşalır. Aktif hesabın
  /// çıkışını çağıran ([AuthNotifier.logout]) ayrıca yapar.
  Future<void> digerlerindenCik(String aktifUid) async {
    final aktifJson = _auth.currentSession == null
        ? null
        : jsonEncode(_auth.currentSession!.toJson());
    _mesgul = true;
    try {
      for (final h in await _kasa.liste()) {
        if (h.uid == aktifUid || h.oturumDustu) continue;
        final y = _yenilemeAnahtari(await _kasa.oturum(h.uid));
        if (y == null) continue;
        try {
          await _auth.setSession(y);
          await _pushCoz();
          await AuthService.instance.logout();
        } catch (e, st) {
          // Oturumu zaten düşmüş ya da ağ yok: cihazdan silinmesi yeter;
          // sunucudaki yenileme anahtarı süresi dolunca kendiliğinden ölür.
          if (e is! AuthException) {
            CrashReporter.report(e, st, reason: 'HesapGecisi.digerlerindenCik');
          }
        }
      }
      await _kasa.hepsiniSil();
      if (aktifJson != null) {
        try {
          await _auth.recoverSession(aktifJson);
        } catch (_) {}
      }
    } finally {
      _mesgul = false;
    }
    eklemedenDonulecek.value = null;
    await listeyiTazele();
  }

  /// Listeden kaldır: oturum sunucuda da iptal edilir (cihazda saklı
  /// yenileme anahtarı başka biri tarafından kullanılamasın), pasif push
  /// bağı çözülür. Aktif hesap kaldırılamaz (onun yolu "çıkış").
  Future<void> kaldir(String uid, {AppUser? aktif}) async {
    if (aktif?.id == uid) return;
    final aktifJson = _auth.currentSession == null
        ? null
        : jsonEncode(_auth.currentSession!.toJson());
    final y = _yenilemeAnahtari(await _kasa.oturum(uid));
    if (y != null) {
      _mesgul = true;
      try {
        await _auth.setSession(y);
        await _pushCoz();
        await _auth.signOut();
      } catch (_) {
        // Düşmüş oturum: yerelden silmek yeter.
      } finally {
        if (aktifJson != null) {
          try {
            await _auth.recoverSession(aktifJson);
          } catch (e, st) {
            CrashReporter.report(e, st, reason: 'HesapGecisi.kaldir.geriYukle');
          }
        }
        _mesgul = false;
      }
    }
    // Çevrimdışı defter de o hesabın: cihazda kalmasın (çıkıştaki kuralla aynı).
    await PortfolioCache.clear(uid);
    await _kasa.sil(uid);
    await listeyiTazele();
  }

  /// Bildirim başka (pasif) bir hesaba aitse önce o hesaba geçilir; bildirim
  /// geçişten sonra işlenir. `true` = geçiş başladı, çağıran bildirimi
  /// şimdi işlemesin.
  Future<bool> bildirimHesabinaGec(
      Map<String, dynamic> data, String? aktifUid) async {
    if (!acik) return false;
    final hedef = data['hesap_uid']?.toString();
    final aktifId = aktifUid ?? _auth.currentUser?.id;
    if (hedef == null || hedef.isEmpty || hedef == aktifId) return false;
    final liste = await _kasa.liste();
    if (!liste.any((h) => h.uid == hedef && !h.oturumDustu)) return false;
    bekleyenBildirim = data;
    try {
      await gec(hedef, aktif: await _aktifKullanici());
      return true;
    } catch (_) {
      bekleyenBildirim = null;
      return false;
    }
  }

  Future<AppUser?> _aktifKullanici() async {
    final u = _auth.currentUser;
    if (u == null) return null;
    return AppUser.fromSession(
      id: u.id,
      email: u.email,
      displayName: u.userMetadata?['display_name'] as String?,
      createdAt: u.createdAt,
    );
  }

  // ── İç adımlar ───────────────────────────────────────────────────────────

  /// Aktif hesaptan AYRILIŞ — sunucu oturumu iptal edilmez (geri dönülecek).
  /// Dönen: ayrılan oturumun JSON'u (geri yükleme için).
  ///
  /// Push bağı hâlâ O hesabın oturumuyla yazılmalı (RPC `auth.uid()`
  /// okur), bu yüzden oturum değişmeden önce.
  Future<String?> _ayril(AppUser aktif) async {
    final s = _auth.currentSession;
    if (s == null || s.user.id != aktif.id) return null;
    final json = jsonEncode(s.toJson());
    final mevcut = (await _kasa.liste())
        .where((h) => h.uid == aktif.id)
        .firstOrNull;
    final ad = _meta(aktif).ad;
    final ok = await _kasa.kaydet(
      (mevcut ?? _meta(aktif)).kopya(
        ad: ad.isNotEmpty ? ad : null,
        eposta: aktif.email,
        sonKullanim: DateTime.now(),
        oturumDustu: false,
      ),
      oturumJson: json,
    );
    if (!ok) throw const HesapSiniriDolu();
    await _pushBagla(aktif.id);
    return json;
  }

  Future<void> _cihazYuzeyleriniTemizle() async {
    // Her adım ayrı: biri düşerse ötekiler yine çalışsın.
    for (final adim in <(String, Future<void> Function())>[
      ('widget', HomeWidgetService.instance.clear),
      ('liveActivity', LiveActivityService.instance.endAll),
      ('cihazIzleme', CihazOturumuService.instance.birak),
    ]) {
      try {
        await adim.$2();
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'HesapGecisi.temizle.${adim.$1}');
      }
    }
    IntradaySeriesCache.instance.clear();
    DisclaimerService.instance.clearCache();
  }

  /// Faz 2: ayrılan hesap bu cihazda PASİF kalır, bildirimleri hesap adıyla
  /// gelir (0137). Token yoksa (izin verilmemiş) ya da sunucu henüz 0137'yi
  /// almadıysa sessizce atlanır — geçişi asla durdurmaz.
  Future<void> _pushBagla(String uid) async {
    final token = RemotePushService.instance.mevcutToken;
    if (token == null || token.isEmpty) return;
    try {
      await SupabaseService.instance.ekHesapPushBagla(
        token: token,
        platform: _platform,
        cihazId: await CihazOturumuService.instance.cihazKimligi(uid),
        deviceId: await RemotePushService.instance.mevcutCihazKimligi(),
        bildirimSurumu: bildirimSurumu,
      );
    } catch (e, st) {
      if (!_eskiSunucu(e)) {
        CrashReporter.report(e, st, reason: 'HesapGecisi.pushBagla');
      }
    }
  }

  /// Bu hesabın YALNIZ bu cihaz token'ındaki pasif bağı çözülür; başka
  /// telefonlardaki bağlar o telefonların işidir.
  Future<void> _pushCoz() async {
    final token = RemotePushService.instance.mevcutToken;
    if (token == null || token.isEmpty) return;
    try {
      await SupabaseService.instance.ekHesapPushCoz(token);
    } catch (e, st) {
      if (!_eskiSunucu(e)) {
        CrashReporter.report(e, st, reason: 'HesapGecisi.pushCoz');
      }
    }
  }

  static bool _eskiSunucu(Object e) =>
      e is PostgrestException && (e.code == 'PGRST202' || e.code == '42883');

  String get _platform {
    if (kIsWeb) return 'unknown';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// İstemciyi oturumsuz bırakır AMA sunucudaki oturumu iptal ETMEZ.
  ///
  /// gotrue'da yalnız-yerel çıkış yok: `signOut()` önce yerel oturumu
  /// siler, sonra elindeki erişim anahtarıyla `/logout` çağırır ve o
  /// oturumun yenileme anahtarını sunucuda öldürür — kasaya aldığımız
  /// oturum geri dönülemez olurdu. Bu yüzden önce ağsız `recoverSession`
  /// ile imzasız, sahte bir oturum yerleştirilir; `signOut` onu siler ve
  /// sunucuya geçersiz anahtarı yollar (401/403 → gotrue yutar, ağ hatası
  /// burada yutulur). Gerçek oturuma hiçbir istek gitmez.
  Future<void> _yereldeBirak() async {
    final simdi = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String b64(Map<String, Object?> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final sahte = '${b64({'alg': 'none', 'typ': 'JWT'})}.'
        '${b64({'sub': _bosKimlik, 'exp': simdi + 3600, 'role': 'anon'})}.x';
    await _auth.recoverSession(jsonEncode({
      'access_token': sahte,
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': _bosKimlik,
        'aud': 'authenticated',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
      },
    }));
    try {
      await _auth.signOut();
    } catch (_) {
      // Yerel oturum `signOut`'un İLK adımında silindi; sunucunun sahte
      // anahtara verdiği yanıt (ya da ağ hatası) önemsiz.
    }
  }

  static const _bosKimlik = '00000000-0000-0000-0000-000000000000';

  void _yenidenKur() {
    nesil.value++;
  }

  /// Perde, yeni kapsam ilk kareyi çizdikten sonra kalkar
  /// (`UygulamaKabugu`). Bekleyen bildirim varsa o an işlenir.
  void perdeyiKaldir() => perde.value = null;

  static String? _yenilemeAnahtari(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is! Map) return null;
      final r = m['refresh_token'];
      return r is String && r.isNotEmpty ? r : null;
    } catch (_) {
      return null;
    }
  }

  static bool _agHatasi(AuthException e) =>
      e is AuthRetryableFetchException ||
      e.statusCode == null ||
      (int.tryParse(e.statusCode ?? '') ?? 0) >= 500;
}
