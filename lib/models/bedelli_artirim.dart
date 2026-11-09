import 'asset.dart';
import 'asset_type.dart';

/// Bedelli sermaye artırımı: rüçhan hakkını kullanan yatırımcının yeni
/// lotları (Ar-Ge 2026-11-07 16:06#1, müşteri raporu 16:30 YAP 1).
///
/// ## Neden normal alış lotu
/// Bedelli artırımda yeni pay nominal değerden (1 ₺) alınır. Uygulama bunu
/// bilmeyince adet eksik, ortalama maliyet yüksek kalıyordu; kullanıcı
/// "1 ₺'den alış" diye elle hesaplıyordu. Kayıt mevcut alış yoluyla
/// (`PortfolioNotifier.addAsset`) yazılır: sunucu değişmez, eski sürüm
/// lotu sıradan bir alış olarak okur, geçmiş defter bozulmaz. Ayrı hareket
/// türü eski istemcide bilinmeyen tür olurdu.
///
/// ## Neden aşağı yuvarlama
/// Kesirli hak lot olmaz: 125 lotta %10 → 12,5 hak, aracı kurum 12 lot
/// verir (kesir hak olarak satılır ya da düşer). Yuvarlama sessiz değildir,
/// sayfa "12,5 hakkın 12'si lot olur" diye yazar.
///
/// ## Uydurma sayı yok
/// Oran ve tarih kullanıcıdan; 1 ₺ nominal yasal sabittir (BIST payları
/// 1 ₺ nominal). Eldeki lot defterden, o günün sonundaki adettir.
class BedelliArtirim {
  const BedelliArtirim._({
    required this.eldekiLot,
    required this.hakSayisi,
    required this.yeniLot,
  });

  /// BIST payının nominal değeri, lot başı ödenen tutar.
  static const double nominal = 1.0;

  /// Kayıt tarihinde elde tutulan adet (alış − satış, o günün sonunda).
  final double eldekiLot;

  /// Yuvarlanmamış hak: `eldekiLot × oran / 100`.
  final double hakSayisi;

  /// Kaydedilecek yeni lot sayısı — [hakSayisi]'nın tam kısmı.
  final int yeniLot;

  /// Ödenen toplam tutar (₺).
  double get toplamTutar => yeniLot * nominal;

  /// Hak kesirliydi ve aşağı yuvarlandı mı (sayfa bunu satırda yazar).
  bool get yuvarlandi => hakSayisi - yeniLot > _kayanNoktaPayi;

  /// Kaydedilebilir mi: en az bir yeni lot.
  bool get kaydedilebilir => yeniLot > 0;

  /// `120 × 100 / 100` gibi tam sonuçlar kayan noktada 119,99999 çıkabilir;
  /// aşağı yuvarlama o payı tam sayıya bağışlar.
  static const double _kayanNoktaPayi = 1e-9;

  /// Hesap. [oranYuzde] `null`/≤0 ya da tarihte lot yoksa da sonuç döner
  /// (`yeniLot == 0`), sayfa düğmeyi kapalı tutar.
  ///
  /// [lotlar] pozisyonun defter satırları (alış, satış, temettü); silinmiş
  /// satır sayılmaz. Tarih gün hassasiyetlidir: o günün içindeki her alış
  /// ve satış sayılır (hak, kayıt günü sonundaki paya doğar).
  static BedelliArtirim hesapla({
    required Iterable<Asset> lotlar,
    required double? oranYuzde,
    required DateTime tarih,
  }) {
    final gunSonu = DateTime(tarih.year, tarih.month, tarih.day + 1);
    var elde = 0.0;
    for (final l in lotlar) {
      if (!l.isActive || !l.addedDate.isBefore(gunSonu)) continue;
      if (l.isBuy) elde += l.quantity;
      if (l.isSell) elde -= l.quantity;
    }
    if (elde < 0) elde = 0;
    final oran = (oranYuzde ?? 0) > 0 ? oranYuzde! : 0.0;
    final hak = elde * oran / 100;
    final yeni = (hak + _kayanNoktaPayi).floor();
    return BedelliArtirim._(eldekiLot: elde, hakSayisi: hak, yeniLot: yeni);
  }

  /// Bedelli artırım yalnız BIST hissesinde anlamlı: ABD hissesinde rüçhan
  /// TL nominaliyle işlemez, endeks bir pay değildir.
  static bool uygunMu(Asset varlik) =>
      varlik.type == AssetType.hisse &&
      !varlik.abdHissesi &&
      !bistEndeksiMi(varlik.ticker);
}
