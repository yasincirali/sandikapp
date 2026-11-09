import 'asset.dart';
import 'asset_type.dart';
import 'position.dart';

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
    this.yeniOrtalama,
  });

  /// BIST payının nominal değeri, lot başı ödenen tutar.
  static const double nominal = 1.0;

  /// Kayıt tarihinde elde tutulan adet (alış − satış, o günün sonunda).
  final double eldekiLot;

  /// Yuvarlanmamış hak: `eldekiLot × oran / 100`.
  final double hakSayisi;

  /// Kaydedilecek yeni lot sayısı — [hakSayisi]'nın tam kısmı.
  final int yeniLot;

  /// Kayıttan sonra Portföy'ün göstereceği ortalama maliyet (lot başı ₺);
  /// gösterilmeyecekse `null`.
  ///
  /// ## Neden Portföy'ün kendi hesabıyla (müşteri raporu 2026-11-10 #1)
  /// Kullanıcı bedelliyi "ortalamam ne olacak" diye kaydediyor; önizleme
  /// elle `(eski maliyet + yeni lot × 1 ₺) ÷ toplam lot` yazsaydı satıştan
  /// sonra alım olan defterde Portföy'ün yürüyen ortalamasından
  /// (`aggregatePositions`) ayrılabilirdi: sayfa bir sayı, kayıttan sonra
  /// ekran başka sayı. Bu yüzden kaydedilecek lot defterin bir kopyasına
  /// eklenip aynı fonksiyon koşulur; sıradan defterde sonuç yine o formüldür
  /// (120 lot ₺287,50 + %150 → (34.500 + 180) ÷ 300 = ₺115,60).
  ///
  /// `null` (uydurma sayı yok): yeni lot yok, elde lot yok, alışlardan biri
  /// "maliyet sonra" işaretli ya da bugünkü ortalama 0 (maliyet bilinmiyor),
  /// ya da kaydedilecek lot başka bir pozisyona düşüyor (TRY dışı defter).
  final double? yeniOrtalama;

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
  ///
  /// [kayitAni] lotun deftere yazılacağı an (sayfanın `_kayitTarihi`);
  /// [yeniOrtalama] lotu bu ana koyar ki aynı gün sonraki bir satış
  /// Portföy'deki gibi sıralansın. Verilmezse seçilen günün öğlesi.
  static BedelliArtirim hesapla({
    required Iterable<Asset> lotlar,
    required double? oranYuzde,
    required DateTime tarih,
    DateTime? kayitAni,
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
    return BedelliArtirim._(
      eldekiLot: elde,
      hakSayisi: hak,
      yeniLot: yeni,
      yeniOrtalama: elde > 0
          ? _yeniOrtalama(lotlar, yeni,
              kayitAni ?? DateTime(tarih.year, tarih.month, tarih.day, 12))
          : null,
    );
  }

  /// [yeniOrtalama]'nın hesabı: kaydedilecek lotu (sayfanın `addAsset`
  /// çağrısıyla aynı alanlar: TRY, 1 ₺, temsilci lotun sembolü/alt türü)
  /// defterin kopyasına ekler, Portföy'ün `aggregatePositions`'ını koşar.
  static double? _yeniOrtalama(
      Iterable<Asset> lotlar, int yeniLot, DateTime an) {
    if (yeniLot <= 0) return null;
    final defter = lotlar.where((l) => l.isActive).toList();
    final alislar = defter.where((l) => l.isBuy).toList();
    if (alislar.isEmpty || alislar.any((l) => l.maliyetBilinmiyor == true)) {
      return null;
    }
    final ornek = alislar.first;
    final bedelli = Asset(
      id: '_bedelli_onizleme',
      userId: ornek.userId,
      name: ornek.name,
      ticker: ornek.ticker,
      type: ornek.type,
      quantity: yeniLot.toDouble(),
      purchasePrice: nominal,
      currency: 'TRY',
      notes: '',
      subCategory: ornek.subCategory,
      unitType: ornek.unitType,
      addedDate: an,
    );
    final anahtar = positionKey(bedelli);
    Position? bul(List<Asset> l) {
      for (final p in aggregatePositions(l)) {
        if (p.key == anahtar) return p;
      }
      return null;
    }

    // Bugünkü pozisyon bu anahtarda yoksa yeni lot ayrı satıra düşer;
    // "ortalaman şu olur" demek yanlış olurdu.
    final once = bul(defter);
    if (once == null || once.weightedPurchasePrice <= 0) return null;
    final sonra = bul([...defter, bedelli]);
    final ort = sonra?.weightedPurchasePrice;
    return ort != null && ort > 0 ? ort : null;
  }

  /// Bedelli artırım yalnız BIST hissesinde anlamlı: ABD hissesinde rüçhan
  /// TL nominaliyle işlemez, endeks bir pay değildir.
  static bool uygunMu(Asset varlik) =>
      varlik.type == AssetType.hisse &&
      !varlik.abdHissesi &&
      !bistEndeksiMi(varlik.ticker);
}
