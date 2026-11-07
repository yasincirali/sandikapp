import '../services/price_service.dart';
import 'asset.dart';
import 'position.dart';

/// Portföydeki altının toplam gramı ve 24 ayar (has) karşılığı.
///
/// ## Neden (Ar-Ge 7 Kas 18:06 #1, YAP)
/// Altın biriktiren kullanıcı altını TL'den önce gramla düşünür; çeyrek,
/// cumhuriyet, 22 ayar bilezik ve 24 ayar gramı karışık tutan biri "kaç
/// gram altınım var" sorusunu elle hesaplıyordu. Portföy Altın grubunda tek
/// satır cevaplar.
///
/// ## Kurallar
/// - Ağırlık fiyat tablosundan (`PriceService.altinGramKarsiligi`): ekranda
///   görünen gram ile fiyatın çarpanı tek kaynaktan.
/// - Bugünkü mülkiyet sorusu → [aktifLotlar]; satılmış pozisyon girmez.
/// - Tabloda olmayan altın (ons, emtia) sessizce dışarıda kalır; "ons
///   hariç" diye yazılmaz. Hiç gram altın yoksa `null` → satır çizilmez.
/// - Hesap burada, ekranın `build()`'i yalnız sonucu yazar.
class AltinGramOzeti {
  const AltinGramOzeti({required this.gram, required this.has});

  /// Fiziksel ağırlıkların toplamı (ayarı ne olursa olsun).
  final double gram;

  /// Aynı altının saf (24 ayar) altın karşılığı.
  final double has;

  /// Tek sahibin lot defterinden.
  static AltinGramOzeti? hesapla(Iterable<Asset> lotlar) =>
      sahiplerdenHesapla([lotlar]);

  /// Sahip başına defterlerden (Birlikte görünümü). Defterler ayrı ayrı
  /// toplanır: `positionKey` sahip taşımaz, birleştirilirse bir ortağın
  /// satışı ötekinin alımından düşerdi (bkz. `aggregatePositionsByOwner`).
  static AltinGramOzeti? sahiplerdenHesapla(
      Iterable<Iterable<Asset>> defterler) {
    var gram = 0.0;
    var has = 0.0;
    for (final lotlar in defterler) {
      for (final p in aggregatePositions(aktifLotlar(lotlar))) {
        final k = PriceService.altinGramKarsiligi(
            p.representative.ticker.trim(), p.totalQuantity);
        if (k == null) continue;
        gram += k.gram;
        has += k.has;
      }
    }
    if (gram <= 0) return null;
    return AltinGramOzeti(gram: gram, has: has);
  }
}
