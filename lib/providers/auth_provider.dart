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

class PartnersNotifier extends AsyncNotifier<List<AppUser>> {
  @override
  Future<List<AppUser>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return [];
    return _loadPartners(user.id);
  }

  Future<List<AppUser>> _loadPartners(String userId) async {
    final ids = await DatabaseService.instance.getPartnerIds(userId);
    return DatabaseService.instance.getUsersByIds(ids);
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

  Future<void> removePartner(String partnerId) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await DatabaseService.instance.removePartnership(user.id, partnerId);
    await refresh();
  }
}

final partnersProvider = AsyncNotifierProvider<PartnersNotifier, List<AppUser>>(
  PartnersNotifier.new,
);
