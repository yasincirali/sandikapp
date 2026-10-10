import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../demo/demo_modu.dart';
import '../models/asset.dart';
import '../models/gorunum_kapsami.dart';
import '../models/portfoy.dart';
import '../models/position.dart';
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

/// Taşı'nın gidecek yeri var mı: en az bir ADLANDIRILMIŞ portföy (Ana her
/// zaman vardır; Ana + bir portföy = iki hedef). Liste yüklenmemişse yok
/// sayılır — düğme listeyle birlikte gelir, "yok" yerine geç gelmek
/// gidecek yeri olmayan bir düğmeden iyidir.
bool tasinacakPortfoyVar(List<Portfoy>? adlandirilmis) =>
    (adlandirilmis?.length ?? 0) >= 1;

/// Çoklu portföyün Premium yüzeyleri (ortağa portföy seçimi, kısmi
/// aktarım) kilitli mi. yasin 2026-10-10: "yeni ekranlar ve özellikler
/// paywall arkasında". Paywall kapalıyken kilit yok (çoklu portföyü zaten
/// yalnız admin görür). Kilit yalnız YENİ değişikliği durdurur: Premium
/// biten kullanıcının ortak seçimi sunucuda geçerli kalır (gizlenen portföy
/// abonelik bitti diye ortağa açılmaz), bölünmüş pozisyonu da olduğu yerde.
final portfoyPremiumKilitliProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  return !ref.watch(effectivePremiumProvider);
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

  /// Ad, Ana'nın kullanıcı verdiği adıyla çakışıyor mu (Ana yeniden
  /// adlandırılabilir; seçicide iki aynı ad hangisinin Ana olduğunu
  /// söylemez).
  bool _anaAdi(String ad) {
    final ana = ref.read(anaPortfoyAdiProvider);
    return ana != null && _anahtar(ana) == _anahtar(ad);
  }

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
    if (_liste.any((p) => _anahtar(p.ad) == _anahtar(ad)) || _anaAdi(ad)) {
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
    if (_liste.any((p) => p.id != id && _anahtar(p.ad) == _anahtar(ad)) ||
        _anaAdi(ad)) {
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

  /// Portföyü İÇİNDEKİ VARLIKLARLA siler (yasin 2026-10-10: "taşıma
  /// yapmamalıyız, bir portföy siliniyorsa onay ekranında gösterilen
  /// varlıklarla birlikte silinmeli").
  ///
  /// ## Neden varlık silme yolu, sunucuda yeni bir şey değil
  /// Her pozisyon, kullanıcının Portföy'de kaydırıp sildiği yoldan gider
  /// (`deletePositionLots`: yumuşak silme damgası + tek "Silindi" satırı).
  /// Böylece toplamlar, grafik, Zirve ve hareket geçmişi bir varlık
  /// silmesini nasıl görüyorsa bunu da öyle görür; ayrı bir "portföyle
  /// silinme" kuralı doğmaz. Kapanmış pozisyonların geçmiş kayıtları da
  /// silinir (yoksa Ana'ya taşınırdı). Sunucu FK'si (`on delete set null`,
  /// 0133) yerinde kalır: eski sürümün sildiği portföyün lotları Ana'ya
  /// döner, yalnız damgalı satırlar ve mezar taşları Ana'ya düşer, hiçbiri
  /// toplama girmez.
  ///
  /// Sıra: önce varlıklar, sonra portföy. Bir pozisyon silinemezse portföy
  /// silinmez ve hata yukarı çıkar; tekrar denemek kalanları siler (silinmiş
  /// lot yeniden seçilmez).
  Future<void> sil(String id) async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    final defter = ref.read(portfolioProvider).valueOrNull?.assets ?? const [];
    final portfolio = ref.read(portfolioProvider.notifier);
    for (final grup in portfoyunSilinecekGruplari(
        defter, id, {for (final p in _liste) p.id}, uid)) {
      await portfolio.deletePositionLots(grup);
    }
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

/// Portföy silinirken silinecek kayıtlar, pozisyon başına bir grup (saf,
/// test edilir): sahibin bu portföydeki SİLİNMEMİŞ lotları (alım, satım,
/// temettü; mezar taşları hariç), `positionKey`'e göre. Açık pozisyonlar ve
/// kapanmış pozisyonların geçmişi birlikte gelir.
List<List<Asset>> portfoyunSilinecekGruplari(
  List<Asset> defter,
  String portfoyId,
  Set<String> bilinen,
  String? sahipId,
) {
  final m = <String, List<Asset>>{};
  for (final a
      in portfoyeGoreBol(defter, bilinen)[portfoyId] ?? const <Asset>[]) {
    if (!a.isActive) continue;
    if (sahipId != null && a.userId != sahipId) continue;
    m.putIfAbsent(positionKey(a), () => []).add(a);
  }
  return m.values.toList();
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

/// Ana portföyün kullanıcı verdiği adı; `null` = varsayılan ("Ana
/// portföy" / kısa "Ana"). Kaynak `user_metadata` (gerekçe
/// `SupabaseService.anaPortfoyAdi`). Oturum değişince yeniden okunur
/// (çoklu hesap: her hesabın kendi adı).
class AnaPortfoyAdiNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(authProvider);
    if (DemoModu.aktif) return null;
    try {
      return SupabaseService.instance.anaPortfoyAdi();
    } catch (_) {
      // Supabase başlatılmamış (test) ya da oturum yok: varsayılan ad.
      return null;
    }
  }

  /// Yeniden adlandır. Ad kuralı ve tekillik adlandırılmış portföylerle
  /// AYNI: seçicide iki "Emeklilik" hangisinin Ana olduğunu söylemez.
  Future<void> yenidenAdlandir(String ad) async {
    if (!Portfoy.adGecerli(ad)) throw ArgumentError.value(ad, 'ad');
    final liste = ref.read(portfoylerProvider).valueOrNull ?? const [];
    final k = ad.trim().toLowerCase();
    if (liste.any((p) => p.ad.trim().toLowerCase() == k)) {
      throw const PortfoyAdiKullaniliyor();
    }
    await SupabaseService.instance.anaPortfoyAdiniYaz(ad);
    state = ad.trim();
  }
}

final anaPortfoyAdiProvider =
    NotifierProvider<AnaPortfoyAdiNotifier, String?>(AnaPortfoyAdiNotifier.new);

/// Silme onayında portföyün AÇIK pozisyonları (yasin 2026-10-10: "içinde
/// varlık olan portföyü silerken varlıklar listelenip öyle onay alınmalı").
/// Değer en büyükten; her satırın değeri `PortfolioState.totalValue` yolu
/// (Portföy ekranındaki toplamla aynı hesap). Boş liste = portföyde açık
/// pozisyon yok, onay kısa sorulur.
typedef PortfoyPozisyonu = ({Position pozisyon, double deger});

final portfoyPozisyonlariProvider =
    Provider.family<List<PortfoyPozisyonu>, String?>((ref, portfoyId) {
  final s = ref.watch(portfolioProvider).valueOrNull;
  final liste = ref.watch(portfoylerProvider).valueOrNull;
  if (s == null || liste == null) return const [];
  final bilinen = {for (final p in liste) p.id};
  final lotlar = portfoyeGoreBol(s.assets, bilinen)[portfoyId] ?? const [];
  final out = <PortfoyPozisyonu>[
    for (final p in aggregatePositions(lotlar))
      (
        pozisyon: p,
        deger: s.copyWith(assets: [
          for (final a in lotlar)
            if (positionKey(a) == p.key) a
        ]).totalValue,
      ),
  ]..sort((a, b) => b.deger.compareTo(a.deger));
  return out;
});
