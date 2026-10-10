import 'asset.dart';

/// "Bu ekranda HANGİ lotlar görünür?" sorusunun TEK cevabı — kişi kapsamı
/// (Ben / ortak / Birlikte) ve portföy.
///
/// ## Neden tek yer (çoklu portföy, 2026-10-10)
/// Kişi kapsamı yedi yüzeyde elle kuruluyordu (`home_screen`,
/// `portfolio_screen`, `portfolio_performance_screen`,
/// `all_transactions_screen`, `kiyasVarliklari`…): `''` ise kendi defteri,
/// uuid ise o ortağın, `null` ise hepsi. Portföy süzgeci aynı yerlere
/// girecekti; yedi kopyaya ikinci bir koşul eklemek bir gün birinin
/// unutulması ve aynı portföyün iki ekranda iki toplam göstermesi demekti
/// (TECHNICAL_DEBT "Olgun Premium setinde ertelenenler" 2. madde: "önce
/// kapsam görünümü tek sağlayıcıya toplanır"). Önce bu dosya, davranışı
/// BİREBİR koruyarak yazıldı (`test/gorunum_kapsami_test.dart` eski elle
/// kurulan listelerle eşitliği kilitler); portföy süzgeci sonra eklendi.
///
/// ## Sözleşme
/// - Kişi: `''` Ben, uuid o ortak, `null` Birlikte (`OrtakSecici`).
/// - Portföy: [PortfoySecimi]. YALNIZ "Ben" kapsamına uygulanır. Ortağın
///   lotları hiçbir portföye girmez (onun portföyleri bu kullanıcının
///   seçicisinde yok) ve Birlikte kullanıcı TOPLAMI + ortaklardır.
/// - Sahiplik sınırı korunur: dönüş sahip başına listedir
///   ([kapsamSahipDefterleri]), çünkü `positionKey` sahip taşımaz (bkz.
///   `aggregatePositionsByOwner`). Düz liste ([kapsamDefteri]) yalnız
///   seri motoruna ve hareket listesine gider.
/// - Süzgeç LOT düzeyindedir, pozisyon düzeyinde değil: portföyün defteri
///   alım + satım + temettü + silme satırlarıyla kendi içinde kapanır, ve
///   seri/getiri/özet motorları (hepsi lot listesi alır) değişmeden o alt
///   kümeyi hesaplar. Aynı sembol iki portföydeyse her portföy kendi
///   ağırlıklı ortalama maliyetini görür.
abstract final class PortfoySecimi {
  /// Bütün lotlar — bugünkü (çoklu portföy öncesi) kullanıcı toplamı.
  static const tumu = '';

  /// `portfoy_id IS NULL` olan lotlar (ve artık var olmayan bir portföyü
  /// işaret edenler, bkz. [lotunPortfoyu]).
  static const ana = 'ana';
}

/// Lotun ÇÖZÜLMÜŞ portföyü: [bilinen] içinde olmayan kimlik Ana sayılır.
///
/// Neden: portföy başka cihazda silindiyse sunucu lotu zaten Ana'ya düşürür
/// (FK `on delete set null`), ama bu cihazın bellekteki defteri yeniden
/// yüklenene kadar eski kimliği taşır. Bilinmeyen kimliği hiçbir portföye
/// koymamak o lotları seçicideki hiçbir parçada göstermezdi ve
/// "Σ portföy == Tümü" kırılırdı; Ana'ya koymak sunucunun bir sonraki
/// okumada vereceği cevabın aynısıdır.
String? lotunPortfoyu(Asset a, Set<String> bilinen) {
  final p = a.portfoyId;
  return p != null && bilinen.contains(p) ? p : null;
}

/// [a] seçili portföyde mi.
bool portfoyeAit(Asset a, String secim, Set<String> bilinen) {
  if (secim == PortfoySecimi.tumu) return true;
  final p = lotunPortfoyu(a, bilinen);
  return secim == PortfoySecimi.ana ? p == null : p == secim;
}

/// [lotlar]'ın seçili portföydeki alt kümesi. "Tümü" seçiliyken AYNI liste
/// nesnesi döner — bayrak kapalıyken hiçbir kopya, hiçbir yeni nesne
/// üretilmez (önbellekler `identical` ile karşılaştırıyor).
List<Asset> portfoyLotlari(
  List<Asset> lotlar,
  String secim,
  Set<String> bilinen,
) {
  if (secim == PortfoySecimi.tumu) return lotlar;
  return [
    for (final a in lotlar)
      if (portfoyeAit(a, secim, bilinen)) a,
  ];
}

/// Defteri portföylere böler (anahtar `null` = Ana). Σ parça == bütün:
/// her lot tam bir parçaya düşer.
Map<String?, List<Asset>> portfoyeGoreBol(
  Iterable<Asset> lotlar,
  Set<String> bilinen,
) {
  final m = <String?, List<Asset>>{};
  for (final a in lotlar) {
    m.putIfAbsent(lotunPortfoyu(a, bilinen), () => []).add(a);
  }
  return m;
}

/// Kapsamın SAHİP BAŞINA defterleri — `aggregatePositionsByOwner` /
/// `ownerScoped*` girdisi.
///
/// [aktifOrtaklar] verilirse yalnız onlar girer (pasifleşmiş ortağın verisi
/// haritada kalmış olabilir; `kiyasVarliklari`'nın kuralı); verilmezse
/// haritadaki herkes (`allPartnerAssetsProvider` zaten yalnız aktif
/// ortakları taşır). Birlikte'de sıra: önce kendi defteri, sonra ortaklar
/// ([aktifOrtaklar] ya da harita sırasıyla) — eski elle kurulan listelerin
/// sırası.
List<List<Asset>> kapsamSahipDefterleri({
  required String? kisi,
  required List<Asset> benim,
  required Map<String, List<Asset>> ortaklar,
  Iterable<String>? aktifOrtaklar,
  String portfoy = PortfoySecimi.tumu,
  Set<String> bilinenPortfoyler = const {},
}) {
  List<Asset> ortak(String id) {
    if (aktifOrtaklar != null && !aktifOrtaklar.contains(id)) {
      return const [];
    }
    return ortaklar[id] ?? const [];
  }

  if (kisi == '') {
    return [portfoyLotlari(benim, portfoy, bilinenPortfoyler)];
  }
  if (kisi != null) return [ortak(kisi)];
  return [
    benim,
    for (final id in aktifOrtaklar ?? ortaklar.keys) ortak(id),
  ];
}

/// Kapsamın DÜZ defteri (ham ledger: alım/satım/temettü/silme). Tek sahipli
/// kapsamda o sahibin liste nesnesinin KENDİSİ döner (portföy "Tümü" iken).
List<Asset> kapsamDefteri({
  required String? kisi,
  required List<Asset> benim,
  required Map<String, List<Asset>> ortaklar,
  Iterable<String>? aktifOrtaklar,
  String portfoy = PortfoySecimi.tumu,
  Set<String> bilinenPortfoyler = const {},
}) {
  final gruplar = kapsamSahipDefterleri(
    kisi: kisi,
    benim: benim,
    ortaklar: ortaklar,
    aktifOrtaklar: aktifOrtaklar,
    portfoy: portfoy,
    bilinenPortfoyler: bilinenPortfoyler,
  );
  if (gruplar.length == 1) return gruplar.single;
  return [for (final l in gruplar) ...l];
}
