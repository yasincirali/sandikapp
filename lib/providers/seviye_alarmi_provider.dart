import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/seviye_alarmi.dart';
import '../services/cizim_deposu.dart';
import '../services/crash_reporter.dart';
import '../services/seviye_alarmi_service.dart';
import 'alarm_disk_ilk.dart';
import 'auth_provider.dart';

/// Servis kapısı — testte sahte `SeviyeAlarmiStore`'lu servisle değiştirilir.
final seviyeAlarmiServiceProvider =
    Provider<SeviyeAlarmiService>((_) => SeviyeAlarmiService.instance);

/// Kullanıcının gösterge alarmları (0170) — `yuzdeAlarmlariProvider` ile
/// aynı kalıp ve aynı karar: **okuma hatası listeyi düşürmez.** 0170 bir
/// sunucuda henüz yoksa (iki sunucu sırayla dağıtılır) boş liste döner,
/// hata Crashlytics'e gider; Alarmlar ekranı fiyat alarmlarını hata
/// ekranının arkasına saklamaz.
class GostergeAlarmlariNotifier extends AsyncNotifier<List<GostergeAlarmi>> {
  SeviyeAlarmiService get _svc => ref.read(seviyeAlarmiServiceProvider);

  @override
  Future<List<GostergeAlarmi>> build() async {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const [];
    Future<List<GostergeAlarmi>> sunucu() async {
      try {
        return await _svc.gostergeleriGetir(me.id);
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'gostergeAlarmlari.fetch');
        return const [];
      }
    }

    return diskIlkYukle(
      ref: ref,
      disk: () => _svc.gostergeleriOnbellektenGetir(me.id),
      sunucu: sunucu,
      taze: (l) => state = AsyncData(l),
      neden: 'gostergeAlarmlari.arkaPlanOkuma',
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<GostergeAlarmi> create(GostergeAlarmi alarm) async {
    final kayit = await _svc.gostergeKur(alarm);
    state = AsyncData([kayit, ...(state.valueOrNull ?? const [])]);
    return kayit;
  }

  Future<void> delete(String id) async {
    await _svc.gostergeSil(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <GostergeAlarmi>[])
        if (a.id != id) a,
    ]);
  }
}

final gostergeAlarmlariProvider =
    AsyncNotifierProvider<GostergeAlarmlariNotifier, List<GostergeAlarmi>>(
        GostergeAlarmlariNotifier.new);

/// Kullanıcının çizgi (trend/ışın) alarmları (0170). Aynı kalıp.
class CizimAlarmlariNotifier extends AsyncNotifier<List<CizimAlarmi>> {
  SeviyeAlarmiService get _svc => ref.read(seviyeAlarmiServiceProvider);

  @override
  Future<List<CizimAlarmi>> build() async {
    final me = ref.watch(authProvider).valueOrNull;
    if (me == null) return const [];
    Future<List<CizimAlarmi>> sunucu() async {
      try {
        return await _svc.cizimleriGetir(me.id);
      } catch (e, st) {
        CrashReporter.report(e, st, reason: 'cizimAlarmlari.fetch');
        return const [];
      }
    }

    return diskIlkYukle(
      ref: ref,
      disk: () => _svc.cizimleriOnbellektenGetir(me.id),
      sunucu: sunucu,
      taze: (l) => state = AsyncData(l),
      neden: 'cizimAlarmlari.arkaPlanOkuma',
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Bilinen liste (yüklenmemişse boş) — `state` korumalı; çizim
  /// eşitlemesi ekrandan bağımsız okur.
  List<CizimAlarmi> get liste => state.valueOrNull ?? const [];

  void _yerinde(CizimAlarmi kayit) {
    state = AsyncData([
      kayit,
      for (final a in state.valueOrNull ?? const <CizimAlarmi>[])
        if (a.id != kayit.id) a,
    ]);
  }

  /// Yeni alarm ya da aynı çizimin çalmış satırını yeniden kurma
  /// ([SeviyeAlarmiService.cizimKur]).
  Future<CizimAlarmi> create(CizimAlarmi alarm) async {
    final eski = (state.valueOrNull ?? const <CizimAlarmi>[])
        .where((a) => a.symbol == alarm.symbol && a.cizimId == alarm.cizimId)
        .firstOrNull;
    final kayit = await _svc.cizimKur(alarm, eski: eski);
    _yerinde(kayit);
    return kayit;
  }

  /// Çizim taşındı: alarm yeni doğruya geçer.
  Future<CizimAlarmi> tasi(String id, CizimAlarmi yeni) async {
    final kayit = await _svc.cizimTasi(id, yeni);
    _yerinde(kayit);
    return kayit;
  }

  /// Alarmlarım'dan yeniden adlandırma ([SeviyeAlarmiService.cizimEtiketi]).
  Future<CizimAlarmi> etiketiGuncelle(String id, String label) async {
    final kayit = await _svc.cizimEtiketi(id, label);
    _yerinde(kayit);
    return kayit;
  }

  Future<void> delete(String id) async {
    await _svc.cizimSil(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <CizimAlarmi>[])
        if (a.id != id) a,
    ]);
  }
}

final cizimAlarmlariProvider =
    AsyncNotifierProvider<CizimAlarmlariNotifier, List<CizimAlarmi>>(
        CizimAlarmlariNotifier.new);

/// Yatay çizgi → fiyat alarmı bağları (2026-10-29, uçtan uca test: zil
/// kurulduktan sonra dolmuyordu, ikinci dokunuş ikinci alarm açıyordu,
/// çizgi silinince alarm ortada kalıyordu). Cihazda saklanır
/// ([CizimDeposu.alarmBaglari]); ilk okuma arka planda, [yuklendi] bekler.
class YatayAlarmBaglariNotifier extends Notifier<Map<String, YatayAlarmBagi>> {
  /// Kayıttan ilk okuma bitti mi — eşitleme bundan önce karar vermez
  /// (boş görünen bağ "alarm yok" sanılıp atlanmasın).
  Future<void> yuklendi = Future.value();

  @override
  Map<String, YatayAlarmBagi> build() {
    yuklendi = _yukle();
    CrashReporter.arkaPlan(yuklendi, reason: 'yatayAlarmBagi.oku');
    return const {};
  }

  Future<void> _yukle() async {
    final kayit = await CizimDeposu.instance.alarmBaglari();
    // Okuma sürerken kurulan bağ kayıttakini ezer (daha yeni).
    state = {...kayit, ...state};
  }

  Map<String, YatayAlarmBagi> get baglar => state;

  void bagla(String cizimId, String alarmId, double fiyat) {
    state = {...state, cizimId: (alarmId: alarmId, fiyat: fiyat)};
    _yaz();
  }

  void coz(String cizimId) {
    if (!state.containsKey(cizimId)) return;
    state = {...state}..remove(cizimId);
    _yaz();
  }

  /// İlk okuma bitmeden yazılırsa kayıttaki bağlar silinirdi; önce bekler.
  void _yaz() => CrashReporter.arkaPlan(() async {
        await yuklendi;
        await CizimDeposu.instance.alarmBaglariniYaz(state);
      }(), reason: 'yatayAlarmBagi.yaz');
}

final yatayAlarmBaglariProvider =
    NotifierProvider<YatayAlarmBaglariNotifier, Map<String, YatayAlarmBagi>>(
        YatayAlarmBaglariNotifier.new);
