// BIST hisse listesi 2026-10-10'da kendi dosyasına taşındı; bu dosyayı
// içe aktaranlar `bist100StocksMap`'i görmeye devam etsin diye dışa aktarılır.
import 'bist_hisseleri.dart';

export 'bist_hisseleri.dart';

/// Birim türleri
enum UnitType {
  piece('Adet', 'adet'),
  gram('Gram', 'gr'),
  ounce('Ons', 'oz'),
  kilogram('Kilogram', 'kg'),
  liter('Litre', 'lt'),
  barrel('Varil', 'bbl');

  const UnitType(this.label, this.shortcode);
  final String label;
  final String shortcode;

  static UnitType fromString(String value) => UnitType.values.firstWhere(
        (e) => e.name == value,
        orElse: () => UnitType.piece,
      );
}

/// Altın alt kategorileri
///
/// **Sıra ekrandaki çip sırasıdır** (`add_asset_screen` `_goldChipGrid`):
/// önce gram cinsinden ayarlar (en çok alınan 24 ayar "gram altın" başta),
/// sonra ziynet/sikke adetleri, en sonda ons. Kayıtlı veriye enum SIRASI
/// değil `label` (subCategory) ve ticker yazılır; sıra değişmesi veriyi
/// bozmaz.
///
/// **2026-09-25 genişlemesi:** "normal gram altın yok" (kullanıcı). Eskiden
/// yalnızca 22 ayar gram vardı; Türkiye'de "gram altın" denince kastedilen
/// 24 ayar (995) külçe gramdır. Eklenenlerin hepsi truncgil v4'te ayrı
/// kotasyonla gelir (`PriceService._truncgilGoldKeys`). Var olan
/// `gr22` → `ALTIN_GRAM` eşlemesi KORUNDU: eski kayıtlar o sembolle durur.
enum GoldSubCategory {
  gr24('Gram Altın (24 Ayar)', 'gr',
      '24 ayar (995) gram altın; bankada ve kuyumcuda "gram altın"'),
  gr22('22 Ayar Gram Altın', 'gr', '22 ayar altın, gram olarak alınır'),
  gr18('18 Ayar Altın', 'gr', '18 ayar altın, gram olarak'),
  gr14('14 Ayar Altın', 'gr', '14 ayar altın, gram olarak'),
  has('Has Altın', 'gr', 'Has (saf) altın, gram olarak'),
  ceyrek('Çeyrek Altın', 'piece', 'Ülkeye özel eski çeyrek altın'),
  yarim('Yarım Altın', 'piece', 'Ülkeye özel eski yarım altın'),
  tam('Tam Altın', 'piece', 'Ziynet tam altın'),
  cumhuriyet('Cumhuriyet Altını', 'piece', 'Türk Cumhuriyet altını'),
  ata('Ata Altını', 'piece', 'Ülkeye özel eski ata altını'),
  resat('Reşat Altını', 'piece', 'Ülkeye özel eski reşat altını'),
  hamit('Hamit Altını', 'piece', 'Osmanlı hamit altını'),
  ikibucuk('İkibuçuk Altın', 'piece', 'İkibuçukluk altın'),
  gremse('Gremse Altın', 'piece', 'Gremse (ziynet ikibuçuk) altın'),
  besli('Beşli Altın', 'piece', 'Beşli altın'),
  ons('Altın (Ons)', 'ounce', 'Uluslararası piyasa - ons, USD');

  const GoldSubCategory(this.label, this.unitType, this.description);
  final String label;
  final String unitType;
  final String description;

  static GoldSubCategory fromString(String value) =>
      GoldSubCategory.values.firstWhere(
        (e) => e.name == value,
        orElse: () => GoldSubCategory.gr22,
      );
}

/// Fon alt kategorileri
enum FondSubCategory {
  bankFund('Banka Fonları', 'Büyük bankaların yatırım fonları'),
  bist100('BIST 100 Endeksi', 'BIST 100 hisse senedi endeksine yatırım'),
  commodity('Emtia Fonları', 'Altın, petrol vb emtialara yatırım'),
  foreign('Yabancı Fonlar', 'Uluslararası yatırım fonları'),
  private('Özel Fon', 'Diğer yatırım fonları');

  const FondSubCategory(this.label, this.description);
  final String label;
  final String description;

  static FondSubCategory fromString(String value) =>
      FondSubCategory.values.firstWhere(
        (e) => e.name == value,
        orElse: () => FondSubCategory.bankFund,
      );
}

/// Hisse alt kategorileri
///
/// **Kayıtta yazılan değer üyeden üyeye farklı (bilinçli):** `bist100` ve
/// `other` geçmişte `label` olarak yazıldı ('BIST Hisseleri' / 'Diğer
/// Hisseler'); o satırlar sunucuda öyle duruyor, değiştirilmez. `abd`
/// (2026-10-08, bayrak `abd_hisse`) ise `name` olarak yazılır: `'abd'`.
/// Etiket Türkçe görünen metindir ve ileride değişebilir; ABD kimliği
/// (`Asset.abdHissesi`) değişmeyen bir koda dayanmalı. Eski sürüm bu
/// değeri tanımaz, ama hisse alt kategorisini yalnız `isBist100`
/// karşılaştırmasında okur — tanımamak ona "BIST seçili değil" demektir,
/// tam da doğru davranış.
enum StockSubCategory {
  bist100('BIST Hisseleri', 'Borsa İstanbul\'da işlem gören hisse senetleri'),
  other('Diğer Hisseler', 'Listede olmayan hisse senetleri'),
  abd('ABD Hisseleri', 'NYSE ve Nasdaq\'ta işlem gören hisse ve ETF\'ler');

  const StockSubCategory(this.label, this.description);
  final String label;
  final String description;

  static StockSubCategory fromString(String value) =>
      StockSubCategory.values.firstWhere(
        (e) => e.name == value,
        orElse: () => StockSubCategory.other,
      );
}

/// Takip/kimlik anahtarına ([varlikAnahtari], `WatchlistItem.key`) girecek
/// alt kategori.
///
/// Anahtar alt kategoriyi sembolden ÖNCE kullanır: altında "Çeyrek Altın"
/// varlığın kimliğidir. ABD hissesinin `'abd'` alt kategorisi ise bir PAZAR
/// etiketidir, kimlik değil — anahtara girseydi bütün ABD hisseleri tek
/// anahtara düşer, ikinci ABD hissesi "zaten takipte" görünürdü. ABD'de
/// kimlik semboldür (sunucu indeksi de sembolü içerir, 0043). Öteki
/// değerler aynen döner: bayrak kapalıyken anahtar birebir eski.
String? anahtarAltKategorisi(String? altKategori) =>
    altKategori == StockSubCategory.abd.name ? null : altKategori;

/// Banka fonları listesi
const bankFunds = {
  'Akbank': [
    'ABF Dengeli Fon',
    'ABF Büyüme Fon',
    'ABF Kısa Vadeli Borçlanma Araçları Fon',
  ],
  'İşbank': [
    'İş Portföy Hisse Fon',
    'İş Portföy Kısa Vadeli Borçlanma Araçları Fon',
    'İş Portföy Dinamik Fon',
  ],
  'Garanti': [
    'Garanti Portföy Hisse Fon',
    'Garanti Portföy Borçlanma Araçları Fon',
    'Garanti Portföy Dengeli Fon',
  ],
  'Yapı Kredi': [
    'Yapı Kredi Portföy Hisse Fon',
    'Yapı Kredi Portföy Borçlanma Araçları Fon',
    'Yapı Kredi Portföy Dinamik Fon',
  ],
  'BBVA': [
    'BBVA Portföy Hisse Fon',
    'BBVA Portföy Borçlanma Araçları Fon',
  ],
  'Deniz': [
    'Deniz Portföy Hisse Fon',
    'Deniz Portföy Borçlanma Araçları Fon',
  ],
};

/// Geriye dönük uyumluluk için liste hali
List<String> get bist100Stocks => bist100StocksMap.keys.toList();

/// Altın alt kategorisi → PriceService'in kullandığı dahili ticker
/// ALTIN_* semboller XAUTRY=X üzerinden hesaplanır
const goldTickerMap = <String, String>{
  'Gram Altın (24 Ayar)': 'ALTIN_GRAM24',
  '22 Ayar Gram Altın': 'ALTIN_GRAM',
  '18 Ayar Altın': 'ALTIN_18AYAR',
  '14 Ayar Altın': 'ALTIN_14AYAR',
  'Has Altın': 'ALTIN_HAS',
  'Çeyrek Altın': 'ALTIN_CEYREK',
  'Yarım Altın': 'ALTIN_YARIM',
  'Tam Altın': 'ALTIN_TAM',
  'Cumhuriyet Altını': 'ALTIN_CUMHURIYET',
  'Ata Altını': 'ALTIN_ATA',
  'Reşat Altını': 'ALTIN_RESAT',
  'Hamit Altını': 'ALTIN_HAMIT',
  'İkibuçuk Altın': 'ALTIN_IKIBUCUK',
  'Gremse Altın': 'ALTIN_GREMSE',
  'Beşli Altın': 'ALTIN_BESLI',
  'Altın (Ons)': 'XAUUSD=X', // USD - Yahoo Finance sembolü
};

/// Emtia türleri
const commodityTypes = [
  'Petrol (Brent)',
  'Doğalgaz',
  'Altın (Ons)',
  'Gümüş (Ons)',
  'Bakır',
  'Buğday',
  'Mısır',
  'Soya',
];
