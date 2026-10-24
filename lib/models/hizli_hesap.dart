import '../utils/tr_format.dart';
import '../utils/tr_katla.dart';
import 'asset_categories.dart';
import 'asset_type.dart';

/// Genel aramada "sayı + birim" sorgusu: "5 çeyrek", "100 dolar"
/// (fikir 2026-10-24 §3, rapor 2026-10-24_0915 §3).
///
/// ## Neden saf ve dar
/// Arama kutusu serbest metin; her sayılı sorguyu hesap sanmak ("2025
/// raporu", "3 ay") aramayı bozar. Bu yüzden yalnız TAM kalıp tanınır:
/// baştan bir sayı, ardından bilinen bir birim ve başka hiçbir şey. İlk
/// sürümde altın türleri ve üç döviz (USD/EUR/GBP); fon/hisse adedi sonra
/// (raporun kapsam kararı). Tanınmayan her şey `null` → satır yok.
///
/// Sayı formdaki alanlarla AYNI kuralla çözülür (`parseTrNumber`): "1.000
/// dolar" bin dolardır, "2,5 gram" iki buçuk gram.
///
/// ## Birim adları
/// Altın türleri `GoldSubCategory`'nin kendisi (repo hangi altını
/// tanıyorsa o). "gram" yalnız başına 24 ayardır: piyasada "gram altın"
/// 24 ayardır, vitrin ve hızlı seçim de öyle kaydeder. Ons BİLEREK yok:
/// USD kotedir, "≈ ₺" satırı ikinci bir çevrim isterdi. "5 altın" da yok:
/// hangi altın olduğu belirsiz, uydurma bir tür seçmek yanlış tutar demek.
class HizliHesap {
  const HizliHesap({required this.miktar, this.altin, this.doviz})
      : assert((altin == null) != (doviz == null));

  /// Çözülen miktar (> 0).
  final double miktar;

  /// Altın sorgusunda alt tür; döviz sorgusunda `null`.
  final GoldSubCategory? altin;

  /// Döviz sorgusunda `dovizOptions` etiketi (USD/EUR/GBP); altında `null`.
  final String? doviz;

  AssetType get tur => altin != null ? AssetType.altin : AssetType.doviz;

  /// TL karşılığı. Fiyat bilinmiyorsa (`null`, 0 ya da negatif) `null`:
  /// uydurma sayı yasak (fiyat kaynağı sözleşmesi madde 3), satır çizilmez.
  double? tutar(double? birimFiyat) =>
      birimFiyat != null && birimFiyat > 0 ? miktar * birimFiyat : null;

  @override
  bool operator ==(Object other) =>
      other is HizliHesap &&
      other.miktar == miktar &&
      other.altin == altin &&
      other.doviz == doviz;

  @override
  int get hashCode => Object.hash(miktar, altin, doviz);

  @override
  String toString() => 'HizliHesap($miktar, ${altin ?? doviz})';
}

/// Katlanmış (`trKatla`) birim → altın türü. Sondaki "altın/altını"
/// [hizliHesapCoz] içinde atılır; burada yalnız türün kendi adı durur.
const _altinBirimleri = <String, GoldSubCategory>{
  'gram': GoldSubCategory.gr24,
  'gr': GoldSubCategory.gr24,
  'gram 24 ayar': GoldSubCategory.gr24,
  '24 ayar': GoldSubCategory.gr24,
  '24 ayar gram': GoldSubCategory.gr24,
  'gram 22 ayar': GoldSubCategory.gr22,
  '22 ayar': GoldSubCategory.gr22,
  '22 ayar gram': GoldSubCategory.gr22,
  'gram 18 ayar': GoldSubCategory.gr18,
  '18 ayar': GoldSubCategory.gr18,
  '18 ayar gram': GoldSubCategory.gr18,
  'gram 14 ayar': GoldSubCategory.gr14,
  '14 ayar': GoldSubCategory.gr14,
  '14 ayar gram': GoldSubCategory.gr14,
  'has': GoldSubCategory.has,
  'gram has': GoldSubCategory.has,
  'has gram': GoldSubCategory.has,
  'ceyrek': GoldSubCategory.ceyrek,
  'yarim': GoldSubCategory.yarim,
  'tam': GoldSubCategory.tam,
  'cumhuriyet': GoldSubCategory.cumhuriyet,
  'ata': GoldSubCategory.ata,
  'resat': GoldSubCategory.resat,
  'hamit': GoldSubCategory.hamit,
  'ikibucuk': GoldSubCategory.ikibucuk,
  'iki bucuk': GoldSubCategory.ikibucuk,
  'gremse': GoldSubCategory.gremse,
  'besli': GoldSubCategory.besli,
};

/// Katlanmış birim → döviz etiketi. Yalnız üç döviz (rapor kararı).
const _dovizBirimleri = <String, String>{
  'dolar': 'USD',
  'usd': 'USD',
  'abd dolari': 'USD',
  'amerikan dolari': 'USD',
  'euro': 'EUR',
  'avro': 'EUR',
  'eur': 'EUR',
  'sterlin': 'GBP',
  'ingiliz sterlini': 'GBP',
  'gbp': 'GBP',
};

final _kalip = RegExp(r'^(\d+(?:[.,]\d+)*)\s*([a-z][a-z0-9 ]*)$');
final _altinEki = RegExp(r'\s*\baltin(i|in)?$');

/// "5 çeyrek", "2,5 gram altın", "100 dolar" → [HizliHesap]; kalıp değilse
/// ya da miktar 0'sa `null`.
HizliHesap? hizliHesapCoz(String girdi) {
  final katli = trKatla(girdi).trim().replaceAll(RegExp(r'\s+'), ' ');
  final m = _kalip.firstMatch(katli);
  if (m == null) return null;
  final miktar = parseTrNumber(m.group(1)!);
  if (miktar == null || miktar <= 0 || !miktar.isFinite) return null;
  final birim = m.group(2)!.trim();

  if (_dovizBirimleri[birim] case final d?) {
    return HizliHesap(miktar: miktar, doviz: d);
  }
  // "çeyrek altın", "cumhuriyet altını", "gram altın": tür adı + ek.
  final yalin = birim.replaceFirst(_altinEki, '').trim();
  if (_altinBirimleri[yalin] case final g?) {
    return HizliHesap(miktar: miktar, altin: g);
  }
  return null;
}
