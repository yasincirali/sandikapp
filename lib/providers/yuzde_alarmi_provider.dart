import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/yuzde_alarmi.dart';
import '../services/crash_reporter.dart';
import '../services/yuzde_alarmi_service.dart';
import 'auth_provider.dart';

/// Servis kapısı — testte sahte `YuzdeAlarmiStore`'lu servisle değiştirilir.
final yuzdeAlarmiServiceProvider =
    Provider<YuzdeAlarmiService>((_) => YuzdeAlarmiService.instance);

/// Kullanıcının günlük yüzde alarmları (0169) — `priceAlertsProvider` ile
/// aynı kalıp: yazma sunucuya gider, başarıda state yerinde güncellenir.
///
/// **Okuma hatası listeyi düşürmez:** 0169 bir sunucuda henüz yoksa (iki
/// sunucu sırayla dağıtılır) ya da tablo okunamazsa boş liste döner ve
/// hata Crashlytics'e gider. Aksi hâlde Alarmlar ekranı fiyat alarmlarını
/// da hata ekranının arkasına saklardı — yeni özellik eskisini bozmasın.
class YuzdeAlarmlariNotifier extends AsyncNotifier<List<YuzdeAlarmi>> {
  YuzdeAlarmiService get _svc => ref.read(yuzdeAlarmiServiceProvider);

  @override
  Future<List<YuzdeAlarmi>> build() async {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const [];
    try {
      return await _svc.fetchAll(me.id);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'yuzdeAlarmlari.fetch');
      return const [];
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<YuzdeAlarmi> create(YuzdeAlarmi alarm) async {
    final kayit = await _svc.create(alarm);
    state = AsyncData([kayit, ...(state.valueOrNull ?? const [])]);
    return kayit;
  }

  Future<void> delete(String id) async {
    await _svc.delete(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <YuzdeAlarmi>[])
        if (a.id != id) a,
    ]);
  }
}

final yuzdeAlarmlariProvider =
    AsyncNotifierProvider<YuzdeAlarmlariNotifier, List<YuzdeAlarmi>>(
        YuzdeAlarmlariNotifier.new);

