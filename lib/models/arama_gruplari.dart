import 'asset_type.dart';
import 'varlik_kimligi.dart';

/// Arama ekranında bir tür grubu: başlık + gösterilen satırlar + toplam.
class AramaGrubu {
  const AramaGrubu({
    required this.tur,
    required this.ogeler,
    required this.toplam,
  });

  final AssetType tur;

  /// Gösterilecek satırlar (kısaltılmış olabilir).
  final List<VarlikKimligi> ogeler;

  /// Bu türdeki TÜM sonuç sayısı — "Tümü (n)" bunu yazar.
  final int toplam;

  bool get kisaltildi => ogeler.length < toplam;
}


/// Grupta varsayılan olarak gösterilen satır sayısı.
///
/// Neden 3 (arama tasarımı, 2026-09-28): "altın" araması 10+ altın ürünü,
/// birkaç emtia ve adında "altın" geçen hisse/fonları getirir. Kesmeden
/// listelemek kullanıcının aradığı türü ekranın altına iter; 3 satır her
/// türden birer örnek görür, "Tümü (n)" ile türe odaklanır.
const aramaGrupSiniri = 3;

/// Sonuçları türe göre gruplar.
///
/// Grup sırası sonuçtaki İLK görünüşe göredir: arama servisi alaka sırasına
/// dizdiği için ("altin" → ticker'ı `ALTIN_` ile başlayanlar önce) en alakalı
/// tür en üstte kalır. Sabit bir tür sırası "altın" aramasında hisseleri
/// altının üstüne koyardı.
///
/// [filtre] verilirse yalnızca o tür döner ve KESİLMEZ (kullanıcı türü
/// seçti; hepsini görmek istiyor).
List<AramaGrubu> aramaGrupla(
  List<VarlikKimligi> sonuc, {
  AssetType? filtre,
  int sinir = aramaGrupSiniri,
}) {
  final gruplar = <AssetType, List<VarlikKimligi>>{};
  for (final k in sonuc) {
    if (filtre != null && k.type != filtre) continue;
    (gruplar[k.type] ??= []).add(k);
  }
  return [
    for (final e in gruplar.entries)
      AramaGrubu(
        tur: e.key,
        ogeler: filtre != null || e.value.length <= sinir
            ? e.value
            : e.value.take(sinir).toList(),
        toplam: e.value.length,
      ),
  ];
}

/// Sonuçta görünen türler, ilk görünüş sırasıyla — çip sırası.
List<AssetType> aramaTurleri(List<VarlikKimligi> sonuc) =>
    {for (final k in sonuc) k.type}.toList();
