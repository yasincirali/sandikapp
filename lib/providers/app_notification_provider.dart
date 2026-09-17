import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Supabase `app_notifications` tablosunun state'i (0066).
///
/// `PriceAlertNotificationNotifier` ile AYNI sözleşme: yazma yok (satırı
/// yalnızca edge function yazar), iyimser güncelleme + hata durumunda geri
/// alma, başarısızlık çağırana ULAŞIR ki kullanıcı "silindi" sanmasın.
class AppNotificationNotifier extends AsyncNotifier<List<AppNotification>> {
  @override
  Future<List<AppNotification>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];
    try {
      return await SupabaseService.instance
          .fetchAppNotifications(userId: user.id);
    } catch (_) {
      // İkincil yüzey: okunamazsa çan diğer iki kaynakla çalışmaya devam eder.
      return const [];
    }
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    try {
      state = AsyncData(await SupabaseService.instance
          .fetchAppNotifications(userId: user.id));
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> dismiss(String id) async {
    final mevcut = state.valueOrNull ?? const [];
    state = AsyncData([
      for (final n in mevcut)
        if (n.id == id) n.copyWith(dismissedAt: DateTime.now()) else n,
    ]);
    try {
      await SupabaseService.instance.dismissAppNotifications([id]);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final mevcut = state.valueOrNull ?? const [];
    state = AsyncData(mevcut.where((n) => n.id != id).toList());
    try {
      await SupabaseService.instance.deleteAppNotifications([id]);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }

  /// Aktif olanların hepsini listeden düşürür.
  Future<void> dismissAll() async {
    final mevcut = state.valueOrNull ?? const [];
    final ids = mevcut.where((n) => !n.isDismissed).map((n) => n.id).toList();
    if (ids.isEmpty) return;
    final simdi = DateTime.now();
    state = AsyncData([
      for (final n in mevcut)
        n.isDismissed ? n : n.copyWith(dismissedAt: simdi),
    ]);
    try {
      await SupabaseService.instance.dismissAppNotifications(ids);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }

  /// Yalnızca GEÇMİŞİ (dismissed olanları) kalıcı siler.
  Future<void> deleteHistory() async {
    final mevcut = state.valueOrNull ?? const [];
    final ids = mevcut.where((n) => n.isDismissed).map((n) => n.id).toList();
    if (ids.isEmpty) return;
    state = AsyncData(mevcut.where((n) => !n.isDismissed).toList());
    try {
      await SupabaseService.instance.deleteAppNotifications(ids);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }

  /// Hepsini (aktif + geçmiş) kalıcı siler.
  Future<void> deleteAll() async {
    final mevcut = state.valueOrNull ?? const [];
    final ids = mevcut.map((n) => n.id).toList();
    if (ids.isEmpty) return;
    state = const AsyncData([]);
    try {
      await SupabaseService.instance.deleteAppNotifications(ids);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }
}

final appNotificationProvider =
    AsyncNotifierProvider<AppNotificationNotifier, List<AppNotification>>(
  AppNotificationNotifier.new,
);

/// Rozet ve çan sayfası için: yalnızca aktif (dismiss edilmemiş) kayıtlar.
final activeAppNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final all = ref.watch(appNotificationProvider).valueOrNull ?? const [];
  return all.where((n) => !n.isDismissed).toList();
});
