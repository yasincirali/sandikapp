import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../demo/demo_modu.dart';
import '../models/gorunum_kapsami.dart';
import '../models/portfoy.dart';
import '../services/analytics_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';

/// Çoklu portföy (0133) — sağlayıcılar.
///
/// ## Üç ayrı soru, üç ayrı sağlayıcı
/// - Şema hazır mı (yazım kapısı): `RemoteConfigService.cokluPortfoy`.
///   Kapalıyken `portfoy_id` hiçbir gövdeye yazılmaz, tablo okunmaz.
/// - Kullanıcı görür mü: [cokluPortfoyGorunurProvider] = bayrak VE
///   Premium özelliklerinin görünürlüğü (paywall açık ya da admin; yasin
///   2026-10-09 "tek flag" kuralı).
/// - Hangi kapsam: [portfoyKapsamiProvider]. Görünmüyorsa HEP "Tümü": bütün
///   toplamlar, seriler ve ekranlar bugünkü kullanıcı toplamıyla birebir.

const _uuid = Uuid();

/// Çoklu portföy bu kullanıcıya görünür mü.
///
/// `RemoteConfigService.premiumOzellikleriGorunur` ile AYNI karar (paywall
/// açık ya da admin), ama reaktif: o alan `_AuthGate`'in yazdığı bir
/// değişken, burada ise admin sonucu ve RC etkinleşmesi izlenir — admin
/// hesabı açılışta seçiciyi bir sonraki soğuk açılışı beklemeden görür.
/// Demo (F1) sunucu yok: hiç görünmez.
final cokluPortfoyGorunurProvider = Provider<bool>((ref) {
  ref.watch(rcEtkinlesmeProvider);
  if (DemoModu.aktif) return false;
  if (!RemoteConfigService.instance.cokluPortfoy) return false;
  final admin = ref.watch(isPushAdminProvider).valueOrNull == true;
  return ref.watch(paywallVisibleProvider) || admin;
});

/// Toplam portföy sınırı (Ana DAHİL) — `assetLimitProvider` deseni.
/// Paywall kapalıyken ya da Premium'da pratikte sınırsız; ücretsizde 1
/// (yalnız Ana). Var olan portföyler sınır düşünce SİLİNMEZ (Premium biten
/// kullanıcı verisini kaybetmez); yalnız yenisi açılamaz.
final portfoyLimitProvider = Provider<int>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return 1 << 30;
  if (ref.watch(effectivePremiumProvider)) return 1 << 30;
  return 1;
});

/// Yeni portföy açmak Premium ister mi (sınır dolu).
final portfoySiniriDoluProvider = Provider<bool>((ref) {
  final adlandirilmis = ref.watch(portfoylerProvider).valueOrNull?.length ?? 0;
  // +1: Ana bir satır değil ama sınırın içinde sayılır.
  return adlandirilmis + 1 >= ref.watch(portfoyLimitProvider);
});

/// Ücretsiz sınır dolu iken yeni portföy isteği — UI paywall'u açar
/// (kaynak `portfoy_limit`).
class PortfoyLimitiAsildi implements Exception {
  const PortfoyLimitiAsildi();
}

/// Aynı adda portföy zaten var (istemci denetimi; sunucuda tekil indeks).
class PortfoyAdiKullaniliyor implements Exception {
  const PortfoyAdiKullaniliyor();
}

/// Kullanıcının adlandırılmış portföyleri, seçici sırasıyla.
///
/// Bayrak kapalıyken, oturum yokken ya da demoda BOŞ liste — tablo hiç
/// okunmaz (0133 sunucuda olmayabilir). Okuma hatası `AsyncError` olur;
/// [portfoyKapsamiProvider] o durumda "Tümü"ye düşer.
class PortfoylerNotifier extends AsyncNotifier<List<Portfoy>> {
  @override
  Future<List<Portfoy>> build() async {
    ref.watch(rcEtkinlesmeProvider);
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null || DemoModu.aktif) return const [];
    if (!RemoteConfigService.instance.cokluPortfoy) return const [];
    return SupabaseService.instance.fetchPortfoyler(user.id);
  }

  List<Portfoy> get _liste => state.valueOrNull ?? const [];

  static String _anahtar(String ad) => ad.trim().toLowerCase();

  /// Yeni portföy. Sınır doluysa [PortfoyLimitiAsildi], ad başka bir
  /// portföyde varsa [PortfoyAdiKullaniliyor] fırlatır (sunucuya gitmeden).
  Future<Portfoy> olustur(String ad) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) throw StateError('Oturum yok.');
    if (ref.read(portfoySiniriDoluProvider)) {
      unawaited(AnalyticsService.instance
          .logPremiumGateShown(feature: 'portfoy_limit'));
      throw const PortfoyLimitiAsildi();
    }
    if (!Portfoy.adGecerli(ad)) throw ArgumentError.value(ad, 'ad');
    if (_liste.any((p) => _anahtar(p.ad) == _anahtar(ad))) {
      throw const PortfoyAdiKullaniliyor();
    }
    final sira = _liste.fold<int>(0, (m, p) => p.sira > m ? p.sira : m) + 1;
    final p = Portfoy(
      id: _uuid.v4(),
      userId: user.id,
      ad: ad.trim(),
      sira: sira,
      createdAt: DateTime.now(),
    );
    await SupabaseService.instance.insertPortfoy(p);
    state = AsyncData([..._liste, p]..sort(Portfoy.karsilastir));
    return p;
  }

  Future<void> yenidenAdlandir(String id, String ad) async {
    if (!Portfoy.adGecerli(ad)) throw ArgumentError.value(ad, 'ad');
    if (_liste.any((p) => p.id != id && _anahtar(p.ad) == _anahtar(ad))) {
      throw const PortfoyAdiKullaniliyor();
    }
    final eski = _liste.firstWhere((p) => p.id == id);
    final yeni = eski.kopya(ad: ad.trim());
    await SupabaseService.instance.updatePortfoy(yeni);
    state = AsyncData([
      for (final p in _liste) p.id == id ? yeni : p,
    ]);
  }

  /// [siraliIdler] yeni sırayı verir; yalnız sırası değişen satır yazılır.
  Future<void> sirala(List<String> siraliIdler) async {
    final m = {for (final p in _liste) p.id: p};
    final yeni = <Portfoy>[];
    for (var i = 0; i < siraliIdler.length; i++) {
      final p = m[siraliIdler[i]];
      if (p == null) continue;
      yeni.add(p.sira == i ? p : p.kopya(sira: i));
    }
    // İyimser: liste hemen yeni sırada; yazım düşerse yeniden yüklenir.
    final onceki = _liste;
    state = AsyncData(yeni);
    try {
      for (final p in yeni) {
        if (m[p.id]!.sira != p.sira) {
          await SupabaseService.instance.updatePortfoy(p);
        }
      }
    } catch (_) {
      state = AsyncData(onceki);
      rethrow;
    }
  }

  /// Portföyü siler. Lotları sunucuda FK ile Ana'ya döner; bellekteki
  /// defter de aynı anda Ana'ya çekilir (yeniden yükleme beklenmez). Seçili
  /// portföy buysa seçim "Tümü"ye döner.
  Future<void> sil(String id) async {
    await SupabaseService.instance.deletePortfoy(id);
    state = AsyncData([
      for (final p in _liste)
        if (p.id != id) p
    ]);
    ref.read(portfolioProvider.notifier).portfoySilindi(id);
    if (ref.read(seciliPortfoyProvider) == id) {
      await ref.read(seciliPortfoyProvider.notifier).set(PortfoySecimi.tumu);
    }
  }
}

final portfoylerProvider =
    AsyncNotifierProvider<PortfoylerNotifier, List<Portfoy>>(
        PortfoylerNotifier.new);

/// Ekranların uyguladığı portföy kapsamı: seçim + bilinen portföy kimlikleri
/// (`gorunum_kapsami.dart` girdisi).
///
/// "Tümü"ye düşülen durumlar (bugünkü davranış birebir): özellik görünmüyor,
/// liste yüklenmedi ya da okunamadı, kayıtlı seçim artık yok, ya da yalnız
/// Ana var (adlandırılmış portföy yokken Ana == Tümü; aynı kümeyi iki
/// farklı önbellek anahtarıyla tutmamak için).
typedef PortfoyKapsami = ({String secim, Set<String> bilinen});

final portfoyKapsamiProvider = Provider<PortfoyKapsami>((ref) {
  const tumu = (secim: PortfoySecimi.tumu, bilinen: <String>{});
  if (!ref.watch(cokluPortfoyGorunurProvider)) return tumu;
  final liste = ref.watch(portfoylerProvider).valueOrNull;
  if (liste == null || liste.isEmpty) return tumu;
  // Kullanıcı değişimi (A çıktı, B girdi): Riverpod yeniden kurulum
  // karesinde `valueOrNull` A'nın listesini taşır (bkz. kullanıcı değişimi
  // tuzakları). Liste oturum sahibinin değilse kapsam kurulmaz.
  final uid = ref.watch(authProvider).valueOrNull?.id;
  if (liste.any((p) => p.userId != uid)) return tumu;
  final bilinen = {for (final p in liste) p.id};
  final secim = ref.watch(seciliPortfoyProvider);
  if (secim == PortfoySecimi.ana || bilinen.contains(secim)) {
    return (secim: secim, bilinen: bilinen);
  }
  return (secim: PortfoySecimi.tumu, bilinen: bilinen);
});

/// Yeni kaydın varsayılan portföyü (ekleme formu, toplu ekleme, yeni
/// sözleşme): seçili adlandırılmış portföy, yoksa Ana (`null`). Bayrak
/// kapalıyken hep `null`.
final varsayilanYeniPortfoyProvider = Provider<String?>((ref) {
  final k = ref.watch(portfoyKapsamiProvider);
  return k.bilinen.contains(k.secim) ? k.secim : null;
});

/// Yönetim sayfasının portföy özetleri (anahtar `null` = Ana): güncel değer
/// ve kayıt sayısı. Değer `PortfolioState.totalValue`'nun KENDİSİ — Portföy
/// ekranında o portföy seçiliyken görünen toplamla aynı yol; Σ değer ==
/// Tümü (`test/coklu_portfoy_test.dart`). Kayıt sayısı silme onayında
/// "kaç kayıt Ana'ya döner" sorusunun cevabı.
typedef PortfoyOzeti = ({double deger, int kayit});

final portfoyOzetleriProvider = Provider<Map<String?, PortfoyOzeti>>((ref) {
  final s = ref.watch(portfolioProvider).valueOrNull;
  final liste = ref.watch(portfoylerProvider).valueOrNull;
  if (s == null || liste == null) return const {};
  final bilinen = {for (final p in liste) p.id};
  return {
    for (final e in portfoyeGoreBol(s.assets, bilinen).entries)
      e.key: (
        deger: s.copyWith(assets: e.value).totalValue,
        kayit: e.value.length,
      ),
  };
});
