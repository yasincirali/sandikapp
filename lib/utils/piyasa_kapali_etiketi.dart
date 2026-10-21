import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';

/// "Kapalı" ibaresinin TEK kuralı — hangi portföye söylenebilir?
///
/// ## Karar (kullanıcı, 2026-10-01)
/// "Kripto vs yüzünden altın sürekli değişiyor, kripto da değişiyor;
/// borsa kapalı sadece. Sadece borsadan oluşan portföyü olanlara
/// gösterebiliriz. Bu ifadeyi uygulama genelinde."
///
/// Yani "Piyasa kapalı" / "Seans kapalı" / "BORSA KAPALI" yalnızca
/// portföyün TAMAMI borsa takvimine bağlıysa söylenir. İçinde tek bir
/// altın, döviz, emtia, kripto ya da mevduat varsa rakam hafta sonu ve
/// gece de hareket eder; "kapalı" demek o kullanıcıya yanlış bilgidir.
///
/// ## Önceki ara adım (2026-09-12)
/// Kullanıcı bildirimi "piyasa kapalı dedik ama fiyatı değişen bir varlık
/// var demek ki" üzerine rozet türe göre daralmıştı ("BORSA KAPALI ·
/// DİĞERLERİ SÜRÜYOR", "SON VERİ"). O ara ifadeler de kalktı: karışık
/// portföyde hiçbir kapalılık ibaresi yok, canlı rakam kendini anlatıyor.
///
/// ## Uygulandığı yüzeyler
/// Bugün kartı (`BugunService.hesapla`), Performans rozeti, ana ekran
/// widget'ı (Android + iOS) ve Canlı Etkinlik (`yalnizBorsa` alanı —
/// istemci özeti + `push-live-activity`). Yeni bir yüzey "kapalı" diyecekse
/// buradan sorar; kendi tür listesini kurmaz.
///
/// ## Neden saf fonksiyon
/// Karar yalnızca türe bakıyor; widget ağacı, tarih ya da ağ gerekmiyor.
/// Ayrı tutmak davranışı platform olmadan test edilebilir kılıyor.

/// Borsa takvimine bağlı türler: hafta sonu ve resmî tatilde KESİN kapalı.
///
/// BES fonları TEFAS'ta fon gibi iş günü fiyatlanır. Mevduat HİÇBİRİNDE
/// değil: değeri piyasadan değil sözleşmeden gelir, "kapalı" olamaz.
/// Döviz/emtia/altın spot piyasaları hafta sonunun bir kısmında, kripto
/// 7/24 açıktır.
const _borsayaBagli = {AssetType.hisse, AssetType.fon, AssetType.bes};

/// Portföy yalnızca borsa takvimine bağlı türlerden mi oluşuyor?
///
/// Boş portföy `false`: kapalı olduğu söylenecek bir şey yok.
bool yalnizcaBorsa(Iterable<AssetType> turler) {
  final set = turler.toSet();
  return set.isNotEmpty && _borsayaBagli.containsAll(set);
}

/// [Asset] listesinden — BUGÜNKÜ mülkiyete göre (`aktifLotlar`).
///
/// Satılıp kapanmış bir kripto pozisyonu portföyü "karışık" yapmaz:
/// kullanıcı artık ondan tutmuyor, rakamı hafta sonu hareket etmez.
///
/// **ABD hissesi (2026-10-08, bayrak `abd_hisse`) portföyü karışık sayar.**
/// Türü hisse ama takvimi BIST değil: "kapalı" kararı BIST seansıyla
/// verilir (`seansAcikMi`, `DailySummary.isMarketOpen`) ve ABD seansı
/// TR saatiyle BIST kapandıktan sonra da sürer — o saatte "BORSA KAPALI"
/// yanlış bilgi olurdu. ABD takvimi bilinmediği için kapalılık hiç
/// söylenmez (uydurma kapalılık yok). ABD lot'u olmayan portföyde kural
/// birebir eski.
bool yalnizcaBorsaVarliklardan(Iterable<Asset> varliklar) {
  final aktif = aktifLotlar(varliklar);
  if (aktif.any((a) => a.abdHissesi)) return false;
  return yalnizcaBorsa(aktif.map((a) => a.type));
}

/// Rozet metni; portföy yalnızca borsaysa `'BORSA KAPALI'`, değilse `null`
/// (rozet çizilmez).
///
/// [turler] çizime giren varlıkların türleri.
String? piyasaKapaliEtiketi(Iterable<AssetType> turler) =>
    yalnizcaBorsa(turler) ? 'BORSA KAPALI' : null;

/// [Asset] listesinden doğrudan etiket üretir.
String? piyasaKapaliEtiketiVarliklardan(Iterable<Asset> varliklar) =>
    yalnizcaBorsaVarliklardan(varliklar) ? 'BORSA KAPALI' : null;

/// Fon gibi günde bir fiyatlanan türler: değer gün içinde değişmez.
const _gundeBirFiyat = {AssetType.fon, AssetType.bes};

/// Portföy (bugünkü mülkiyet) yalnız fon ve BES'ten mi oluşuyor?
bool yalnizcaFonVarliklardan(Iterable<Asset> varliklar) {
  final turler = aktifLotlar(varliklar).map((a) => a.type).toSet();
  return turler.isNotEmpty && _gundeBirFiyat.containsAll(turler);
}

/// Ortak nabzın fiyat turu seyrek mi atılsın (`TazelikRitmi.sakinTur`)?
/// Tek kural, tek yer (`MainNavigationScreen` buradan sorar).
///
/// - Yalnız borsa portföyü + seans kapalı (2026-10-21, #232): değişmeyecek
///   fiyat 30 sn'de bir indirilmesin.
/// - Yalnız fon/BES portföyü, seans AÇIKKEN de (müşteri raporu 2026-10-21
///   17:15 + 21:15, yasin "yapılmayan yap'ları yap"): fon fiyatı günde bir
///   yayınlanır; gün içinde 30 sn'lik tur hep aynı fiyatı getirir.
///   Yeni fiyat yayınlandığında en fazla bir sakin tur (5 dk) gecikir; öne
///   dönüş ve aşağı çekme her zaman anında tazeler.
///
/// Yalnız portföyün fiyat turunu etkiler: ana sayfadaki piyasa şeridi
/// (dolar, BIST, altın) kendi kotasyonunu nabızla çekmeye devam eder, o
/// kişide de canlı kalır.
bool fiyatTuruSakinMi(Iterable<Asset> varliklar, {required bool seansAcik}) =>
    yalnizcaFonVarliklardan(varliklar) ||
    (yalnizcaBorsaVarliklardan(varliklar) && !seansAcik);
