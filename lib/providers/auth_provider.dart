import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_push_service.dart';
import '../services/supabase_service.dart';
import 'bulk_cart_provider.dart';

// ── Mevcut oturum kullanıcısı ─────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() => AuthService.instance.getSessionUser();

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
      AnalyticsService.instance.logLogin(method: 'email');
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
      AnalyticsService.instance.logSignup(method: 'email');
    }
  }

  /// Ağ geri geldiğinde minimal (offline) profili gerçeğiyle değiştirir.
  ///
  /// `getSessionUser` ağ yokken token'dan minimal bir kullanıcı kuruyor —
  /// `displayName` boş oluyor. Bağlantı gelince sessizce tazelenir.
  /// Başarısız olursa mevcut state korunur: kullanıcı oturumdan atılmaz.
  Future<void> refreshProfileIfStale() async {
    final current = state.valueOrNull;
    if (current == null || current.displayName.isNotEmpty) return;
    try {
      final fresh = await AuthService.instance.refreshProfile();
      if (fresh != null) state = AsyncData(fresh);
    } catch (_) {
      // Ağ hâlâ yok — mevcut minimal profille devam.
    }
  }

  Future<void> logout() async {
    AnalyticsService.instance.logLogout();
    await RemotePushService.instance.stop();
    await AuthService.instance.logout();
    DisclaimerService.instance.clearCache();
    ref.read(bulkCartProvider.notifier).clear();
    state = const AsyncData(null);
  }

  /// Hesabı Edge Function üzerinden kalıcı olarak siler.
  /// Başarılıysa state'i null'a çeker → AuthGate LoginScreen'e döner.
  Future<void> deleteAccount({required String password}) async {
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
      _tick();
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
    final fresh = await _loadPartners(u.id);
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
    if (user == null) throw Exception('Oturum açın.');
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
  final confirm = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Çıkış Yap'),
      content: const Text('Hesabınızdan çıkmak istediğinizden emin misiniz?'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Çıkış Yap'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  await ref.read(authProvider.notifier).logout();
}
