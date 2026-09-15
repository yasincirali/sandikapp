import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert_notification.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';

/// Supabase `price_alert_notifications` tablosunun state'i (0065).
///
/// **Neden `signalProvider`'dan ayrı:** iki bildirim türünün veri modeli
/// ayrı (bkz. `PriceAlertNotification` sınıf notu). Aynı notifier'a
/// sokmak, teknik sinyale özgü `analyzePortfolio` mantığıyla alarm
/// listesini aynı sınıfta tutmak olurdu.
///
/// **Yazma yok:** satırları yalnızca edge function (service_role) yazar;
/// istemcinin INSERT yetkisi bilinçli olarak verilmedi. Buradaki işlemler
/// yalnızca okuma, dismiss ve silme.
class PriceAlertNotificationNotifier
    extends AsyncNotifier<List<PriceAlertNotification>> {
  @override
  Future<List<PriceAlertNotification>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];
    try {
      return await SupabaseService.instance
          .fetchPriceAlertNotifications(userId: user.id);
    } catch (_) {
      // Liste ikincil bir yüzey: okunamazsa çan sayfası sinyallerle
      // çalışmaya devam etmeli, hata ekranına düşmemeli.
      return const [];
    }
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    try {
      final list = await SupabaseService.instance
          .fetchPriceAlertNotifications(userId: user.id);
      state = AsyncData(list);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Tek bildirimi listeden düşürür (geçmişte kalır).
  ///
  /// İyimser güncelleme + hata durumunda geri alma: sinyal tarafındaki
  /// `SignalNotifier.dismiss` ile aynı sözleşme — başarısızlık çağırana
  /// ULAŞMALI ki kullanıcı "silindi" sanmasın.
  Future<void> dismiss(String id) async {
    final mevcut = state.valueOrNull ?? const [];
    state = AsyncData([
      for (final n in mevcut)
        if (n.id == id) n.copyWith(dismissedAt: DateTime.now()) else n,
    ]);
    try {
      await SupabaseService.instance.dismissPriceAlertNotifications([id]);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }

  /// Tek bildirimi KALICI siler.
  Future<void> delete(String id) async {
    final mevcut = state.valueOrNull ?? const [];
    state = AsyncData(mevcut.where((n) => n.id != id).toList());
    try {
      await SupabaseService.instance.deletePriceAlertNotifications([id]);
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
      await SupabaseService.instance.dismissPriceAlertNotifications(ids);
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
      await SupabaseService.instance.deletePriceAlertNotifications(ids);
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
      await SupabaseService.instance.deletePriceAlertNotifications(ids);
    } catch (_) {
      state = AsyncData(mevcut);
      rethrow;
    }
  }
}

final priceAlertNotificationProvider = AsyncNotifierProvider<
    PriceAlertNotificationNotifier, List<PriceAlertNotification>>(
  PriceAlertNotificationNotifier.new,
);

/// Rozet ve çan sayfası için: yalnızca aktif (dismiss edilmemiş) alarmlar.
final activePriceAlertNotificationsProvider =
    Provider<List<PriceAlertNotification>>((ref) {
  final all = ref.watch(priceAlertNotificationProvider).valueOrNull ?? const [];
  return all.where((n) => !n.isDismissed).toList();
});
