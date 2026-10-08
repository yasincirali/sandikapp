import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/kullanici_adi.dart';
import '../models/user_model.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/crash_reporter.dart';
import '../services/social_auth_service.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_push_service.dart';
import '../services/supabase_service.dart';
import 'bulk_cart_provider.dart';
import '../utils/friendly_error.dart';

// ── Mevcut oturum kullanıcısı ─────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<AppUser?> {
  /// Son bilinen profil diskteyse açılış ONU bekler, ağı değil
  /// (bkz. `AuthService` "Profil önbelleği"). İlk açılışta / hesap
  /// değişiminde önbellek yoktur ve eski yol (`getSessionUser`) yürür.
  @override
  Future<AppUser?> build() async {
    final onbellek = await AuthService.instance.onbellekliOturumKullanicisi();
    if (onbellek == null) return AuthService.instance.getSessionUser();
    // Çıplak `unawaited` değil: tazeleme kendi içinde ağ hatasını yutar,
    // ama beklenmedik bir hata (ör. sökülmüş notifier'a yazma) çökme
    // yerine non-fatal kayıt olsun (`arka_plan_hata_yutma_test`).
    CrashReporter.arkaPlan(_profiliArkadaTazele(onbellek.id),
        reason: 'AuthNotifier.profiliArkadaTazele');
    return onbellek;
  }

  /// Gerçek profili arkada çeker; state'e YALNIZ değiştiyse yazar.
  ///
  /// Koşulsuz yazmak portföy, sinyal, alarm… `authProvider`'ı izleyen her
  /// provider'ı yeniden kurar ve açılışın yeni kazandığı gidiş-dönüşü geri
  /// verirdi. Ağ yoksa sessiz: önbellekteki profil zaten gerçek bir
  /// profildir (offline minimal profil değil).
  Future<void> _profiliArkadaTazele(String id) async {
    try {
      final taze = await AuthService.instance.refreshProfile();
      final simdiki = state.valueOrNull;
      // Bu arada çıkış / hesap değişimi olduysa bu yanıt bayattır.
      if (simdiki == null || simdiki.id != id) return;
      if (taze == null) {
        // Profil satırı yok (hesap başka cihazdan silinmiş): önbelleksiz
        // yolun davranışı neyse o — kullanıcı yok.
        state = const AsyncData(null);
        return;
      }
      if (!ayniProfil(simdiki, taze)) state = AsyncData(taze);
    } catch (_) {
      // Ağ yok — önbellekteki profille devam.
    }
  }

  @visibleForTesting
  static bool ayniProfil(AppUser a, AppUser b) =>
      a.id == b.id &&
      a.email == b.email &&
      a.displayName == b.displayName &&
      a.onboardingCompleted == b.onboardingCompleted &&
      a.username == b.username &&
      a.eksikProfil == b.eksikProfil &&
      a.createdAt.millisecondsSinceEpoch == b.createdAt.millisecondsSinceEpoch;

  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => AuthService.instance.login(email: email, password: password, rememberMe: rememberMe),
    );
    if (state.hasValue && state.valueOrNull != null) {
      unawaited(AnalyticsService.instance.logLogin(method: 'email'));
    }
  }

  /// Apple / Google ile giriş. Kullanıcı sağlayıcı ekranında vazgeçerse
  /// state'e dokunulmaz — hata da gösterilmez.
  Future<void> loginWithSocial(SocialProvider provider) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      final user = await AuthService.instance.loginWithSocial(provider);
      state = AsyncData(user);
      unawaited(AnalyticsService.instance.logLogin(method: provider.name));
    } on SocialSignInCancelled {
      state = previous;
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => AuthService.instance.register(
        email: email,
        displayName: displayName,
        password: password,
      ),
    );
    if (state.hasValue && state.valueOrNull != null) {
      unawaited(AnalyticsService.instance.logSignup(method: 'email'));
    }
  }

  /// Kullanıcı adını kaydeder; başarılıysa state yeni adla güncellenir
  /// (giriş kapısı kapanır, ortak ve ana ekran yeni adı görür).
  Future<KullaniciAdiSonuc> kullaniciAdiKaydet(String ad) async {
    final mevcut = state.valueOrNull;
    if (mevcut == null) return KullaniciAdiSonuc.bilinmiyor;
    final r = await AuthService.instance.kullaniciAdiAyarla(ad, mevcut);
    final profil = r.profil;
    // Bu arada çıkış / hesap değişimi olduysa yanıt bayattır.
    if (profil != null && state.valueOrNull?.id == profil.id) {
      state = AsyncData(profil);
    }
    return r.sonuc;
  }

  /// Ağ geri geldiğinde minimal (offline) profili gerçeğiyle değiştirir.
  ///
  /// `getSessionUser` ağ yokken token'dan minimal bir kullanıcı kuruyor —
  /// `displayName` boş oluyor. Bağlantı gelince sessizce tazelenir.
  /// Başarısız olursa mevcut state korunur: kullanıcı oturumdan atılmaz.
  Future<void> refreshProfileIfStale() async {
    final current = state.valueOrNull;
    if (current == null ||
        (!current.eksikProfil && current.displayName.isNotEmpty)) {
      return;
    }
    try {
      final fresh = await AuthService.instance.refreshProfile();
      if (fresh != null) state = AsyncData(fresh);
    } catch (_) {
      // Ağ hâlâ yok — mevcut minimal profille devam.
    }
  }

  Future<void> logout() async {
    unawaited(AnalyticsService.instance.logLogout());
    // `finally`: push durdurma ya da çıkış adımlarından biri hata verse de
    // uygulama giriş ekranına dönmeli ve sepet boşalmalı. Eskiden hata
    // yukarı çıkınca durum oturumlu kalıyordu, zaman aşımı çıkışı da
    // (`main.dart`, sonucu beklenmeyen çağrı) bunu çökme olarak
    // raporluyordu (2026-09-23 denetimi F8).
    try {
      await RemotePushService.instance.stop();
      await AuthService.instance.logout();
    } finally {
      DisclaimerService.instance.clearCache();
      ref.read(bulkCartProvider.notifier).clear();
      state = const AsyncData(null);
    }
  }

  /// Hesabı Edge Function üzerinden kalıcı olarak siler.
  /// Başarılıysa state'i null'a çeker → AuthGate LoginScreen'e döner.
  Future<void> deleteAccount({String? password}) async {
    await RemotePushService.instance.stop();
    await AuthService.instance.deleteAccount(password: password);
    DisclaimerService.instance.clearCache();
    ref.read(bulkCartProvider.notifier).clear();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);

// ── Ortaklar ──────────────────────────────────────────────────────────────────

class PartnerAccount {
  final AppUser user;
  final bool isActive;
  PartnerAccount({required this.user, required this.isActive});
}

class PartnersNotifier extends AsyncNotifier<List<PartnerAccount>>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _observing = false;

  /// Ortaklık değişimi nadir bir olaydır; 8 saniye gereksiz sıktı.
  /// 30 saniyede saatlik istek sayısı 900'den 240'a iner.
  static const _pollInterval = Duration(seconds: 30);

  /// Son `_loadPartners` BAŞLANGICI — öne dönüş tazelemesini ayıklamak için.
  ///
  /// Soğuk açılışta gözlemci `build` sırasında eklenir ve uygulama hemen
  /// ardından `resumed` olur: `_tick` build'in isteği daha dönmeden AYNI
  /// listeyi ikinci kez çekiyordu (profile build'de iki
  /// `getPartnershipsWithStatus` + iki `getProfilesByIds`, ölçüldü
  /// 2026-09-28). Başlangıç zamanı tutulur ki eşzamanlı istek de sayılsın.
  DateTime? _sonYukleme;
  static const _taptaze = Duration(seconds: 10);

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Uygulama arka plandayken sorgu atmanın anlamı yok: kullanıcı sonucu
  /// göremez, ama pil ve mobil veri harcanır, Supabase kotası dolar.
  /// Öne dönünce hemen bir kez taze veri çekilir, sonra periyot devam eder.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final son = _sonYukleme;
      if (son == null || DateTime.now().difference(son) > _taptaze) _tick();
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  @override
  Future<List<PartnerAccount>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) {
      _stopPolling();
      return [];
    }
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    // Karşı taraf ortaklığı kaldırınca yansısın
    _startPolling();
    ref.onDispose(() {
      _stopPolling();
      if (_observing) {
        WidgetsBinding.instance.removeObserver(this);
        _observing = false;
      }
    });
    return _loadPartners(user.id);
  }

  Future<void> _tick() async {
    final u = ref.read(authProvider).valueOrNull;
    if (u == null) return;
    // `_tick` sahipsiz çağrılır (Timer.periodic + öne dönüş): fırlayan hata
    // zone handler'ına düşüp ÇÖKME sayılıyordu (Crashlytics 2026-10-06,
    // PostgrestException 504). Yoklama turu düşerse eldeki liste kalır,
    // sonraki tur yeniden dener; hata non-fatal kaydedilir.
    final List<PartnerAccount> fresh;
    try {
      fresh = await _loadPartners(u.id);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'PartnersNotifier._tick');
      return;
    }
    // Sadece gerçekten değişiklik varsa state güncelle — gereksiz rebuild engellenir
    final current = state.valueOrNull ?? [];
    final changed = fresh.length != current.length ||
        fresh.any((f) {
          final c = current.where((c) => c.user.id == f.user.id).firstOrNull;
          return c == null || c.isActive != f.isActive;
        });
    if (changed) state = AsyncData(fresh);
  }

  Future<List<PartnerAccount>> _loadPartners(String userId) async {
    _sonYukleme = DateTime.now();
    final statusList =
        await SupabaseService.instance.getPartnershipsWithStatus(userId);
    if (statusList.isEmpty) return [];

    final ids = statusList.map((s) => s.id).toList();
    final users = await SupabaseService.instance.getProfilesByIds(ids);

    // Profili eksik olan ortaklar için partner_invites'tan isim çek
    final missingIds =
        ids.where((id) => !users.any((u) => u.id == id)).toList();
    if (missingIds.isNotEmpty) {
      final resolved = await SupabaseService.instance
          .resolveNamesFromInvites(userId, missingIds);
      users.addAll(resolved);
    }

    return statusList.map((status) {
      final user = users.firstWhere(
        (u) => u.id == status.id,
        orElse: () => AppUser(
          id: status.id,
          email: '',
          displayName: 'Ortak',
          createdAt: DateTime.now(),
        ),
      );
      return PartnerAccount(user: user, isActive: status.active);
    }).toList();
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadPartners(user.id));
  }

  /// Kodu gönder — sadece invite'a to_user_id yazar, partnership kurmaz.
  /// Döner: (inviteId, partnerName) — UI bunu polling için saklar.
  Future<({String inviteId, String partnerName})> submitCode(
      String code) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) throw Exception('Oturum aç.');
    return AuthService.instance.submitPartnerCode(
      currentUserId: user.id,
      code: code,
    );
  }

  /// Kod sahibi onayladı → partnership kur, listeyi yenile
  Future<void> acceptInvite(String inviteId) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await AuthService.instance.acceptInvite(
      inviteId: inviteId,
      currentUserId: user.id,
    );
    await refresh();
  }

  /// Kod sahibi reddetti
  Future<void> rejectInvite(String inviteId) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await AuthService.instance.rejectInvite(
      inviteId: inviteId,
      currentUserId: user.id,
    );
  }

  Future<void> toggleHidden(String partnerId, bool hidden) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await SupabaseService.instance
        .setPartnershipHidden(user.id, partnerId, hidden);
    await refresh();
  }

  Future<void> removePartner(String partnerId) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await SupabaseService.instance.removePartnership(user.id, partnerId);
    await refresh();
  }
}

final partnersProvider =
    AsyncNotifierProvider<PartnersNotifier, List<PartnerAccount>>(
  PartnersNotifier.new,
);

final activePartnersProvider = Provider<List<AppUser>>((ref) {
  final partners = ref.watch(partnersProvider).valueOrNull ?? [];
  return partners.where((p) => p.isActive).map((p) => p.user).toList();
});

// ── Ortak logout akışı — her ekrandan çağrılabilir ───────────────────────────
// Onay dialogu gösterir, onaylanırsa logout yapar ve LoginScreen'e yönlendirir.

/// Onay dialogu gösterir, onaylanırsa logout yapar.
/// _AuthGate authProvider'ı dinlediği için LoginScreen yönlendirmesi otomatik olur.
Future<void> confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirm = await showSandikConfirm(
    context: context,
    title: 'Çıkış yap',
    message: 'Hesabından çıkmak istediğine emin misin?',
    confirmLabel: 'Çıkış yap',
    destructive: true,
  );
  if (!confirm || !context.mounted) return;
  await ref.read(authProvider.notifier).logout();
}

/// Push teşhis ekranı görünürlüğü. Oturum değişince yeniden hesaplanır.
/// Sunucudaki `is_push_admin()` RPC'sine bağlıdır (bkz. 0055 migration);
/// hata durumunda false — tile gizlenir, teşhis RPC'leri zaten kendini korur.
final isPushAdminProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(authProvider).valueOrNull?.id;
  if (userId == null) return false;
  return SupabaseService.instance.isPushAdmin();
});

// ── Bekleyen ortaklık istekleri — TEK kaynak ─────────────────────────────────

/// Onay bekleyen ortaklık istekleri.
///
/// ## Neden provider'a taşındı (kullanıcı bildirimi, 2026-09-16)
///
/// **Ölçülen arıza:** kullanıcı bildirimden gelen isteği onaylıyor, geri
/// dönünce istek Profil ekranında DURMAYA devam ediyor; ikinci kez
/// "Onayla"ya basınca "Bu davet zaten yanıtlanmış" hatası alıyor.
///
/// Sebep: iki ekran aynı listeyi AYRI AYRI tutuyordu.
///   - `PartnershipRequestsScreen._pendingInvites`  (bildirimden açılan)
///   - `profile_screen._PendingRequestsSectionState._pendingInvites`
///
/// Bildirim yolu ikinci ekranı birincinin ÜSTÜNE `push` ediyor. Üstteki
/// ekranda onay verilince o kendi listesini tazeliyor, ama alttaki ekranın
/// state'i dokunulmadan kalıyor — Navigator geri dönerken `initState`
/// yeniden çalışmaz, `ForegroundPoller` da yalnızca uygulama arka plandan
/// dönünce tetikleniyor (ekranlar arası geçişte değil).
///
/// Böylece kullanıcı SİLİNMİŞ bir daveti gösteren bayat bir kart görüyor.
/// Ona basınca sunucu doğru davranıp 409 `already_processed` dönüyor —
/// yani hata mesajı arızanın kendisi değil, SEMPTOMU. Sunucu tarafında
/// yanlış bir şey yok (`accept-invite/index.ts` kabulde `used=true` yazıyor
/// ve liste sorgusu `used=false` filtreliyor).
///
/// Tek kaynağa alınca her iki ekran aynı state'i izler: biri onayladığında
/// öteki kendiliğinden güncellenir.
class PendingInvitesNotifier
    extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    // Kullanıcı değişince (çıkış/giriş) liste kendiliğinden yeniden kurulur.
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];
    return SupabaseService.instance.getPendingInvitesForMe(user.id);
  }

  /// Sunucudan tazele. Onay/ret sonrası ve elle çekmede çağrılır; Profil
  /// ekranı 20 sn'de bir güvenlik ağı olarak da çağırır.
  ///
  /// Yanıt öncekiyle AYNIYSA state yazılmaz (2026-10-01, CPU raporu):
  /// her `AsyncData(yeniListe)` ataması, içerik aynı olsa da farklı liste
  /// örneği olduğu için dinleyicileri uyandırıyordu; Profil ekranı 20 sn'de
  /// bir boşa yeniden kuruluyor, ölçümde tur başına ~1,2 sn CPU ve 17 kare
  /// üretiyordu. Karşılaştırma JSON üzerinden: davet kayıtları Postgrest'ten
  /// düz JSON gelir (iç içe profil haritası dahil), `mapEquals` iç haritayı
  /// kimlikle kıyaslayıp hep "farklı" derdi.
  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      state = const AsyncData([]);
      return;
    }
    final yeni = await AsyncValue.guard(
      () => SupabaseService.instance.getPendingInvitesForMe(user.id),
    );
    final eski = state.valueOrNull;
    final yeniListe = yeni.valueOrNull;
    if (eski != null &&
        yeniListe != null &&
        davetKayitlariAyni(eski, yeniListe)) {
      return;
    }
    state = yeni;
  }

  /// Daveti listeden HEMEN düşür — sunucu turunu beklemeden.
  ///
  /// Onay/ret sonrası `refresh()` zaten çağrılıyor ama o bir ağ turu sürüyor;
  /// o arada kart ekranda duruyor ve ikinci kez basılabiliyordu. Bu tam da
  /// bildirilen arızanın oluştuğu aralık.
  void kaldir(String inviteId) {
    final mevcut = state.valueOrNull;
    if (mevcut == null) return;
    state = AsyncData(
      mevcut.where((i) => i['id'] != inviteId).toList(growable: false),
    );
  }
}

/// İki davet listesi içerik olarak aynı mı (bkz. [PendingInvitesNotifier.refresh]).
@visibleForTesting
bool davetKayitlariAyni(
    List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  if (a.length != b.length) return false;
  try {
    return jsonEncode(a) == jsonEncode(b);
  } catch (_) {
    // JSON'a dökülemeyen bir değer (beklenmez) — güvenli taraf: farklı say.
    return false;
  }
}

final pendingInvitesProvider =
    AsyncNotifierProvider<PendingInvitesNotifier, List<Map<String, dynamic>>>(
  PendingInvitesNotifier.new,
);
