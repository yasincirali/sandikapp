import '../models/asset.dart';
import '../models/asset_type.dart';

/// Piyasa kapalı rozetinin metni — portföydeki TÜRLERE göre.
///
/// ## Neden "PİYASA KAPALI" yetmiyor
/// "Piyasa" tek bir şey değil. Kullanıcı bildirimi (2026-09-12):
/// "piyasa kapalı dedik ama fiyatı değişen bir varlık var demek ki."
/// Haklıydı — ölçüldü:
///
///   * **Döviz / emtia / altın** spot piyasaları Pazar akşamı açılıyor;
///     Cumartesi kapalı ama Pazar gecesi hareket var.
///   * **Hisse / fon** BIST ve TEFAS takvimine bağlı — hafta sonu kesin
///     kapalı.
///
/// Hepsine birden "piyasa kapalı" demek, dövizi olan bir kullanıcı için
/// YANLIŞ bilgi. (Vadeli mevduat da bu listedeydi; tür 2026-09-14'te
/// kaldırıldı, kural döviz/emtia/altın için aynen geçerli.) Rozet artık neyin kapalı olduğunu söylüyor.
///
/// ## Neden saf fonksiyon
/// Karar yalnızca türe bakıyor; widget ağacı, tarih ya da ağ gerekmiyor.
/// Ayrı tutmak hafta sonu davranışını platform olmadan test edilebilir
/// kılıyor — bu ekranda tekrar tekrar işe yarayan bir ayrım.

/// Borsa takvimine bağlı türler: hafta sonu ve resmî tatilde KESİN kapalı.
const _borsayaBagli = {AssetType.hisse, AssetType.fon};

/// Kapalı dönemde de değer üretebilen türler.
///
/// Döviz/emtia/altın spot piyasaları hafta sonunun bir kısmında açıktır.
const _kapalidaIsleyebilen = {
  AssetType.doviz,
  AssetType.emtia,
  AssetType.altin,
  // Kripto hiç kapanmaz (7/24). Borsayla karışıksa "diğerleri sürüyor"
  // tam olarak doğru; tek başınaysa kuyruk yalnızca veri gecikmesidir.
  AssetType.kripto,
};

/// Rozet metni. Portföyde hangi türler varsa ona göre daralır.
///
/// [turler] çizime giren varlıkların türleri.
String piyasaKapaliEtiketi(Iterable<AssetType> turler) {
  final set = turler.toSet();

  final borsaVar = set.intersection(_borsayaBagli).isNotEmpty;
  final digerVar = set.intersection(_kapalidaIsleyebilen).isNotEmpty;

  // Yalnızca borsa ürünleri → en net ifade.
  if (borsaVar && !digerVar) return 'BORSA KAPALI';

  // Karışık portföy: "piyasa kapalı" demek spot hareketi yok sayardı.
  // Hangi kolun durduğunu söylüyoruz, tamamının durduğunu değil.
  if (borsaVar && digerVar) return 'BORSA KAPALI · DİĞERLERİ SÜRÜYOR';

  // Borsa ürünü yok — kuyruk zaten yalnızca veri gelmediği için çizildi.
  if (digerVar) return 'SON VERİ';

  return 'PİYASA KAPALI';
}

/// [Asset] listesinden doğrudan etiket üretir.
String piyasaKapaliEtiketiVarliklardan(Iterable<Asset> varliklar) =>
    piyasaKapaliEtiketi(varliklar.map((a) => a.type));
