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
    Map<int, double> seedData = const {},
  }) {
    _from = initialFrom;
    _to = initialTo;
    _tier = ResolutionTierMeta.pickForSpan(_spanDays());
    // Filtre değişiminde önceki controller'ın verisi tohum olarak gelir.
    // Yeni seri hazır olana kadar ekranda soluk şekilde eski grafik durur;
    // böylece "veri yok" hâli oluşmaz ve tam sayfa spinner'a düşülmez.
    // Bu veri BAŞKA bir filtreye ait — sadece geçici görsel süreklilik
    // içindir, ilk gerçek sonuç geldiğinde tamamen değişir.
    _data = seedData;
    _recomputeDataBounds();
    _stale = seedData.isNotEmpty;
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
  /// `_data` başka bir filtreden devralınan tohum veri mi? Doğruysa grafik
  /// gösterilir ama "bu henüz seçtiğin filtrenin verisi değil" diye soluk
  /// çizilir ve sayısal özetler (toplam/PnL) buna göre gizlenebilir.
  bool _stale = false;
  int _requestSeq = 0;
  Timer? _debounce;
  // Yükleme durumunu geciktiren timer — dispose'da iptal edilmeli, aksi
  // halde widget ağaçtan kalktıktan sonra notifyListeners() çağırıp
  // "disposed ChangeNotifier" hatası fırlatır.
  Timer? _graceTimer;
  bool _disposed = false;

  Map<int, double> get data => _data;
  bool get loading => _loading;

  /// Ekrandaki veri devralınan tohum mu (henüz bu filtrenin gerçek sonucu
  /// gelmedi mi)?
  bool get stale => _stale;
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

  // `_data`nın min/max zaman damgası. Her viewport değişiminde tüm
  // anahtarları sıralamak (pan sırasında saniyede onlarca kez) gereksizdi —
  // veri değişmediği sürece sınırlar da değişmez. `_data` her atandığında
  // bir kez hesaplanır.
  int _dataMinTs = 0;
  int _dataMaxTs = -1;

  void _recomputeDataBounds() {
    if (_data.isEmpty) {
      _dataMinTs = 0;
      _dataMaxTs = -1;
      return;
    }
    int lo = _data.keys.first;
    int hi = lo;
    for (final k in _data.keys) {
      if (k < lo) lo = k;
      if (k > hi) hi = k;
    }
    _dataMinTs = lo;
    _dataMaxTs = hi;
  }

  bool _dataCoversViewport() {
    if (_data.isEmpty) return false;
    return _dataMinTs <= _from.millisecondsSinceEpoch &&
        _dataMaxTs >= _to.millisecondsSinceEpoch - 60 * 1000;
  }

  Future<void> _reload({bool immediate = false}) async {
    final mySeq = ++_requestSeq;
    // `_loading`i HEMEN true yapıp notify etmiyoruz. Fiyat serileri
    // `HistoryService._tierCache` içinde önbelleklendiği için istek çoğu
    // zaman aynı karede (mikro-görev) döner; önce "yükleniyor" yayınlamak
    // görünür bir spinner çakması üretiyordu. Bunun yerine kısa bir gecikme
    // sonrası hâlâ bitmediyse yükleme durumunu duyuruyoruz.
    _graceTimer?.cancel();
    final graceTimer = Timer(const Duration(milliseconds: 120), () {
      if (_disposed || mySeq != _requestSeq) return;
      if (!_loading) {
        _loading = true;
        notifyListeners();
      }
    });
    _graceTimer = graceTimer;
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
      _recomputeDataBounds();
      _stale = false;
    } catch (_) {
      // sessizce yok say — eski veri ekranda kalır
    } finally {
      graceTimer.cancel();
      // `await`ten sonra buradayız — controller bu arada dispose edilmiş
      // olabilir (filtre değişiminde eski controller atılıyor). Dispose
      // sonrası notifyListeners() exception fırlatır.
      if (!_disposed && mySeq == _requestSeq) {
        _loading = false;
        // Grace timer "yükleniyor" duyurmuş olsa da olmasa da tek notify
        // yeterli: ya spinner'ı kapatır ya da yeni veriyi yayınlar.
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _graceTimer?.cancel();
    super.dispose();
  }
}
