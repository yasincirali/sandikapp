import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
import '../services/analytics_service.dart';
import '../services/history_service.dart';
import '../services/supabase_service.dart';
import '../services/technical_analysis_service.dart';
import 'auth_provider.dart';
import 'preferences_provider.dart';

/// Supabase `signal_notifications` tablosunun state'i.
///
/// - `analyzePortfolio`: kullanıcının varlıklarını göstergelerle analiz eder,
///   confidence eşiğini geçenler için (asset tipi başına) yeni satır yazar.
/// - De-dup: aynı asset için son sinyal ile aynıysa yeniden atılmaz.
/// - `dismiss` / `delete`: kullanıcı sildiğinde dismissed_at set edilir /
///   kalıcı silinir. Statü değişmedikçe yeniden push atılmaz.
class SignalNotifier extends AsyncNotifier<List<SignalAlert>> {
  @override
  Future<List<SignalAlert>> build() async {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const [];
    try {
      return await SupabaseService.instance
          .fetchSignalNotifications(userId: user.id);
    } catch (_) {
      return const [];
    }
  }

  Future<void> refresh() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    state = const AsyncLoading();
    try {
      final list = await SupabaseService.instance
          .fetchSignalNotifications(userId: user.id);
      state = AsyncData(list);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// Kullanıcının portföyünü analiz et; eşiği geçen ve önceki sinyalden
  /// farklı olan her varlık için yeni bildirim yazar + push gönderir.
  ///
  /// [slot] analytics için: 'morning' (TR 11:00), 'afternoon' (TR 15:00),
  /// 'manual' (kullanıcı tetikli), 'startup' (uygulama açılışı — nadir).
  Future<void> analyzePortfolio(List<Asset> assets, {String slot = 'manual'}) async {
    if (assets.isEmpty) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final indicatorPrefs = ref.read(indicatorPrefsProvider.notifier);
    final thresholds = ref.read(signalThresholdProvider.notifier);
    final neutralPushEnabled = ref.read(signalNeutralPushProvider);
    final premium = ref.read(premiumUnlockedProvider);

    final inserted = <SignalAlert>[];

    for (final asset in assets) {
      // Vadeli mevduatın teknik göstergesi yoktur — sinyal üretmez.
      if (asset.type == AssetType.mevduat) continue;
      final enabledIds = indicatorPrefs.forType(asset.type);
      if (enabledIds.isEmpty) continue;

      // GERÇEK fiyat geçmişi şart. Boş liste verilirse
      // `TechnicalAnalysisService.analyze` `_simulate()`'e düşer ve `Random`
      // ile UYDURMA fiyat üretir — bu yol sinyali DB'ye yazdığı için
      // kullanıcıya sahte bir "AL/SAT" gösterirdi. Sunucu tarafı bu tuzağı
      // zaten kapatmış durumda (yeterli veri yoksa varlığı atlar).
      final priceMap = await HistoryService.instance
          .getSymbolHistory(asset.ticker, periodDays: 180)
          .catchError((_) => <int, double>{});
      final sortedTs = priceMap.keys.toList()..sort();
      final prices = [for (final t in sortedTs) priceMap[t]!];
      // Göstergelerin çoğu 20-26 nokta ister; 30 altı güvenilir değil.
      if (prices.length < 30) continue;

      final indicators = TechnicalAnalysisService.analyze(
        asset,
        prices,
        enabledIds: enabledIds,
        premiumUnlocked: premium,
      );
      if (indicators.isEmpty) continue;

      final summary = TechnicalAnalysisService.summarize(indicators);
      final threshold = thresholds.forType(asset.type);

      // Neutral push kapalıysa neutral sinyalleri es geç.
      if (summary.signal == SignalType.neutral && !neutralPushEnabled) continue;
      // Confidence eşiği: 0-100 arası. Threshold'un altında kalıyorsa skip.
      if (summary.confidence < threshold) continue;

      // De-dup: aynı asset için en son sinyalle aynıysa skip.
      SignalAlert? last;
      try {
        last = await SupabaseService.instance.fetchLastSignalForAsset(
          userId: user.id,
          assetId: asset.id,
        );
      } catch (_) {}
      if (last != null && last.signal == summary.signal) continue;

      final alert = SignalAlert(
        assetId: asset.id,
        assetName: asset.name,
        assetTicker: asset.ticker,
        assetType: asset.type,
        signal: summary.signal,
        buyCount: summary.buyCount,
        sellCount: summary.sellCount,
        confidence: summary.confidence,
        detectedAt: DateTime.now(),
      );

      try {
        final saved = await SupabaseService.instance.insertSignalNotification(
          userId: user.id,
          alert: alert,
        );
        inserted.add(saved);

        AnalyticsService.instance.logSignalReceived(
          ticker: asset.ticker,
          action: summary.signal.name,
          confidence: summary.confidence,
          slot: slot,
        );

        // NOT: burada artık local notification GÖNDERİLMEZ.
        //
        // Sinyal push'u sunucu tarafında üretiliyor (`analyze-signals` edge
        // function → FCM `notification` payload). Client de ayrıca local
        // bildirim gösterirse kullanıcı aynı sinyal için İKİ bildirim alır.
        //
        // Bu fonksiyon yine de değerli: kullanıcı uygulamayı açtığında
        // portföyü anında analiz eder ve uygulama içi bildirim listesini
        // (`signal_notifications`) günceller — sunucunun bir sonraki
        // turunu beklemeden.
      } catch (_) {}
    }

    if (inserted.isNotEmpty) {
      final current = state.valueOrNull ?? const [];
      state = AsyncData([...inserted, ...current]);
    }
  }

  /// Kullanıcı bildirim geçmişinden bir kaydı sildi.
  /// Statü değişmedikçe yeniden push atılmaz.
  ///
  /// **İyimser (optimistic) güncelleme + geri alma.** Satır önce ekrandan
  /// düşer (dokunma anında tepki), sunucu reddederse GERİ GELİR ve hata
  /// fırlatılır — çağıran kullanıcıya söyleyebilsin.
  ///
  /// Eskiden `catch (_) {}` ile hata yutuluyor, ardından state yine de
  /// "silindi" olarak yazılıyordu: sunucuda silinmemiş bir kayıt ekranda
  /// silinmiş görünüyor, uygulama yeniden açılınca geri geliyordu.
  /// Kullanıcının "silmiyor" dediği davranış buydu — sessiz başarısızlık.
  Future<void> dismiss(String id) async {
    final current = state.valueOrNull ?? const [];
    final alert = current.where((a) => a.id == id).firstOrNull;
    if (alert != null) {
      AnalyticsService.instance
          .logSignalDismissed(ticker: alert.assetTicker);
    }

    // İyimser: önce ekrandan düş.
    state = AsyncData([
      for (final a in current)
        if (a.id == id) a.copyWith(dismissedAt: DateTime.now()) else a,
    ]);

    try {
      await SupabaseService.instance.dismissSignalNotification(id);
    } catch (e) {
      // Sunucu reddetti — ekranı ESKİ haline al, yalan söyleme.
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Kalıcı sil (kullanıcı long-press veya delete ile).
  ///
  /// [dismiss] ile aynı iyimser + geri alma sözleşmesi.
  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? const [];
    state = AsyncData(current.where((a) => a.id != id).toList());
    try {
      await SupabaseService.instance.deleteSignalNotification(id);
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// Tümünü dismiss et (bell sheet'teki "Tümünü sil" butonu için).
  ///
  /// **Kısmi başarı diye bir şey YOK.** Herhangi biri başarısız olursa tüm
  /// liste eski haline döner ve hata fırlatılır. Eskiden her satır ayrı
  /// `try/catch` içindeydi ve hepsi yutuluyordu: yarısı silinip yarısı
  /// kalabiliyor, ekran ise hepsini silinmiş gösteriyordu.
  Future<void> dismissAll() async {
    final current = state.valueOrNull ?? const [];
    final active =
        current.where((a) => !a.isDismissed && a.id != null).toList();
    if (active.isEmpty) return;

    state = AsyncData([
      for (final a in current)
        if (!a.isDismissed) a.copyWith(dismissedAt: DateTime.now()) else a,
    ]);

    try {
      // Sırayla değil TOPLU: N satır için N istek atmak yavaş ve yarıda
      // kesilmeye açıktı.
      await SupabaseService.instance
          .dismissSignalNotifications([for (final a in active) a.id!]);
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// GEÇMİŞTEKİ kayıtları KALICI siler.
  ///
  /// [dismissAll]'dan farkı: o yalnızca `dismissed_at` damgalar ve kayıtlar
  /// GEÇMİŞ bölümünde durmaya devam eder. Bu metot satırları tamamen kaldırır
  /// — kullanıcı "tümünü temizle" dedikten sonra listenin gerçekten boşalmasını
  /// bekliyordu (kullanıcı isteği, 2026-09-01).
  ///
  /// Yalnızca dismissed kayıtları hedefler: aktif (henüz okunmamış) bir sinyali
  /// tek dokunuşla yok etmek sürpriz olurdu. Aktifleri silmek için önce
  /// [dismissAll], sonra bu.
  Future<void> deleteHistory() async {
    final current = state.valueOrNull ?? const [];
    final history =
        current.where((a) => a.isDismissed && a.id != null).toList();
    if (history.isEmpty) return;

    final silinecek = {for (final a in history) a.id!};
    state = AsyncData(
        current.where((a) => a.id == null || !silinecek.contains(a.id)).toList());

    try {
      await SupabaseService.instance
          .deleteSignalNotifications(silinecek.toList());
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }

  /// HEPSİNİ (aktif + geçmiş) kalıcı siler.
  ///
  /// Çanı tamamen boşaltır. En yıkıcı işlem olduğu için çağıran taraf onay
  /// almalıdır.
  Future<void> deleteAll() async {
    final current = state.valueOrNull ?? const [];
    final hepsi = [for (final a in current) if (a.id != null) a.id!];
    if (hepsi.isEmpty) return;

    state = const AsyncData([]);
    try {
      await SupabaseService.instance.deleteSignalNotifications(hepsi);
    } catch (e) {
      state = AsyncData(current);
      rethrow;
    }
  }
}

final signalProvider =
    AsyncNotifierProvider<SignalNotifier, List<SignalAlert>>(
  SignalNotifier.new,
);

/// Bell sheet ve rozet için: sadece dismissed olmayan (aktif) sinyaller.
final activeSignalsProvider = Provider<List<SignalAlert>>((ref) {
  final all = ref.watch(signalProvider).valueOrNull ?? const [];
  return all.where((a) => !a.isDismissed).toList();
});
