import 'asset.dart';
import 'asset_type.dart';
import 'position.dart';
import 'sozlesme.dart';

/// Bir BES sözleşmesinin fonları — Portföy listesinde TEK satır.
///
/// ## Neden (yasin, 2026-10-29: "BES varlığı fon dağılımıyla birlikte tek
/// mi gözükmeli … içerden varlık dağılımı değiştirilebilmeli")
/// Portföy her fon + katkı tipi için ayrı satır basıyordu: üç fonlu, devlet
/// katkılı bir sözleşme dört satır ediyordu ve hiçbir satır "MetLife
/// BES'im ne kadar" sorusunu yanıtlamıyordu. Kullanıcı BES'i tek varlık
/// olarak düşünür (ücretsiz kota da öyle sayar, `kotaAnahtarlari`).
///
/// ## Değişmez korunur
/// Birleşme GÖRÜNÜMDEDİR, hesapta değil (aynı desen: [BirlesikPozisyon]).
/// Her fon kendi `aggregatePositions` çıktısıdır — kendi fiyatı, kendi
/// maliyet ortalaması. Değer ve maliyet fonların TOPLAMIDIR; tek fonun
/// fiyatı başka fonun payına uygulanmaz. Halka, üst özet ve toplamlar bu
/// sınıfı hiç görmez (yalnız listenin satırları gruplanır), yani
/// "Σ satır == toplam" eskisi gibi sağlanır.
///
/// [totalQuantity] fon paylarının toplamıdır ve TEK BAŞINA anlamsızdır
/// (farklı fonların payı toplanmaz); yalnız sıralama ve [asDisplayAsset]
/// için "değer = miktar × birim" eşitliğini kurmak üzere taşınır. Satır
/// miktar göstermez (`_satirAltMetni` BES'te zaten göstermiyordu).
class BesSozlesmePozisyonu extends Position {
  BesSozlesmePozisyonu._({
    required super.key,
    required super.representative,
    required super.lots,
    required super.totalQuantity,
    required super.weightedPurchasePrice,
    required super.weightedFxRate,
    required super.latestAddedDate,
    required super.totalCommission,
    required super.totalDividend,
    required this.sozlesmeId,
    required this.fonlar,
  });

  final String sozlesmeId;

  /// Sözleşmenin fon pozisyonları, değere göre azalan (en büyük önde).
  final List<Position> fonlar;

  /// Satırın liste anahtarı — fon anahtarlarıyla çakışmaz.
  static String anahtarOf(String sozlesmeId) => 'bes|sozlesme:$sozlesmeId';

  factory BesSozlesmePozisyonu.fonlardan(
      String sozlesmeId, List<Position> fonlar) {
    assert(fonlar.isNotEmpty);
    final sirali = [...fonlar]
      ..sort((a, b) => b.totalValue.compareTo(a.totalValue));
    var miktar = 0.0, maliyet = 0.0, kurluMaliyet = 0.0;
    var komisyon = 0.0, temettu = 0.0;
    var enYeni = sirali.first.latestAddedDate;
    for (final p in sirali) {
      miktar += p.totalQuantity;
      maliyet += p.totalQuantity * p.weightedPurchasePrice;
      kurluMaliyet +=
          p.totalQuantity * p.weightedPurchasePrice * p.weightedFxRate;
      komisyon += p.totalCommission;
      temettu += p.totalDividend;
      if (p.latestAddedDate.isAfter(enYeni)) enYeni = p.latestAddedDate;
    }
    return BesSozlesmePozisyonu._(
      key: anahtarOf(sozlesmeId),
      // En büyük fonun temsilcisi: kurum adı, tür, sahip ve sözleşme
      // kimliği oradan okunur (hepsi sözleşme genelinde aynı).
      representative: sirali.first.representative,
      lots: [for (final p in sirali) ...p.lots]
        ..sort((a, b) => b.addedDate.compareTo(a.addedDate)),
      totalQuantity: miktar,
      weightedPurchasePrice: miktar > 0 ? maliyet / miktar : 0,
      weightedFxRate: maliyet > 0 ? kurluMaliyet / maliyet : 1,
      latestAddedDate: enYeni,
      totalCommission: komisyon,
      totalDividend: temettu,
      sozlesmeId: sozlesmeId,
      fonlar: List.unmodifiable(sirali),
    );
  }

  /// Satır başlığındaki kurum (lot adından, `Asset.besKurumu`). Eski
  /// biçimli adda `null` — satır yalnız türü yazar.
  String? get kurum {
    for (final p in fonlar) {
      final k = p.representative.besKurumu;
      if (k != null && k.isNotEmpty) return k;
    }
    return null;
  }

  /// Satıra dokununca açılan fon: en büyüğü. Varlık ekranı tek fonun
  /// grafiğini ve sözleşme kartını (fon dağılımı dahil) gösterir.
  Position get enBuyukFon => fonlar.first;

  /// Kendi katkı fonu sayısı + devlet katkısı fonu var mı — alt metin.
  int get fonSayisi => {
        for (final p in fonlar)
          if (p.representative.subCategory != BesAltKategori.devletKatkisi)
            p.representative.ticker.toUpperCase(),
      }.length;

  bool get devletKatkisiVar => fonlar.any(
      (p) => p.representative.subCategory == BesAltKategori.devletKatkisi);

  @override
  double get totalValue => fonlar.fold(0.0, (s, p) => s + p.totalValue);

  @override
  double get totalCost => fonlar.fold(0.0, (s, p) => s + p.totalCost);

  @override
  double get totalCostTRY => fonlar.fold(0.0, (s, p) => s + p.totalCostTRY);

  /// Birim fiyat toplam değerden türetilir: satırdaki tutar (`miktar ×
  /// fiyat`) ile kâr/zararın dayandığı [totalValue] aynı sayı olsun.
  /// Fonlardan birinin fiyatı yoksa (0) birim de 0'a düşer: kâr/zarar
  /// satırı gizlenir, eksik fiyat kârı uydurmaz.
  @override
  Asset asDisplayAsset() {
    final a = super.asDisplayAsset();
    final fiyatsiz = fonlar.any((p) => p.representative.currentPrice <= 0);
    a.currentPrice =
        fiyatsiz || totalQuantity <= 0 ? 0 : totalValue / totalQuantity;
    return a;
  }

  /// Fon fon döküm (açılır panel ve sözleşme kartı aynı fonksiyondan).
  List<BesFonSatiri> get fonSatirlari => besFonSatirlari(fonlar);
}

/// Sözleşmedeki bir fonun satırı: kod, katkı tipi, tutar, sözleşme içindeki
/// payı ve getirisi.
class BesFonSatiri {
  const BesFonSatiri({
    required this.pozisyon,
    required this.kod,
    required this.devlet,
    required this.deger,
    required this.maliyet,
    required this.oran,
  });

  final Position pozisyon;

  /// Kullanıcıya gösterilen fon kodu (`AH5`, önek yok).
  final String kod;

  /// Devlet katkısı birikimi mi.
  final bool devlet;
  final double deger;
  final double maliyet;

  /// Sözleşme toplamı içindeki pay, yüzde (0–100).
  final double oran;

  /// Getiri yüzdesi; maliyet ya da fiyat bilinmiyorsa `null` (uydurma
  /// yüzde yazılmaz).
  double? get getiriYuzde => maliyet > 0 && deger > 0
      ? (deger - maliyet) / maliyet * 100
      : null;
}

/// [fonlar]'ı satırlara çevirir — sıra değere göre azalan. Saf, test edilir.
///
/// Pay, BUGÜNKÜ değerden hesaplanır (fon fiyatları farklı yürüdüğü için
/// sözleşmenin katkı talimatından — `Sozlesme.fonDagilimi` — ayrışabilir;
/// kart ikisini ayrı gösterir).
List<BesFonSatiri> besFonSatirlari(Iterable<Position> fonlar) {
  final l = fonlar.toList();
  final toplam = l.fold<double>(0, (s, p) => s + p.totalValue);
  return [
    for (final p in l)
      BesFonSatiri(
        pozisyon: p,
        kod: p.representative.displayTicker ?? p.representative.ticker,
        devlet:
            p.representative.subCategory == BesAltKategori.devletKatkisi,
        deger: p.totalValue,
        maliyet: p.totalCost,
        oran: toplam > 0 ? p.totalValue / toplam * 100 : 0,
      ),
  ]..sort((a, b) => b.deger.compareTo(a.deger));
}

/// Liste satırlarını sözleşmeye göre toplar: sözleşmeli BES fon
/// pozisyonları [BesSozlesmePozisyonu]'na, geri kalan her şey olduğu gibi.
///
/// Sıra ilk görülme sırasıdır; çağıran ardından sıralar (sözleşme satırı
/// toplam değeriyle yarışır). Sözleşme kimliği olmayan BES lotu ve ortak
/// satırı ([BirlesikPozisyon]) dokunulmadan geçer — sözleşme tek sahiplidir,
/// kimliksiz lotun ait olduğu sözleşme bilinmez.
List<Position> besSozlesmeleriniGrupla(Iterable<Position> pozisyonlar) {
  final gruplar = <String, List<Position>>{};
  final sira = <Object>[];
  for (final p in pozisyonlar) {
    final sid = p.representative.sozlesmeId;
    if (p.representative.type == AssetType.bes &&
        p is! BirlesikPozisyon &&
        sid != null &&
        sid.isNotEmpty) {
      final g = gruplar[sid];
      if (g == null) {
        gruplar[sid] = [p];
        sira.add(sid);
      } else {
        g.add(p);
      }
    } else {
      sira.add(p);
    }
  }
  return [
    for (final x in sira)
      if (x is Position)
        x
      else
        BesSozlesmePozisyonu.fonlardan(x as String, gruplar[x]!),
  ];
}
