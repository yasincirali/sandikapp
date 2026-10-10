import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../demo/demo_modu.dart';
import '../services/hesap_gecisi.dart';
import '../services/hesap_kasasi.dart';
import '../services/remote_config_service.dart';
import 'auth_provider.dart';
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

/// Hesap seçici kullanıcıya görünür mü.
///
/// Bayrak VE şunlardan biri: Premium yüzeyleri görünür (paywall açık ya da
/// admin — çoklu portföyle aynı kural) YA DA cihazda zaten 2+ hesap var.
/// İkinci koşul şart: admin hesabından normal bir hesaba geçen kullanıcı,
/// paywall kapalıyken seçiciyi kaybedip geri dönemezdi.
final cokluHesapGorunurProvider = Provider<bool>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  if (DemoModu.aktif) return false;
  if (!RemoteConfigService.instance.cokluHesap) return false;
  if (ref.watch(kayitliHesaplarProvider).length >= 2) return true;
  final admin = ref.watch(isPushAdminProvider).valueOrNull == true;
  return ref.watch(paywallVisibleProvider) || admin;
});

/// Yeni hesap EKLEME Premium mu istiyor (yasin 2026-10-10: "yeni ekranlar
/// ve özellikler paywall arkasında"). Geçiş ve çıkış her zaman serbest:
/// Premium'u biten kullanıcı kendi hesaplarına kilitli kalmamalı.
final hesapEklemeKilitliProvider =
    Provider<bool>((ref) => ref.watch(premiumKilitliProvider));
