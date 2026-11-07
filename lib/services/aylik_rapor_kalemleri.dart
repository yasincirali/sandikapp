import '../models/asset_type.dart';
import '../providers/hafta_ozeti_provider.dart'
    show HaftaRozeti, haftaRozetiSunucudan;
import 'aylik_rapor_ozeti.dart';
import 'varlik_analizi.dart';

/// Bir pozisyonun aylık nottaki karşılığı: not anahtarı ('THYAO.IS',
/// 'HISSE:AAPL', 'ALTIN:GRAM'…), tür ve kullanıcının tanıdığı ad.
typedef NotPozisyonu = ({String notAnahtari, AssetType tur, String ad});

/// Raporda bir satır ya da kart: varlığın adı ve türü, ayın sayısı
/// ([varlik], istemcinin hesabı) ve yapay zekâ notu ([not]).
class RaporKalemi {
  const RaporKalemi({
    required this.ad,
    required this.tur,
    this.varlik,
    this.not,
    this.haberler = const [],
  });

  final String ad;
  final AssetType? tur;
  final AyinVarligi? varlik;
  final AnalizOzeti? not;

  /// Notun ayın haber satırları (0177); yalnız [onemli] kalemde dolu.
  final List<AyinHaberi> haberler;
}

/// Notun öne çıkıp çıkmadığı: rozeti bilinen ve `sakin` olmayan not.
/// Rozet veriden gelir (sunucu `balina_olay` / fiyat ölçümleri); türden
/// bağımsız (yasin 2026-11-07: "önemli bilgi olan varlıklar görüntülenmeli").
bool notOnemli(AnalizOzeti n) {
  final r = haftaRozetiSunucudan(n.rozet);
  return r != null && r != HaftaRozeti.sakin;
}

/// Aylık raporun iki listesi — ekran ve PDF AYNI sırayı buradan alır
/// (yasin 2026-11-07: "not sayfası da rapor pdf'i de anlaşılır olmalı").
///
/// - [onemli]: öne çıkan notlar, rozet önemine göre; her not BİR kez
///   (birden çok altın lotu tek nota bağlanır). Ayın sayısı yalnız notu
///   tek pozisyon taşıyorsa eklenir (iki altın lotunun yüzdesi ayrı).
/// - [diger]: her pozisyon tek satır (sayısal bölümün sırası, piyasa
///   etkisine göre); öne çıkmayan not ilk eşleştiği satırın alt cümlesi.
///   Pozisyonu sayısal bölüme girmeyen (fiyat serisi yok) notlar sonda.
///
/// [pozisyonlar] `positionKey` → not karşılığı; [notAdi] eşleşmeyen notun
/// adı.
///
/// Haber (0177, yasin: "önemli haber akışlarıyla önemli bilgi olan
/// varlıklar görüntülenmeli"): notunun ayında haberi olan varlık da
/// [onemli]'ye girer ve kartı haberleri taşır. Sıra: önce rozetliler
/// (rozet önemi), sonra yalnız haberi olan sakin notlar. Haber verilmezse
/// (bayrak kapalı, haber gelmedi) liste eskisiyle birebir aynı.
({List<RaporKalemi> onemli, List<RaporKalemi> diger}) raporKalemleri({
  required List<AnalizOzeti> notlar,
  required List<AyinVarligi> varliklar,
  required Map<String, NotPozisyonu> pozisyonlar,
  required String Function(AyinVarligi) varlikAdi,
  required String Function(String) notAdi,
  List<AyinHaberi> haberler = const [],
}) {
  final notMap = {for (final n in notlar) n.ticker: n};
  final haberMap = <String, List<AyinHaberi>>{};
  for (final h in haberler) {
    (haberMap[h.anahtar] ??= []).add(h);
  }
  bool haberli(AnalizOzeti n) => haberMap[n.ticker]?.isNotEmpty ?? false;
  // Haberli sakin not rozetliden sonra gelir (rozet önemi + 1 kademe).
  int sira(AnalizOzeti n) => notOnemli(n)
      ? haftaRozetiSunucudan(n.rozet)!.index
      : HaftaRozeti.values.length;
  // Not → onu taşıyan pozisyon(lar) ve etiket.
  final notunVarliklari = <String, List<AyinVarligi>>{};
  for (final v in varliklar) {
    final k = pozisyonlar[v.anahtar]?.notAnahtari;
    if (k != null) (notunVarliklari[k] ??= []).add(v);
  }
  final etiket = <String, NotPozisyonu>{};
  for (final p in pozisyonlar.values) {
    etiket.putIfAbsent(p.notAnahtari, () => p);
  }

  final onemliNotlar =
      notlar.where((n) => notOnemli(n) || haberli(n)).toList()
        ..sort((a, b) {
          final ra = sira(a), rb = sira(b);
          return ra != rb ? ra - rb : a.ticker.compareTo(b.ticker);
        });
  final onemli = [
    for (final n in onemliNotlar)
      RaporKalemi(
        ad: etiket[n.ticker]?.ad ?? notAdi(n.ticker),
        tur: etiket[n.ticker]?.tur,
        varlik: (notunVarliklari[n.ticker]?.length ?? 0) == 1
            ? notunVarliklari[n.ticker]!.single
            : null,
        not: n,
        haberler: haberMap[n.ticker] ?? const [],
      ),
  ];

  final kullanilan = <String>{for (final n in onemliNotlar) n.ticker};
  final diger = <RaporKalemi>[];
  for (final v in varliklar) {
    final k = pozisyonlar[v.anahtar]?.notAnahtari;
    final n = k == null || kullanilan.contains(k) ? null : notMap[k];
    if (n != null) kullanilan.add(n.ticker);
    diger.add(RaporKalemi(ad: varlikAdi(v), tur: v.tur, varlik: v, not: n));
  }
  final kalan = notlar.where((n) => !kullanilan.contains(n.ticker)).toList()
    ..sort((a, b) => a.ticker.compareTo(b.ticker));
  for (final n in kalan) {
    diger.add(RaporKalemi(
        ad: etiket[n.ticker]?.ad ?? notAdi(n.ticker),
        tur: etiket[n.ticker]?.tur,
        not: n));
  }
  return (onemli: onemli, diger: diger);
}
