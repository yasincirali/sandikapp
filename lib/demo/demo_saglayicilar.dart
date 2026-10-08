import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/kullanici_adi.dart';
import '../models/price_alert.dart';
import '../models/price_alert_notification.dart';
import '../models/signal_alert.dart';
import '../models/user_model.dart';
import '../models/watchlist_item.dart';
import '../providers/app_notification_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/kripto_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/price_alert_notification_provider.dart';
import '../providers/price_alert_provider.dart';
import '../providers/quiet_hours_provider.dart';
import '../providers/signal_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/crash_reporter.dart';
import '../services/price_service.dart';
import '../services/social_auth_service.dart';
import '../services/tazelik_ritmi.dart';
import '../utils/friendly_error.dart';
import '../utils/money_format.dart';
import 'demo_modu.dart';
import 'demo_verisi.dart';

/// Demo kabuğunun `ProviderContainer`'ına verilen değişiklikler.
///
/// ## Kapsam kuralı — neden bu liste ve neden AYRI bir container
/// Kabuk ebeveynsiz bir `ProviderContainer` kurar (bkz. `DemoKabugu`).
/// Ebeveynli iç içe `ProviderScope` burada YANLIŞ olurdu: Riverpod 2'de
/// `dependencies` bildirmeyen türev sağlayıcılar (ör. `activePartnersProvider`,
/// `watchlistCountProvider`) kök container'da kurulur ve kökteki —
/// oturumsuz — `authProvider`'ı izler; ekran demo defterini değil boş
/// kökü görürdü. Ebeveynsiz container'da HER sağlayıcı taze kurulur ve
/// aşağıdakiler dışındakiler gerçek kodlarıyla çalışır (tercih okuma,
/// baz para, sepet…).
///
/// Buradaki her satır gerçek sürümü SUNUCUYA giden bir sağlayıcıdır:
/// oturum açık göründüğü için (demo kullanıcısı) gerçek sürüm hemen
/// Supabase'e sorgu atardı. Liste eksik kalırsa `SupabaseService` kapısı
/// (`DemoModu.sunucuEngeli`) isteği ağa çıkmadan düşürür ve
/// `demo_izolasyon_test` izini yakalar.
List<Override> demoOverrides() => [
      authProvider.overrideWith(_DemoAuth.new),
      portfolioProvider.overrideWith(DemoPortfolioNotifier.new),
      partnersProvider.overrideWith(_DemoPartners.new),
      allPartnerAssetsProvider.overrideWith(_DemoPartnerAssets.new),
      pendingInvitesProvider.overrideWith(_DemoPendingInvites.new),
      isPushAdminProvider.overrideWith((ref) async => false),
      signalProvider.overrideWith(_DemoSignals.new),
      priceAlertNotificationProvider
          .overrideWith(_DemoPriceAlertNotifications.new),
      appNotificationProvider.overrideWith(_DemoAppNotifications.new),
      priceAlertsProvider.overrideWith(_DemoPriceAlerts.new),
      watchlistProvider.overrideWith(_DemoWatchlist.new),
      quietHoursProvider.overrideWith(_DemoQuietHours.new),
      kriptoKatalogProvider.overrideWith((ref) async => const []),
    ];

// ── Oturum ──────────────────────────────────────────────────────────────────

/// Sabit demo kullanıcısı. Oturum işlemleri (giriş, çıkış, ad seçme) demo
/// içinde anlamsız; çıkış özellikle TEHLİKELİ olurdu — gerçek sürüm
/// `RemotePushService.stop` ve `AuthService.logout` çağırır.
class _DemoAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => demoKullanici;

  @override
  Future<void> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async =>
      DemoModu.yazmaEngeli('giris');

  @override
  Future<void> loginWithSocial(SocialProvider provider) async =>
      DemoModu.yazmaEngeli('giris');

  @override
  Future<void> register({
    required String email,
    required String displayName,
    required String password,
  }) async =>
      DemoModu.yazmaEngeli('kayit');

  @override
  Future<KullaniciAdiSonuc> kullaniciAdiKaydet(String ad) async =>
      DemoModu.yazmaEngeli('kullanici_adi');

  @override
  Future<void> refreshProfileIfStale() async {}

  @override
  Future<void> logout() async => DemoModu.yazmaEngeli('cikis');

  @override
  Future<void> deleteAccount({String? password}) async =>
      DemoModu.yazmaEngeli('hesap_sil');
}

// ── Portföy ─────────────────────────────────────────────────────────────────

/// Demo defteri: `store_listing/demo_portfoy.csv` lot'ları, fiyatlar CANLI.
///
/// Okuma yolu gerçek sürümle aynı `PortfolioState` hesaplarını kullanır —
/// toplam, maliyet, getiri ve grafikler kullanıcının kendi defterinde
/// göreceğinin aynısı. Farklı olan yalnızca veri kaynağı ve yan etkiler:
///
/// - `build` sunucudan değil [demoLotlari]'ndan okur, diske önbellek yazmaz.
/// - [refreshPrices] fiyatları `PriceService.fetchQuotes` ile herkese açık
///   kaynaklardan (Yahoo, TEFAS, truncgil) çeker. Gerçek turun sunucu
///   yazımı (`_fiyatlariYaz`), anlık görüntüsü (`_saveSnapshot`) ve ortak
///   yüklemesi YOK. Demo defterinde kripto yok: `fetchQuotes` kriptoyu
///   sunucu tablosundan okur (bkz. `PriceService._fetchKripto`).
/// - Her yazma metodu [DemoModu.yazmaEngeli] ile durur: "hesap oluştur"
///   sayfası açılır, çağıran başarı yoluna girmez.
class DemoPortfolioNotifier extends PortfolioNotifier {
  /// Kotasyon kaynağı — testte ağsız sabit fiyat verilir. Üretimde gerçek
  /// turun kullandığı `PriceService.fetchQuotes`'un kendisi.
  @visibleForTesting
  static Future<Map<String, YahooQuote>> Function(
          List<String> semboller, bool zorla) kotasyonlar =
      (s, z) => PriceService.instance.fetchQuotes(s, forceRefresh: z);

  Future<void>? _suren;
  bool _surenZorla = false;

  @override
  Future<PortfolioState> build() async {
    final bos = PortfolioState(
      assets: demoLotlari(),
      ownerId: kDemoKullaniciId,
    );
    // İlk kare fiyatlı gelsin: fiyatsız lot toplamlara girmez ve ekran
    // ₺0 ile açılırdı. Ağ yoksa defter fiyatsız döner ve mesaj söyler —
    // uydurma bir fiyat yazılmaz.
    try {
      return await _fiyatla(bos, force: false)
          .timeout(TazelikRitmi.yuzey);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'DemoPortfolioNotifier.build');
      return bos.copyWith(
          errorMessage: 'Fiyatlar güncellenemedi. ${friendlyError(e)}');
    }
  }

  /// Gerçek turdaki sembol kuralının aynısı (bkz.
  /// `PortfolioNotifier._fiyatTuru`): üç kur her zaman, gram altın yalnızca
  /// baz birim altınsa, silinmemiş ve elle fiyatlanmamış her varlık.
  Future<PortfolioState> _fiyatla(PortfolioState s,
      {required bool force}) async {
    final symbols = <String>{'USDTRY=X', 'EURTRY=X', 'GBPTRY=X'};
    if (BaseCurrency.fromIndex(ref.read(baseCurrencyIndexProvider)) ==
        BaseCurrency.gold) {
      symbols.add(kGoldGramSymbol);
    }
    for (final a in s.assets) {
      if (!a.isActive) continue;
      if (a.ticker.isNotEmpty && !a.isManualPrice) {
        symbols.add(a.ticker.toUpperCase());
      }
    }
    final quotes = await kotasyonlar(symbols.toList(), force);

    final simdi = DateTime.now();
    for (final a in s.assets) {
      if (!a.isActive || a.isManualPrice || a.ticker.isEmpty) continue;
      final fiyat = quotes[a.ticker.toUpperCase()]?.regularMarketPrice;
      if (fiyat == null) continue;
      a.currentPrice = fiyat;
      a.lastUpdated = simdi;
    }
    return s.copyWith(
      assets: List<Asset>.of(s.assets),
      usdTry: quotes['USDTRY=X']?.regularMarketPrice ?? s.usdTry,
      eurTry: quotes['EURTRY=X']?.regularMarketPrice ?? s.eurTry,
      gbpTry: quotes['GBPTRY=X']?.regularMarketPrice ?? s.gbpTry,
      goldGramTry: quotes[kGoldGramSymbol]?.regularMarketPrice ?? s.goldGramTry,
      isLoading: false,
      clearError: true,
      lastUpdated: simdi,
    );
  }

  /// Süren tura katılma kuralı gerçek sürümle aynı: zorlamalı istek
  /// önbellekten beslenen tura katılmaz, bitmesini bekleyip kendi turunu
  /// atar.
  @override
  Future<void> refreshPrices({bool force = false, bool nabiz = false}) async {
    final zorla = force || nabiz;
    final suren = _suren;
    if (suren != null) {
      if (!zorla || _surenZorla) return suren;
      try {
        await suren;
      } catch (_) {
        // Süren turun hatası onu çağıranındır.
      }
      return refreshPrices(force: force, nabiz: nabiz);
    }
    final tur = _tur(force: zorla);
    _suren = tur;
    _surenZorla = zorla;
    try {
      await tur;
    } finally {
      if (identical(_suren, tur)) _suren = null;
    }
  }

  Future<void> _tur({required bool force}) async {
    final built = await future;
    final s = state.valueOrNull ?? built;
    if (s.assets.isEmpty) return;
    state = AsyncData(s.copyWith(isLoading: true, clearError: true));
    try {
      state = AsyncData(await _fiyatla(state.valueOrNull ?? s, force: force));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'DemoPortfolioNotifier.refreshPrices');
      final current = state.valueOrNull ?? s;
      state = AsyncData(current.copyWith(
        isLoading: false,
        errorMessage: 'Fiyatlar güncellenemedi. ${friendlyError(e)}',
      ));
    }
  }

  // Bekleme yardımcıları gerçek sürümde özel `_surenTur` alanını okur;
  // demo turu kendi alanında yaşadığı için aynı sözleşme burada kurulur.
  @override
  Future<void> fiyatTurunuBekle({Duration enFazla = TazelikRitmi.yuzey}) =>
      TazelikRitmi.turuBekle(_suren, enFazla: enFazla);

  @override
  Future<void> fiyatTurunuVeKareyiBekle(
          {Duration enFazla = TazelikRitmi.yuzey}) =>
      TazelikRitmi.turuVeKareyiBekle(_suren, enFazla: enFazla);

  @override
  bool get fiyatTuruSuruyor => _suren != null;

  @override
  Future<void> acilisTazele() => _suren ?? refreshPrices();

  // ---- Yazma: hepsi durur ---------------------------------------------------

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
    String? sozlesmeId,
  }) async =>
      DemoModu.yazmaEngeli('varlik_ekle');

  @override
  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
    DateTime? addedDate,
  }) async =>
      DemoModu.yazmaEngeli('satis');

  @override
  Future<void> addDividend({
    required Asset asset,
    required double amount,
    DateTime? paidAt,
  }) async =>
      DemoModu.yazmaEngeli('temettu');

  @override
  Future<void> updateAsset(Asset asset) async =>
      DemoModu.yazmaEngeli('varlik_duzenle');

  @override
  Future<void> updateNotes(Asset asset, String notes) async =>
      DemoModu.yazmaEngeli('not');

  @override
  Future<void> deleteAsset(String id) async => DemoModu.yazmaEngeli('sil');

  @override
  Future<SilinenPozisyon?> deletePositionLots(List<Asset> lots) async =>
      DemoModu.yazmaEngeli('sil');

  @override
  Future<void> restorePositionLots(SilinenPozisyon kayit) async =>
      DemoModu.yazmaEngeli('sil');

  @override
  Future<void> updateManualPrice(Asset asset, double price) async =>
      DemoModu.yazmaEngeli('fiyat');

  /// Anlık görüntüler sunucuda; demo defterinin geçmişi yok.
  @override
  Future<List<({int ts, Map<String, double> values})>> fetchSnapshots(
          int sinceMs) async =>
      const [];
}

// ── Ortaklık ────────────────────────────────────────────────────────────────

/// Ortak yok. Gerçek sürüm `build`'de 30 sn'lik yoklama ve yaşam döngüsü
/// gözlemcisi kurar; burada ikisi de kurulmaz.
class _DemoPartners extends PartnersNotifier {
  @override
  Future<List<PartnerAccount>> build() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<({String inviteId, String partnerName})> submitCode(
          String code) async =>
      DemoModu.yazmaEngeli('ortak');

  @override
  Future<void> acceptInvite(String inviteId) async =>
      DemoModu.yazmaEngeli('ortak');

  @override
  Future<void> rejectInvite(String inviteId) async =>
      DemoModu.yazmaEngeli('ortak');

  @override
  Future<void> toggleHidden(String partnerId, bool hidden) async =>
      DemoModu.yazmaEngeli('ortak');

  @override
  Future<void> removePartner(String partnerId) async =>
      DemoModu.yazmaEngeli('ortak');
}

class _DemoPartnerAssets extends PartnerAssetsNotifier {
  @override
  Future<Map<String, List<Asset>>> build() async => const {};

  @override
  Future<void> reload() async => state = const AsyncData({});
}

class _DemoPendingInvites extends PendingInvitesNotifier {
  @override
  Future<List<Map<String, dynamic>>> build() async => const [];

  @override
  Future<void> refresh() async {}
}

// ── Bildirimler ─────────────────────────────────────────────────────────────

/// Sinyal, alarm bildirimi ve genel bildirim listeleri BOŞ. Boş listede
/// kapatma/silme eylemleri zaten hedef bulmaz; gerçek sürümleri yine de
/// sunucuya gittiği için sessiz no-op'a çevrilir (sayfa açtırmak, boş
/// listeye "temizle" diyen kullanıcıya anlamsız gelirdi).
class _DemoSignals extends SignalNotifier {
  @override
  Future<List<SignalAlert>> build() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> analyzePortfolio(List<Asset> assets,
      {String slot = 'manual'}) async {}

  @override
  Future<void> dismiss(String id) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dismissAll() async {}

  @override
  Future<void> deleteHistory() async {}

  @override
  Future<void> deleteAll() async {}
}

class _DemoPriceAlertNotifications extends PriceAlertNotificationNotifier {
  @override
  Future<List<PriceAlertNotification>> build() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dismiss(String id) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dismissAll() async {}

  @override
  Future<void> deleteHistory() async {}

  @override
  Future<void> deleteAll() async {}
}

class _DemoAppNotifications extends AppNotificationNotifier {
  @override
  Future<List<AppNotification>> build() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dismiss(String id) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dismissAll() async {}

  @override
  Future<void> deleteHistory() async {}

  @override
  Future<void> deleteAll() async {}
}

// ── Alarm, takip, sessiz saatler ─────────────────────────────────────────────

class _DemoPriceAlerts extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => const [];

  @override
  Future<void> refresh() async {}

  @override
  Future<PriceAlert> create(PriceAlert alarm) async =>
      DemoModu.yazmaEngeli('alarm');

  @override
  Future<void> delete(String id) async => DemoModu.yazmaEngeli('alarm');

  @override
  Future<void> rearm(String id) async => DemoModu.yazmaEngeli('alarm');
}

class _DemoWatchlist extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => const [];

  @override
  Future<void> add(WatchlistItem item) async => DemoModu.yazmaEngeli('takip');

  @override
  Future<void> remove(String id) async => DemoModu.yazmaEngeli('takip');
}

class _DemoQuietHours extends QuietHoursNotifier {
  @override
  Future<QuietHours> build() async => const QuietHours();

  @override
  Future<void> set({int? start, int? end}) async =>
      DemoModu.yazmaEngeli('ayarlar');
}
