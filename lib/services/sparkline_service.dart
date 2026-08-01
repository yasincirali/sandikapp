import 'package:flutter/foundation.dart';

import '../models/asset.dart';
import '../models/asset_type.dart';
import 'price_service.dart';

/// Varlık satırlarındaki mini trend grafiği (sparkline) için tek-sembol
/// fiyat serisi sağlar.
///
/// [HistoryService] portföyün TOPLAM değerini hesaplar (tüm lot'lar × miktar
/// × kur). Sparkline'ın ihtiyacı bambaşka: tek bir sembolün normalize edilmiş
/// fiyat eğrisi. Miktar ve maliyet bilinçli olarak hesaba katılmaz — satırda
/// zaten tutar ve yüzde yazıyor; grafiğin işi yalnızca "hangi yöne, ne kadar
/// dalgalanarak gitti" sorusunu cevaplamak.
///
/// Neden ayrı servis: [HistoryService] agresif biçimde portföy-toplamı
/// odaklı (grid üretimi, signed quantity, outlier smoothing). Tek sembol için
/// o makineyi çalıştırmak hem gereksiz hem yanıltıcı olurdu.
class SparklineService {
  static final SparklineService instance = SparklineService._();
  SparklineService._();

  /// Sparkline penceresi — 1 ay, günlük kapanış (~22 nokta).
  ///
  /// 30 nokta 60px genişlikte okunabilir bir eğri verir; daha uzun dönem
  /// (1y/haftalık) satır ölçeğinde düz çizgiye dönüşüyor, daha kısası
  /// (5d/saatlik) gürültüyü trend gibi gösteriyor.
  static const String _range = '1mo';

  /// sembol → normalize edilmiş seri. Uygulama ömrü boyunca tutulur:
  /// günlük kapanış verisi gün içinde değişmez, liste her kaydırmada
  /// yeniden fetch etmemeli.
  final Map<String, List<double>> _cache = {};

  /// Aynı sembol için uçuşan istekleri tekilleştirir — 20 satırlık listede
  /// aynı ticker birden çok pozisyonda geçebilir.
  final Map<String, Future<List<double>>> _inflight = {};

  /// Bu sembol için sparkline çizilebilir mi?
  ///
  /// Manuel fiyatlı varlıklar (kullanıcının elle girdiği "Ev", "Araba") ve
  /// ticker'ı olmayanlar için geçmiş seri yoktur — çağıran bunlarda grafik
  /// alanını hiç ayırmamalı.
  static bool supports(Asset a) {
    if (a.isManualPrice) return false;
    if (a.type == AssetType.altin) return true;
    if (a.ticker.trim().isEmpty) return false;
    return a.type == AssetType.hisse ||
        a.type == AssetType.emtia ||
        a.type == AssetType.doviz ||
        a.type == AssetType.fon;
  }

  /// Yahoo/TEFAS sembolü. Altın iç sembolleri (`ALTIN_GRAM` vb.) gerçek bir
  /// enstrüman değil; hepsi aynı ons eğrisini (GC=F) takip eder — ağırlık
  /// çarpanı eğrinin ŞEKLİNİ değiştirmediği için normalize edilmiş
  /// sparkline'da çarpan uygulamaya gerek yok.
  static String? _symbolFor(Asset a) {
    if (a.type == AssetType.altin) return 'GC=F';
    final t = a.ticker.trim();
    return t.isEmpty ? null : t;
  }

  /// [asset] için 0..1 aralığına normalize edilmiş fiyat serisi döner.
  ///
  /// Normalizasyon burada yapılır (widget'ta değil): çizim katmanı ham TRY
  /// değerleriyle uğraşmamalı, min/max'ı her build'de yeniden hesaplamamalı.
  /// Seri düz ise (min == max) tüm noktalar 0.5 olur → ortada yatay çizgi.
  ///
  /// Veri yoksa veya çizmeye yetmiyorsa boş liste döner.
  Future<List<double>> seriesFor(Asset asset) async {
    final symbol = _symbolFor(asset);
    if (symbol == null) return const [];

    final cached = _cache[symbol];
    if (cached != null) return cached;

    final pending = _inflight[symbol];
    if (pending != null) return pending;

    final future = _fetch(symbol);
    _inflight[symbol] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(symbol);
    }
  }

  Future<List<double>> _fetch(String symbol) async {
    try {
      final raw = await PriceService.instance.fetchHistory(symbol, _range);
      final series = normalize(raw);
      // Boş sonucu da cache'le: 404 veren sembol için her kaydırmada
      // yeniden ağa çıkmanın anlamı yok.
      _cache[symbol] = series;
      return series;
    } catch (e) {
      if (kDebugMode) debugPrint('[Sparkline] $symbol başarısız: $e');
      _cache[symbol] = const [];
      return const [];
    }
  }

  /// Ham (ts, price) noktalarını 0..1 aralığına indirger.
  ///
  /// İki noktadan az seri çizilemez — tek nokta "trend" değildir.
  ///
  /// Saf fonksiyon (ağ/state yok) — doğrudan test edilir.
  @visibleForTesting
  static List<double> normalize(List<(int, double)> points) {
    if (points.length < 2) return const [];

    final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    final values = [
      for (final p in sorted)
        if (p.$2 > 0) p.$2
    ];
    if (values.length < 2) return const [];

    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }

    final span = max - min;
    // Tamamen düz seri (sabit kur, işlem görmeyen fon) — ortada düz çizgi.
    if (span <= 0) return List<double>.filled(values.length, 0.5);

    return [for (final v in values) (v - min) / span];
  }

  /// Fiyatlar yenilendiğinde çağrılır — ertesi gün kapanışları gelsin diye.
  void clear() {
    _cache.clear();
    _inflight.clear();
  }
}
