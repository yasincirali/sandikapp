import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/asset.dart';
import '../services/history_service.dart';

/// Zoom-aware grafik veri controller'ı.
///
/// Grafik viewport'u değiştiğinde çağıran `updateViewport(from, to)` diyerek
/// controller'a bildirir. Controller uygun `ResolutionTier`'ı seçer, debounce
/// eder ve yeni veri yüklenince notify eder. Eski veri set'i yeni geldiğinde
/// silinene kadar ekranda kalır — flicker olmaz.
class ZoomDataController extends ChangeNotifier {
  ZoomDataController({
    required this.assets,
    required this.initialFrom,
    required this.initialTo,
    this.simulate = false,
  }) {
    _from = initialFrom;
    _to = initialTo;
    _tier = ResolutionTierMeta.pickForSpan(_spanDays());
    // İlk yüklemeyi tetikle
    _reload(immediate: true);
  }

  final List<Asset> assets;
  final DateTime initialFrom;
  final DateTime initialTo;
  final bool simulate;

  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();
  ResolutionTier _tier = ResolutionTier.daily;

  Map<int, double> _data = const {};
  bool _loading = false;
  int _requestSeq = 0;
  Timer? _debounce;

  Map<int, double> get data => _data;
  bool get loading => _loading;
  ResolutionTier get tier => _tier;
  DateTime get from => _from;
  DateTime get to => _to;

  double _spanDays() =>
      _to.difference(_from).inMinutes / (60.0 * 24.0);

  /// Chart viewport değiştiğinde çağır. [from]/[to] gerçek tarih değerleri.
  /// Debounce 220ms — pinch/pan sırasında spam istek atmaz.
  void updateViewport(DateTime from, DateTime to) {
    _from = from;
    _to = to;
    final newTier = ResolutionTierMeta.pickForSpan(_spanDays());
    // Tier değişmediyse ve _data zaten viewport'u kapsıyorsa reload etme —
    // pan sırasında Y-fit içinde gezmek yeni istek gerektirmez.
    if (newTier == _tier && _dataCoversViewport()) {
      notifyListeners();
      return;
    }
    _tier = newTier;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _reload();
    });
  }

  bool _dataCoversViewport() {
    if (_data.isEmpty) return false;
    final keys = _data.keys.toList()..sort();
    final dataMin = keys.first;
    final dataMax = keys.last;
    return dataMin <= _from.millisecondsSinceEpoch &&
        dataMax >= _to.millisecondsSinceEpoch - 60 * 1000;
  }

  Future<void> _reload({bool immediate = false}) async {
    final mySeq = ++_requestSeq;
    if (!_loading) {
      _loading = true;
      notifyListeners();
    }
    try {
      final result =
          await HistoryService.instance.getPortfolioHistoryAtResolution(
        assets: assets,
        from: _from,
        to: _to,
        tier: _tier,
        simulate: simulate,
      );
      // Sıra numarası eşleşmezse (viewport arada değişti) bu sonucu at.
      if (mySeq != _requestSeq) return;
      _data = result;
    } catch (_) {
      // sessizce yok say — eski veri ekranda kalır
    } finally {
      if (mySeq == _requestSeq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
