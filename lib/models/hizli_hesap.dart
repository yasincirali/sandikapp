import '../utils/tr_format.dart';
import '../utils/tr_katla.dart';
import 'asset_categories.dart';
import 'asset_type.dart';
import 'varlik_kimligi.dart';

/// Genel aramada "sayı + birim" sorgusu: "5 çeyrek", "100 dolar"
/// (fikir 2026-10-24 §3, rapor 2026-10-24_0915 §3); ikinci adım (fikir
/// 2026-10-25_1245 §1, yasin onayı): ters yön "10.000 tl çeyrek" ve
/// hisse/fon adedi "100 THYAO".
///
/// ## Neden saf ve dar
/// Arama kutusu serbest metin; her sayılı sorguyu hesap sanmak ("2025
/// raporu", "3 ay") aramayı bozar. Bu yüzden yalnız TAM kalıp tanınır:
/// baştan bir sayı, ardından bilinen bir birim ve başka hiçbir şey.
/// Tanınmayan her şey `null` → satır yok. Üç kalıp:
/// - **İleri:** `sayı + altın türü | USD/EUR/GBP` → TL karşılığı.
/// - **Ters:** `sayı + tl|₺ + altın türü | döviz` → o TL ile kaç birim.
/// - **Adet:** `sayı + SEMBOL` → hisse/fon adedinin TL karşılığı.
///
/// Sayı formdaki alanlarla AYNI kuralla çözülür (`parseTrNumber`): "1.000
/// dolar" bin dolardır, "2,5 gram" iki buçuk gram. "5 bin tl" yazımı bu
/// adımda yok (fikir dosyası: küçük sözlük sonra gelebilir).
///
/// ## Birim adları
/// Altın türleri `GoldSubCategory`'nin kendisi (repo hangi altını
/// tanıyorsa o). "gram" yalnız başına 24 ayardır: piyasada "gram altın"
/// 24 ayardır, vitrin ve hızlı seçim de öyle kaydeder. Ons BİLEREK yok:
/// USD kotedir, "≈ ₺" satırı ikinci bir çevrim isterdi. "5 altın" da yok:
/// hangi altın olduğu belirsiz, uydurma bir tür seçmek yanlış tutar demek.
///
/// ## Ters yön neden SATIŞ fiyatından (2026-10-25)
/// "10.000 TL kaç çeyrek" soran kişi ALACAK; kuyumcu/banka ona satış
/// fiyatından satar. Alıştan bölmek, elindeki parayla gerçekte
/// alabileceğinden fazlasını söylerdi. Satış, Varlık Ekle'nin maliyete
/// yazdığı ve "Bozdurursan · Alırsan" satırının gösterdiği sayıyla AYNI
/// kapıdan geçer (`gorunurSatisFiyati` → `maliyetSatisFiyati`: yurt içi
/// kotasyon, TRY, satış ≥ alış, makas sınır içinde). Kapı reddederse satır
/// YOK; alışa düşülmez (o da "alırsın" deyip yanlış sayı göstermek olurdu).
///
/// ## Adet neden yalnız birebir sembol (2026-10-25)
/// "100 thy", "5 ak" gibi yarım kodu tahmin etmek yanlış şirketin tutarını
/// göstermek demek (müşteri incelemesi 2026-10-25_1315 §3: "100 thy ne
/// demek?"). Bu yüzden ayrıştırıcı sembol listesi TUTMAZ: çağıran,
/// aramanın var olan kaynağından bulduğu kimliği `sembolBul` ile verir
/// (iki arama yüzeyi ayrışmasın); ayrıştırıcı yalnız kısa etiketi yazılan
/// kodla BİREBİR aynı BIST hissesini (`.IS`) ya da TEFAS fonunu
/// (`TEFAS:`) kabul eder. Bulunamayan kod serbest metin kalır (`null`).
class HizliHesap {
  const HizliHesap({
    required this.miktar,
    this.altin,
    this.doviz,
    this.kimlik,
    this.ters = false,
  })  : assert((altin != null ? 1 : 0) +
                (doviz != null ? 1 : 0) +
                (kimlik != null ? 1 : 0) ==
            1),
        assert(!ters || kimlik == null);

  /// Çözülen sayı (> 0). İleri ve adet kalıbında birim miktarı; TERS
  /// kalıpta TL tutarı.
  final double miktar;

  /// Altın sorgusunda alt tür; öteki sorgularda `null`.
  final GoldSubCategory? altin;

  /// Döviz sorgusunda `dovizOptions` etiketi (USD/EUR/GBP); ötekilerde `null`.
  final String? doviz;

  /// Adet sorgusunda hisse/fon kimliği; ötekilerde `null`.
  final VarlikKimligi? kimlik;

  /// "10.000 tl çeyrek": [miktar] TL'dir, sonuç birim adedidir.
  final bool ters;

  AssetType get tur => altin != null
      ? AssetType.altin
      : doviz != null
          ? AssetType.doviz
          : kimlik!.type;

  /// Formun miktar alanına yazılacak adet; ters kalıpta `null` (miktar TL,
  /// adet değil; form o zaman Tutar kipinde açılır).
  double? get adetOnDolgu => ters ? null : miktar;

  /// TL karşılığı. Fiyat bilinmiyorsa (`null`, 0 ya da negatif) `null`:
  /// uydurma sayı yasak (fiyat kaynağı sözleşmesi madde 3), satır çizilmez.
  /// Ters kalıpta anlamsız → `null`.
  double? tutar(double? birimFiyat) =>
      !ters && birimFiyat != null && birimFiyat > 0 && birimFiyat.isFinite
          ? miktar * birimFiyat
          : null;

  /// Ters kalıpta alınabilecek birim adedi: TL ÷ SATIŞ fiyatı. Satış
  /// bilinmiyorsa `null` (satır yok). İleri kalıpta `null`.
  double? alinabilecekAdet(double? satisFiyati) =>
      ters && satisFiyati != null && satisFiyati > 0 && satisFiyati.isFinite
          ? miktar / satisFiyati
          : null;

  @override
  bool operator ==(Object other) =>
      other is HizliHesap &&
      other.miktar == miktar &&
      other.altin == altin &&
      other.doviz == doviz &&
      other.kimlik?.ticker == kimlik?.ticker &&
      other.ters == ters;

  @override
  int get hashCode => Object.hash(miktar, altin, doviz, kimlik?.ticker, ters);

  @override
  String toString() => 'HizliHesap(${ters ? 'TL ' : ''}$miktar, '
      '${altin ?? doviz ?? kimlik?.ticker})';
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

/// Ters kalıp: sayı, ardından "tl" / "try" / "₺", ardından birim. "tl"
/// sonrası boşluk zorunlu ("10 tlx" birim değil), "₺" sonrası değil.
final _tersKalip =
    RegExp(r'^(\d+(?:[.,]\d+)*)\s*(?:(?:tl|try)\s|₺\s*)\s*([a-z][a-z0-9 ]*)$');

/// Hisse/fon kodu biçimi: harfle başlar, 2–6 harf/rakam (BIST "A1CAP",
/// TEFAS "AFT"). Boşluk yok: "100 thy hava" kod değildir.
final _kodKalip = RegExp(r'^[a-z][a-z0-9]{1,5}$');
final _altinEki = RegExp(r'\s*\baltin(i|in)?$');

/// Kod sanılmaması gereken sözcükler: para birimi ve süre/adet ("10 tl",
/// "3 ay", "10 adet"). Kaynakta böyle bir sembol çıksa bile kullanıcı onu
/// kastetmez.
const _kodDegil = {'tl', 'try', 'ay', 'yil', 'gun', 'hafta', 'adet', 'lot'};

String _katla(String girdi) =>
    trKatla(girdi).trim().replaceAll(RegExp(r'\s+'), ' ');

double? _sayi(String metin) {
  final v = parseTrNumber(metin);
  if (v == null || v <= 0 || !v.isFinite) return null;
  return v;
}

/// Birim adı → (altın, döviz); tanınmazsa `null`.
(GoldSubCategory?, String?)? _birim(String birim) {
  if (_dovizBirimleri[birim] case final d?) return (null, d);
  // "çeyrek altın", "cumhuriyet altını", "gram altın": tür adı + ek.
  final yalin = birim.replaceFirst(_altinEki, '').trim();
  if (_altinBirimleri[yalin] case final g?) return (g, null);
  return null;
}

/// "100 THYAO" biçimindeki sorgunun KOD adayı (büyük harf); kalıp değilse
/// ya da birim altın/döviz/"tl" gibi bilinen bir sözcükse `null`. Ekran bu
/// adayı aramanın kendi kaynağında arar ve bulduğunu [hizliHesapCoz]'a
/// `sembolBul` ile verir; aday tek başına hiçbir satır çizdirmez.
String? hizliHesapKodAdayi(String girdi) {
  final m = _kalip.firstMatch(_katla(girdi));
  if (m == null || _sayi(m.group(1)!) == null) return null;
  final birim = m.group(2)!.trim();
  if (_birim(birim) != null) return null;
  if (_kodDegil.contains(birim) || !_kodKalip.hasMatch(birim)) return null;
  return birim.toUpperCase();
}

/// Kimlik birebir o kodun BIST hissesi ya da TEFAS fonu mu? ABD hissesi,
/// kripto, endeks ve yabancı para kotesi dışarıda: "≈ ₺" satırı TL kote
/// ister ve kapsam kararı BIST + TEFAS'tır.
bool _birebirHisseFon(VarlikKimligi k, String kod) {
  if (k.currency.toUpperCase() != 'TRY') return false;
  final t = k.ticker.toUpperCase();
  final bicim = switch (k.type) {
    AssetType.hisse => t.endsWith('.IS'),
    AssetType.fon => t.startsWith('TEFAS:'),
    _ => false,
  };
  return bicim && k.kisaEtiket.toUpperCase() == kod;
}

/// "5 çeyrek", "2,5 gram altın", "100 dolar", "10.000 tl çeyrek",
/// "100 THYAO" → [HizliHesap]; kalıp değilse ya da sayı 0'sa `null`.
///
/// [sembolBul] adet kalıbının tek kapısıdır: büyük harfli kodu (THYAO,
/// AFT) aramanın kaynağında bulunan kimliğe çevirir; verilmezse ya da
/// bulamazsa adet kalıbı hiç tanınmaz.
HizliHesap? hizliHesapCoz(
  String girdi, {
  VarlikKimligi? Function(String kod)? sembolBul,
}) {
  final katli = _katla(girdi);

  if (_tersKalip.firstMatch(katli) case final t?) {
    final tl = _sayi(t.group(1)!);
    final b = _birim(t.group(2)!.trim());
    if (tl == null || b == null) return null;
    return HizliHesap(miktar: tl, altin: b.$1, doviz: b.$2, ters: true);
  }

  final m = _kalip.firstMatch(katli);
  if (m == null) return null;
  final miktar = _sayi(m.group(1)!);
  if (miktar == null) return null;

  if (_birim(m.group(2)!.trim()) case final b?) {
    return HizliHesap(miktar: miktar, altin: b.$1, doviz: b.$2);
  }

  final kod = hizliHesapKodAdayi(girdi);
  if (kod == null || sembolBul == null) return null;
  final k = sembolBul(kod);
  if (k == null || !_birebirHisseFon(k, kod)) return null;
  return HizliHesap(miktar: miktar, kimlik: k);
}
