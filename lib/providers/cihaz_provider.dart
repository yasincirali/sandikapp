import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/kayitli_cihaz.dart';
import '../services/cihaz_oturumu_service.dart';
import '../services/crash_reporter.dart';
import 'auth_provider.dart';

/// Giriş sonrası cihaz kapısı (0098) — `_AuthGate` bunu izler.
///
/// Yalnızca kullanıcı KİMLİĞİ değişince yeniden değerlendirilir: profil
/// tazelemesi (ad, onboarding bayrağı) kapıyı yeniden koşturup sunucuya
/// gereksiz `oturum_al` yağdırmasın.
class CihazKapisiNotifier extends AsyncNotifier<CihazKapisi>
    with WidgetsBindingObserver {
  bool _gozlemci = false;

  CihazOturumuService get _servis => CihazOturumuService.instance;

  @override
  Future<CihazKapisi> build() async {
    final uid = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
    ref.onDispose(_gozlemciyiKaldir);
    await _servis.birak();
    if (uid == null) return CihazKapisi.serbest;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || user.id != uid) return CihazKapisi.serbest;

    final karar = await _servis.degerlendir(user);
    if (karar == CihazKapisi.serbest) _izlemeyeBasla(uid);
    return karar;
  }

  void _izlemeyeBasla(String uid) {
    if (!_gozlemci) {
      WidgetsBinding.instance.addObserver(this);
      _gozlemci = true;
    }
    CrashReporter.arkaPlan(_servis.izle(uid, _atildi),
        reason: 'CihazKapisi.izle');
  }

  void _gozlemciyiKaldir() {
    if (_gozlemci) {
      WidgetsBinding.instance.removeObserver(this);
      _gozlemci = false;
    }
  }

  void _atildi() {
    if (state.valueOrNull == CihazKapisi.serbest) {
      state = const AsyncData(CihazKapisi.atildi);
    }
  }

  /// Realtime uygulama arkadayken kopabilir (iOS soketi askıya alır):
  /// öne dönüşte aynı soru doğrudan sorulur.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) return;
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null || state.valueOrNull != CihazKapisi.serbest) return;
    CrashReporter.arkaPlan(() async {
      if (!await _servis.halaAktifMi(uid)) _atildi();
    }(), reason: 'CihazKapisi.oneDonus');
  }

  /// Kod e-postası. Hata çağırana fırlar (ekran gösterir).
  Future<void> kodGonder() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await _servis.kodGonder(user);
  }

  /// Kodu doğrula → cihaz kaydedilir, oturum bu cihaza geçer, kapı açılır.
  Future<void> kodDogrula(String kod) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await _servis.kodDogrula(user, kod);
    state = const AsyncData(CihazKapisi.serbest);
    _izlemeyeBasla(user.id);
  }

  void yenidenDene() => ref.invalidateSelf();
}

final cihazKapisiProvider =
    AsyncNotifierProvider<CihazKapisiNotifier, CihazKapisi>(
  CihazKapisiNotifier.new,
);

/// Kayıtlı cihaz listesi + bu cihazın kimliği (listede "Bu cihaz" için).
final kayitliCihazlarProvider =
    FutureProvider.autoDispose<({List<KayitliCihaz> liste, String buCihaz})>(
        (ref) async {
  final uid = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
  if (uid == null) return (liste: const <KayitliCihaz>[], buCihaz: '');
  final servis = CihazOturumuService.instance;
  final buCihaz = await servis.cihazKimligi(uid);
  final liste = await servis.liste(uid);
  return (liste: liste, buCihaz: buCihaz);
});
