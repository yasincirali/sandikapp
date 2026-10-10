import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../services/hesap_gecisi.dart';
import '../services/hesap_kasasi.dart';
import '../services/remote_config_service.dart';
import 'preferences_provider.dart';

/// Cihazda oturumu saklı hesaplar (çoklu hesap, bayrak `coklu_hesap`).
/// Kaynak [HesapGecisi.hesaplar]; kasa her değişince yeniden okunur.
final kayitliHesaplarProvider = Provider<List<KayitliHesap>>((ref) {
  final n = HesapGecisi.instance.hesaplar;
  void degisti() => ref.invalidateSelf();
  n.addListener(degisti);
  ref.onDispose(() => n.removeListener(degisti));
  return n.value;
});

/// Hesap seçici kullanıcıya görünür mü: bayrak açıksa herkese (demo hariç).
///
/// İlk sürümde (#152) Premium'du: seçici yalnız paywall açıkken ya da
/// adminde görünür, ekleme Premium isterdi. yasin 2026-10-10 akşam:
/// "session switch özelliği de premium olmamalı". Hesap ekleme ve geçiş
/// artık ücretsiz; tek sınır cihaz başına [HesapKasasi.enCok] hesap.
final cokluHesapGorunurProvider = Provider<bool>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  if (DemoModu.aktif) return false;
  return RemoteConfigService.instance.cokluHesap;
});
