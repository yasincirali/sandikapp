import 'history_service.dart' show NormalizedSeries;
import 'symbol_search_service.dart' show PortfolioSeries, SymbolHit;
import '../utils/tr_format.dart';

/// Karşılaştır ekranının paylaşım kartına giren tek satır: ad + dönem yüzdesi.
typedef KiyasSatiri = ({String ad, double pct});

/// Karşılaştır'daki kıyasın paylaşılabilir hâli (Ar-Ge 7 Kas 04:03, YAP 1).
///
/// **Yalnız yüzde, tutar yok.** Kıyas grafiği zaten dönem başına göre
/// normalize yüzdedir (`normalizeSeries`); `firstPrice`/`lastPrice` karta
/// GİRMEZ — "Portföyüm" satırında ham değer portföy tutarı demektir.
/// Dönem özeti kartıyla aynı mahremiyet kuralı (`ShareCardData` notu).
class KiyasPaylasimi {
  const KiyasPaylasimi({
    required this.satirlar,
    required this.baslangic,
    required this.bitis,
  });

  /// En yüksek getiriden en düşüğe. Ekrandaki sıra renk ataması içindir
  /// (seçim sırası); kartta renk yok, sıralı liste "kim önde" sorusunu
  /// tek bakışta yanıtlar.
  final List<KiyasSatiri> satirlar;

  /// Kıyasa giren serilerin ortak penceresi (en erken ilk nokta, en geç son
  /// nokta) — başlığın altındaki tarih aralığı.
  final DateTime baslangic;
  final DateTime bitis;

  /// Metin paylaşımının gövdesi: "THYAO +%12,3 · Altın +%4,1".
  /// Yüzde biçimi kartla ve uygulamanın geri kalanıyla aynı (`fmtPctIsaretli`).
  String get ozetSatiri => satirlar
      .map((s) => '${s.ad} ${fmtPctIsaretli(s.pct, digits: 1)}')
      .join(' · ');
}

/// Seçili semboller + seriler → paylaşım modeli; paylaşılacak bir şey yoksa
/// `null` (ekran o zaman paylaş düğmesini kapatır).
///
/// Saf fonksiyon: `build()` içinde hesap yok kuralı ve test edilebilirlik.
///
/// Kurallar:
/// - Serisi henüz gelmemiş ya da çekilememiş sembol atlanır; uydurma `0`
///   yazılmaz (fiyat kaynağı sözleşmesi §3).
/// - **Ortak portföyü kartta yok.** O başkasının portföyüdür; ekranda
///   ortaklık izniyle görülür ama paylaşım kararı onun değil, kullanıcının
///   olurdu. Adı ve yüzdesi dışarı çıkmaz.
/// - En az İKİ satır: tek varlığın yüzdesi kıyas değildir; o paylaşım
///   varlık sayfasının ve dönem özetinin işi.
KiyasPaylasimi? kiyasPaylasimiKur({
  required List<SymbolHit> secili,
  required Map<String, NormalizedSeries> seriler,
  required String Function(SymbolHit) etiket,
}) {
  final satirlar = <KiyasSatiri>[];
  int? ilk;
  int? son;
  for (final hit in secili) {
    if (PortfolioSeries.partnerIdOf(hit.ticker) != null) continue;
    final s = seriler[hit.ticker];
    if (s == null || s.points.isEmpty || !s.totalReturnPct.isFinite) continue;
    satirlar.add((ad: etiket(hit), pct: s.totalReturnPct));
    for (final k in s.points.keys) {
      if (ilk == null || k < ilk) ilk = k;
      if (son == null || k > son) son = k;
    }
  }
  if (satirlar.length < 2 || ilk == null || son == null) return null;
  satirlar.sort((a, b) => b.pct.compareTo(a.pct));
  return KiyasPaylasimi(
    satirlar: List.unmodifiable(satirlar),
    baslangic: DateTime.fromMillisecondsSinceEpoch(ilk),
    bitis: DateTime.fromMillisecondsSinceEpoch(son),
  );
}
