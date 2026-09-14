import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/price_alert.dart';
import '../services/price_alert_service.dart';
import 'auth_provider.dart';

/// Servis kapısı — testte sahte `PriceAlertStore`'lu servisle değiştirilir.
final priceAlertServiceProvider =
    Provider<PriceAlertService>((_) => PriceAlertService.instance);

/// Kullanıcının fiyat alarmları — tek kaynak.
///
/// 2026-09-14: liste yalnızca `PriceAlertsScreen`'in kendi `Future`'ında
/// yaşıyordu. Alarm artık varlık ekranından kuruluyor ve Portföy kartında
/// zil rozeti olarak görünüyor; üç yüzeyin aynı listeyi görmesi için durum
/// provider'a çıktı. Yazma işlemleri (kur/sil/yeniden kur) sunucuya gider
/// ve başarıda state yerinde güncellenir — yeniden çekmeye gerek yok.
class PriceAlertsNotifier extends AsyncNotifier<List<PriceAlert>> {
  PriceAlertService get _svc => ref.read(priceAlertServiceProvider);

  @override
  Future<List<PriceAlert>> build() async {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const [];
    return _svc.fetchAll(me.id);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<PriceAlert> create(PriceAlert alarm) async {
    final kayit = await _svc.create(alarm);
    state = AsyncData([kayit, ...(state.valueOrNull ?? const [])]);
    return kayit;
  }

  Future<void> delete(String id) async {
    await _svc.delete(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        if (a.id != id) a,
    ]);
  }

  Future<void> rearm(String id) async {
    await _svc.rearm(id);
    // Sunucu satırı döndürmez; yerel kopya yamayla aynı şekle getirilir.
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        a.id == id
            ? PriceAlert(
                id: a.id,
                userId: a.userId,
                symbol: a.symbol,
                label: a.label,
                targetPrice: a.targetPrice,
                direction: a.direction,
                enabled: true,
                createdAt: a.createdAt,
              )
            : a,
    ]);
  }
}

final priceAlertsProvider =
    AsyncNotifierProvider<PriceAlertsNotifier, List<PriceAlert>>(
        PriceAlertsNotifier.new);

/// Belirli bir sembolün alarmları (aktif + tetiklenmiş), en yeni önce.
final symbolAlertsProvider =
    Provider.family<List<PriceAlert>, String>((ref, symbol) {
  final hepsi = ref.watch(priceAlertsProvider).valueOrNull ?? const [];
  return [for (final a in hepsi) if (a.symbol == symbol) a];
});
