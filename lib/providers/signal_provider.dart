import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/asset.dart';
import '../models/signal_alert.dart';
import '../models/technical_signal.dart';
import '../services/technical_analysis_service.dart';
import '../services/notification_service.dart';

// Aktif sinyal listesi — sadece AL veya SAT olanlar
class SignalNotifier extends Notifier<List<SignalAlert>> {
  @override
  List<SignalAlert> build() => [];

  /// Verilen varlık listesini analiz eder, güçlü sinyal (3+/5) olanları
  /// state'e yazar ve push notification gönderir.
  Future<void> analyzePortfolio(List<Asset> assets) async {
    if (assets.isEmpty) return;

    final newAlerts = <SignalAlert>[];

    for (final asset in assets) {
      final indicators = TechnicalAnalysisService.analyze(asset, []);
      final summary = TechnicalAnalysisService.summarize(indicators);
      if (summary.signal == SignalType.neutral) continue;

      newAlerts.add(SignalAlert(
        assetId: asset.id,
        assetName: asset.name,
        assetTicker: asset.ticker,
        signal: summary.signal,
        buyCount: summary.buyCount,
        sellCount: summary.sellCount,
        confidence: summary.confidence,
        detectedAt: DateTime.now(),
      ));
    }

    // Önceki listeden farklı olan (yeni veya değişen) sinyalleri bul
    final previous = state;
    for (final alert in newAlerts) {
      final prev = previous.where((a) => a.assetId == alert.assetId).firstOrNull;
      // Yeni sinyal veya öncekinden farklı yön → bildirim gönder
      if (prev == null || prev.signal != alert.signal) {
        await NotificationService.instance.sendSignalNotification(
          assetName: alert.assetName,
          ticker: alert.assetTicker,
          signal: alert.signal,
          buyCount: alert.buyCount,
          sellCount: alert.sellCount,
        );
      }
    }

    state = newAlerts;
  }

  void dismiss(String assetId) {
    state = state.where((a) => a.assetId != assetId).toList();
  }

  void dismissAll() => state = [];
}

final signalProvider = NotifierProvider<SignalNotifier, List<SignalAlert>>(
  SignalNotifier.new,
);
