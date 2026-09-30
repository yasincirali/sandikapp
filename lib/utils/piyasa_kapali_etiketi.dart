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
bool yalnizcaBorsaVarliklardan(Iterable<Asset> varliklar) =>
    yalnizcaBorsa(aktifLotlar(varliklar).map((a) => a.type));

/// Rozet metni; portföy yalnızca borsaysa `'BORSA KAPALI'`, değilse `null`
/// (rozet çizilmez).
///
/// [turler] çizime giren varlıkların türleri.
String? piyasaKapaliEtiketi(Iterable<AssetType> turler) =>
    yalnizcaBorsa(turler) ? 'BORSA KAPALI' : null;

/// [Asset] listesinden doğrudan etiket üretir.
String? piyasaKapaliEtiketiVarliklardan(Iterable<Asset> varliklar) =>
    yalnizcaBorsaVarliklardan(varliklar) ? 'BORSA KAPALI' : null;
