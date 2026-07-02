import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_push_service.dart';
import '../services/supabase_service.dart';

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
  }

  Future<void> logout() async {
    await RemotePushService.instance.stop();
    await AuthService.instance.logout();
    DisclaimerService.instance.clearCache();
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

class PartnersNotifier extends AsyncNotifier<List<PartnerAccount>> {
  Timer? _pollTimer;

  @override
  Future<List<PartnerAccount>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) {
      _pollTimer?.cancel();
      return [];
    }
    // Karşı taraf ortaklığı kaldırınca anlık yansısın
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
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
    });
    ref.onDispose(() => _pollTimer?.cancel());
    return _loadPartners(user.id);
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
