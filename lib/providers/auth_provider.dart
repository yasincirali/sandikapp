import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';

// ── Mevcut oturum kullanıcısı ─────────────────────────────────────────────────

class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() => AuthService.instance.getSessionUser();

  Future<void> login({required String email, required String password}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => AuthService.instance.login(email: email, password: password),
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
    await AuthService.instance.logout();
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
  @override
  Future<List<PartnerAccount>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return [];
    return _loadPartners(user.id);
  }

  Future<List<PartnerAccount>> _loadPartners(String userId) async {
    final statusList = await DatabaseService.instance.getPartnershipsWithStatus(userId);
    if (statusList.isEmpty) return [];
    
    final ids = statusList.map((s) => s.id).toList();
    final users = await DatabaseService.instance.getUsersByIds(ids);
    
    // DB sırası ile eşleştir
    return statusList.map((status) {
      final user = users.firstWhere((u) => u.id == status.id);
      return PartnerAccount(user: user, isActive: status.active);
    }).toList();
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _loadPartners(user.id));
  }

  Future<String> redeemCode(String code) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) throw Exception('Oturum açın.');
    final partnerName = await AuthService.instance.redeemPartnerCode(
      currentUserId: user.id,
      code: code,
    );
    await refresh();
    return partnerName;
  }

  Future<void> toggleActive(String partnerId, bool active) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await DatabaseService.instance.setPartnershipActive(user.id, partnerId, active);
    await refresh();
  }

  Future<void> removePartner(String partnerId) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await DatabaseService.instance.removePartnership(user.id, partnerId);
    await refresh();
  }
}

final partnersProvider = AsyncNotifierProvider<PartnersNotifier, List<PartnerAccount>>(
  PartnersNotifier.new,
);

final activePartnersProvider = Provider<List<AppUser>>((ref) {
  final partners = ref.watch(partnersProvider).valueOrNull ?? [];
  return partners.where((p) => p.isActive).map((p) => p.user).toList();
});
