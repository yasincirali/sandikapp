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
enum GoldSubCategory {
  gr22('22 Ayar Gram Altın', 'gr', '22 ayar altın, gram olarak alınır'),
  ceyrek('Çeyrek Altın', 'piece', 'Ülkeye özel eski çeyrek altın'),
  yarim('Yarım Altın', 'piece', 'Ülkeye özel eski yarım altın'),
  ata('Ata Altını', 'piece', 'Ülkeye özel eski ata altını'),
  resat('Reşat Altını', 'piece', 'Ülkeye özel eski reşat altını'),
  cumhuriyet('Cumhuriyet Altını', 'piece', 'Türk Cumhuriyet altını'),
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
enum StockSubCategory {
  bist100('BIST 100 Hisseleri', 'Türkiye\'nin en değerli 100 hisse senedi'),
  other('Diğer Hisseler', 'BIST 100 dışı hisse senetleri');

  const StockSubCategory(this.label, this.description);
  final String label;
  final String description;

  static StockSubCategory fromString(String value) =>
      StockSubCategory.values.firstWhere(
        (e) => e.name == value,
        orElse: () => StockSubCategory.other,
      );
}

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

/// Tüm BIST100 hisseleri — Yahoo Finance sembolü → şirket adı
const bist100StocksMap = <String, String>{
  // Bankacılık & Finans
  'GARAN.IS': 'Garanti BBVA',
  'AKBNK.IS': 'Akbank',
  'ISCTR.IS': 'İş Bankası (C)',
  'VAKBN.IS': 'Vakıfbank',
  'YKBNK.IS': 'Yapı Kredi Bankası',
  'HALKB.IS': 'Halkbank',
  'SKBNK.IS': 'Şekerbank',
  'ALBRK.IS': 'Albaraka Türk',
  'KLNMA.IS': 'Kalkınma ve Yatırım Bankası',
  // Holding
  'KCHOL.IS': 'Koç Holding',
  'SAHOL.IS': 'Sabancı Holding',
  'DOHOL.IS': 'Doğan Holding',
  'GLYHO.IS': 'Global Yatırım Holding',
  'AGHOL.IS': 'AG Anadolu Grubu Holding',
  'BERA.IS': 'Bera Holding',
  'ALARK.IS': 'Alarko Holding',
  // Ulaşım & Havacılık
  'THYAO.IS': 'Türk Hava Yolları',
  'PGSUS.IS': 'Pegasus Hava Yolları',
  'TAVHL.IS': 'TAV Havalimanları',
  'CLEBI.IS': 'Çelebi Havacılık',
  // Teknoloji & Telekomünikasyon
  'TCELL.IS': 'Turkcell',
  'TTKOM.IS': 'Türk Telekom',
  'LOGO.IS': 'Logo Yazılım',
  'NETAS.IS': 'Netaş Telekomünikasyon',
  'KAREL.IS': 'Karel Elektronik',
  'KONTR.IS': 'Kontrolmatik Teknoloji',
  'SMART.IS': 'Smart Güneş Enerji',
  // Enerji & Petrokimya
  'TUPRS.IS': 'Tüpraş',
  'PETKM.IS': 'Petkim',
  'SASA.IS': 'SASA Polyester',
  'AKSEN.IS': 'Aksa Enerji',
  'AYDEM.IS': 'Aydem Yenilenebilir Enerji',
  'AYEN.IS': 'Ayen Enerji',
  'ODAS.IS': 'Odaş Elektrik',
  'ENJSA.IS': 'Enerjisa Enerji',
  'ZOREN.IS': 'Zorlu Enerji',
  'IPEKE.IS': 'İpek Doğal Enerji',
  'PRKME.IS': 'Park Elektrik',
  'GEREL.IS': 'Gersan Elektrik',
  // Savunma & Sanayi
  'ASELS.IS': 'Aselsan',
  'TKFEN.IS': 'Tekfen Holding',
  'OTKAR.IS': 'Otokar Otobüs',
  // Otomotiv
  'FROTO.IS': 'Ford Otosan',
  'TOASO.IS': 'Tofaş Oto Fab.',
  'TTRAK.IS': 'Türk Traktör',
  'DOAS.IS': 'Doğuş Otomotiv',
  'ASUZU.IS': 'Anadolu Isuzu',
  'KARSN.IS': 'Karsan Otomotiv',
  // Beyaz Eşya & Elektronik
  'ARCLK.IS': 'Arçelik',
  'VESTL.IS': 'Vestel Elektronik',
  'VESBE.IS': 'Vestel Beyaz Eşya',
  // Cam & İnşaat Malzeme
  'SISE.IS': 'Şişe Cam',
  'ENKA.IS': 'ENKA İnşaat',
  'CIMSA.IS': 'Çimsa Çimento',
  'NUHCM.IS': 'Nuh Çimento',
  'BUCIM.IS': 'Bursa Çimento',
  'OYAKC.IS': 'Oyak Çimento',
  'UNYEC.IS': 'Ünye Çimento',
  // Demir & Çelik & Metal
  'EREGL.IS': 'Ereğli Demir Çelik',
  'KRDMD.IS': 'Kardemir (D)',
  'ERBOS.IS': 'Erbosan',
  'SARKY.IS': 'Sarkuysan',
  'EGEEN.IS': 'Ege Endüstri',
  'PARSN.IS': 'Parsan',
  'TMSN.IS': 'Tümosan Motor',
  // Lastik & Plastik
  'BRISA.IS': 'Brisa Bridgestone',
  'KORDS.IS': 'Kordsa Teknik',
  // GYO
  'EKGYO.IS': 'Emlak Konut GYO',
  'ISGYO.IS': 'İş GYO',
  'TRGYO.IS': 'Torunlar GYO',
  'ZRGYO.IS': 'Ziraat GYO',
  'HLGYO.IS': 'Halk GYO',
  // Madencilik
  'KOZAL.IS': 'Koza Altın',
  'KOZAA.IS': 'Koza Madencilik',
  // Perakende & Gıda
  'MGROS.IS': 'Migros Ticaret',
  'CARFA.IS': 'CarrefourSA',
  'SOKM.IS': 'Şok Marketler',
  'BIMAS.IS': 'BİM Mağazalar',
  'ULKER.IS': 'Ülker Bisküvi',
  'BANVT.IS': 'Banvit',
  'CCOLA.IS': 'Coca-Cola İçecek',
  // Tekstil & Moda
  'MAVI.IS': 'Mavi Giyim',
  // Kimya & Tarım
  'GUBRF.IS': 'Gübre Fabrikaları',
  'SODA.IS': 'Soda Sanayii',
  'HEKTS.IS': 'Hektaş Ticaret',
  // İlaç & Sağlık
  'DEVA.IS': 'Deva Holding',
  'ECILC.IS': 'Eczacıbaşı İlaç',
  'SELEC.IS': 'Selçuk Ecza Deposu',
  'MPARK.IS': 'Medical Park',
  // Sigorta
  'TURSG.IS': 'Türkiye Sigorta',
  // Diğer
  'TKNSA.IS': 'Teknosa',
};

/// Geriye dönük uyumluluk için liste hali
List<String> get bist100Stocks => bist100StocksMap.keys.toList();

/// Altın alt kategorisi → PriceService'in kullandığı dahili ticker
/// ALTIN_* semboller XAUTRY=X üzerinden hesaplanır
const goldTickerMap = <String, String>{
  '22 Ayar Gram Altın': 'ALTIN_GRAM',
  'Çeyrek Altın':       'ALTIN_CEYREK',
  'Yarım Altın':        'ALTIN_YARIM',
  'Ata Altını':         'ALTIN_ATA',
  'Reşat Altını':       'ALTIN_RESAT',
  'Cumhuriyet Altını':  'ALTIN_CUMHURIYET',
  'Altın (Ons)':        'XAUUSD=X', // USD - Yahoo Finance sembolü
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
