/// Grafik üzerindeki işaret noktalarının (alım/satım dot'ları) birbirine
/// yapışmasını engelleyen yardımcı.
///
/// Sorun: `checkToShowDot` gün bazlı çalıştığı için arka arkaya yapılan
/// alımlarda her noktaya ~9px genişliğinde (yarıçap + beyaz halka) bir dot
/// çizilir. Noktalar birkaç piksel arayla düştüğünde üst üste binip tek bir
/// yığın/leke gibi görünür.
///
/// Çözüm: dot'ları **piksel uzaklığına** göre seyrelt. Aday X değerleri sıralı
/// gezilir; bir öncekiyle arasındaki mesafe [minSeparationPx] altındaysa aday
/// atlanır. Zoom yapıldıkça viewport daralır, aynı noktalar birbirinden
/// uzaklaşır ve daha fazlası görünür hale gelir — TradingView davranışı.
class DotThinner {
  /// Görünür kalan X değerleri. `checkToShowDot` içinde O(1) sorgulanır.
  final Set<double> _visible;

  const DotThinner._(this._visible);

  /// [candidates] işaretlenmek istenen tüm X değerleri (sıralı olmak zorunda
  /// değil). [viewMinX]/[viewMaxX] o anki viewport, [plotWidthPx] grafiğin
  /// piksel genişliği. Viewport dışındaki adaylar elenir.
  ///
  /// [alwaysKeep] içindeki X'ler mesafeye bakılmaksızın korunur (ilk nokta,
  /// "şimdi" noktası gibi anlamı olan işaretler).
  factory DotThinner.build({
    required Iterable<double> candidates,
    required double viewMinX,
    required double viewMaxX,
    double plotWidthPx = 340,
    double minSeparationPx = 14,
    Set<double> alwaysKeep = const {},
  }) {
    final span = viewMaxX - viewMinX;
    if (span <= 0 || plotWidthPx <= 0) {
      return DotThinner._({...candidates, ...alwaysKeep});
    }

    // Piksel eşiğini veri birimine çevir — tek karşılaştırma yeter.
    final minSeparationData = minSeparationPx / plotWidthPx * span;

    final inView = candidates
        .where((x) => x >= viewMinX && x <= viewMaxX)
        .toList()
      ..sort();

    final kept = <double>{...alwaysKeep};
    double? lastKeptX;

    // Korunması zorunlu noktalar da mesafe hesabına dahil olmalı; aksi halde
    // bir alım dot'u "şimdi" dot'unun üstüne binebilir.
    final anchors = alwaysKeep.where((x) => x >= viewMinX && x <= viewMaxX).toList()
      ..sort();

    bool tooCloseToAnchor(double x) {
      for (final a in anchors) {
        if ((x - a).abs() < minSeparationData) return true;
      }
      return false;
    }

    for (final x in inView) {
      if (kept.contains(x)) continue;
      if (tooCloseToAnchor(x)) continue;
      if (lastKeptX != null && (x - lastKeptX) < minSeparationData) continue;
      kept.add(x);
      lastKeptX = x;
    }

    return DotThinner._(kept);
  }

  /// Bu X değerinde dot çizilmeli mi?
  bool shows(double x) => _visible.contains(x);

  /// Seyreltme sonrası görünen dot sayısı.
  int get visibleCount => _visible.length;
}
