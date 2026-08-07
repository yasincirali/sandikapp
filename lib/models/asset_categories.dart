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
  bist100('BIST Hisseleri', 'Borsa İstanbul\'da işlem gören hisse senetleri'),
  other('Diğer Hisseler', 'Listede olmayan hisse senetleri');

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

/// Tüm BIST hisseleri — Yahoo Finance sembolü → şirket adı
///
/// Not: İsim geriye dönük uyumluluk için `bist100StocksMap` kaldı, ancak
/// kapsam BIST 100 ile SINIRLI DEĞİLDİR — BIST'te işlem gören tüm pazarlar
/// (Yıldız, Ana, Alt, Yakın İzleme) dahildir. Kullanıcı GSDHO gibi BIST 100
/// dışı hisseleri de ekleyebilmeli; liste 91 sembolle sınırlıyken bunlar
/// seçicide hiç görünmüyordu.
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

  // ─── BIST 100 dışı hisseler ───────────────────────────────────────────────
  // Aşağıdakiler BIST 100 endeksinde olmayan ama borsada işlem gören
  // hisselerdir. Kullanıcı bunları da portföyüne ekleyebilmelidir.

  // Bankacılık, Finans & Aracı Kurumlar
  'TSKB.IS': 'T.S.K.B.',
  'ICBCT.IS': 'ICBC Turkey Bank',
  'QNBFB.IS': 'QNB Finansbank',
  'GLBMD.IS': 'Global Menkul Değerler',
  'ISMEN.IS': 'İş Yatırım Menkul Değerler',
  'GEDIK.IS': 'Gedik Yatırım Menkul Değerler',
  'INFO.IS': 'İnfo Yatırım Menkul Değerler',
  'OSMEN.IS': 'Osmanlı Yatırım Menkul Değerler',
  'AGYO.IS': 'Atakule GYO',
  'GARFA.IS': 'Garanti Faktoring',
  'LIDFA.IS': 'Lider Faktoring',
  'SEKFK.IS': 'Şeker Finansal Kiralama',
  'ISFIN.IS': 'İş Finansal Kiralama',
  'CRDFA.IS': 'Creditwest Faktoring',
  'VAKFN.IS': 'Vakıf Finansal Kiralama',

  // Holding & Yatırım
  'GSDHO.IS': 'GSD Holding',
  'GSDDE.IS': 'GSD Denizcilik Gayrimenkul',
  'ECZYT.IS': 'Eczacıbaşı Yatırım',
  'IHLAS.IS': 'İhlas Holding',
  'IHGZT.IS': 'İhlas Gazetecilik',
  'IEYHO.IS': 'Işıklar Enerji ve Yapı Holding',
  'ITTFH.IS': 'İttifak Holding',
  'ATAGY.IS': 'Ata GYO',
  'BRKO.IS': 'Birko Mensucat',
  'METRO.IS': 'Metro Holding',
  'NTHOL.IS': 'Net Holding',
  'TKURU.IS': 'Taze Kuru Gıda',
  'EUHOL.IS': 'Euro Yatırım Holding',
  'MZHLD.IS': 'Mazhar Zorlu Holding',
  'POLHO.IS': 'Polisan Holding',
  'ORGE.IS': 'Orge Enerji Elektrik',
  'BOSSA.IS': 'Bossa Ticaret',

  // Teknoloji, Yazılım & Bilişim
  'ARENA.IS': 'Arena Bilgisayar',
  'ARDYZ.IS': 'ARD Bilişim Teknolojileri',
  'DGATE.IS': 'Datagate Bilgisayar',
  'DESPC.IS': 'Despec Bilgisayar',
  'INDES.IS': 'İndeks Bilgisayar',
  'ESCOM.IS': 'Escort Teknoloji',
  'FONET.IS': 'Fonet Bilgi Teknolojileri',
  'MIATK.IS': 'Mia Teknoloji',
  'MOBTL.IS': 'Mobiltel İletişim',
  'PKART.IS': 'Plastikkart',
  'ALCTL.IS': 'Alcatel Lucent Teleteknik',
  'ANELE.IS': 'Anel Elektrik',
  'PENTA.IS': 'Penta Teknoloji',
  'REEDR.IS': 'Reeder Teknoloji',
  'VBTYZ.IS': 'VBT Yazılım',
  'LINK.IS': 'Link Bilgisayar',
  'KFEIN.IS': 'Kafein Yazılım',
  'SMRTG.IS': 'Smart Güneş Enerjisi',
  'ISATR.IS': 'İş Bankası (A)',
  'ISBTR.IS': 'İş Bankası (B)',

  // Enerji & Elektrik
  'AKSA.IS': 'Aksa Akrilik',
  'AKFYE.IS': 'Akfen Yenilenebilir Enerji',
  'ALFAS.IS': 'Alfa Solar Enerji',
  'BIOEN.IS': 'Biotrend Enerji',
  'CANTE.IS': 'Çan2 Termik',
  'CONSE.IS': 'Consus Enerji',
  'ESEN.IS': 'Esenboğa Elektrik',
  'GWIND.IS': 'Galata Wind Enerji',
  'HUNER.IS': 'Hun Yenilenebilir Enerji',
  'MAGEN.IS': 'Margün Enerji',
  'NATEN.IS': 'Naturel Yenilenebilir Enerji',
  'PAMEL.IS': 'Pamel Yenilenebilir Elektrik',
  'ZEDUR.IS': 'Zedur Enerji',
  'ARASE.IS': 'Aras Elektrik Dağıtım',
  'ENERY.IS': 'Enerya Enerji',
  'AHGZT.IS': 'Ahlatcı Doğalgaz',
  'BASGZ.IS': 'Başkent Doğalgaz',
  'AKENR.IS': 'Ak Enerji',

  // Sanayi, Makine & Metal
  'ALKA.IS': 'Alkim Kağıt',
  'ALKIM.IS': 'Alkim Alkali Kimya',
  'BFREN.IS': 'Bosch Fren Sistemleri',
  'CEMTS.IS': 'Çemtaş Çelik',
  'DITAS.IS': 'Ditaş Doğan',
  'DOKTA.IS': 'Döktaş Dökümcülük',
  'FMIZP.IS': 'Federal-Mogul İzmit Piston',
  'JANTS.IS': 'Jantsa Jant Sanayi',
  'KATMR.IS': 'Katmerciler Ekipman',
  'MAKTK.IS': 'Makina Takım Endüstrisi',
  'ORMA.IS': 'Orma Orman Mahsulleri',
  'SILVR.IS': 'Silverline Endüstri',
  'ISDMR.IS': 'İskenderun Demir Çelik',
  'CUSAN.IS': 'Çuhadaroğlu Metal',
  'BURCE.IS': 'Burçelik',
  'BURVA.IS': 'Burçelik Vana',
  'DMSAS.IS': 'Demisaş Döküm',
  'EMKEL.IS': 'Emek Elektrik',
  'GEDZA.IS': 'Gediz Ambalaj',
  'IZMDC.IS': 'İzmir Demir Çelik',
  'KLMSN.IS': 'Klimasan Klima',
  'SAYAS.IS': 'Say Reklamcılık',
  'SANFM.IS': 'Sanifoam Sünger',
  'ULUSE.IS': 'Ulusoy Elektrik',
  'YUNSA.IS': 'Yünsa Yünlü Sanayi',
  'ARSAN.IS': 'Arsan Tekstil',

  // Gıda, Tarım & İçecek
  'AEFES.IS': 'Anadolu Efes',
  'TATGD.IS': 'Tat Gıda',
  'PNSUT.IS': 'Pınar Süt',
  'PETUN.IS': 'Pınar Et ve Un',
  'KERVT.IS': 'Kerevitaş Gıda',
  'TUKAS.IS': 'Tukaş Gıda',
  'KNFRT.IS': 'Konfrut Gıda',
  'FRIGO.IS': 'Frigo Pak Gıda',
  'SELVA.IS': 'Selva Gıda',
  'AVOD.IS': 'A.V.O.D. Gıda',
  'ATAKP.IS': 'Atakey Patates',
  'CEMAS.IS': 'Çemaş Döküm',
  'GENTS.IS': 'Gentaş Genel Metal',
  'KTSKR.IS': 'Kütahya Şeker',
  'OFSYM.IS': 'Ofis Yem Gıda',
  'PENGD.IS': 'Penguen Gıda',
  'ULUUN.IS': 'Ulusoy Un',
  'YAYLA.IS': 'Yayla Agro Gıda',
  'ORCAY.IS': 'Orçay Ortaköy Çay',
  'DARDL.IS': 'Dardanel Önentaş',
  'MERKO.IS': 'Merko Gıda',
  'VANGD.IS': 'Van Et Entegre',

  // Perakende & Ticaret
  'BIZIM.IS': 'Bizim Toptan Satış',
  'VAKKO.IS': 'Vakko Tekstil',
  'DESA.IS': 'Desa Deri',
  'DAGI.IS': 'Dagi Yatırım Holding',
  'KIMMR.IS': 'Kim Mağazacılık',
  'MEPET.IS': 'Mepet Metro Petrol',
  'MARTI.IS': 'Martı Otel İşletmeleri',
  'MIPAZ.IS': 'Milpa Ticari',
  'SANKO.IS': 'Sanko Pazarlama',
  'SUWEN.IS': 'Suwen Tekstil',
  'YATAS.IS': 'Yataş Yatak',
  'YONGA.IS': 'Yonga Mobilya',
  'INTEM.IS': 'İntema İnşaat',
  'BRKSN.IS': 'Berkosan Yalıtım',

  // İnşaat, Çimento & Gayrimenkul
  'AKCNS.IS': 'Akçansa Çimento',
  'AFYON.IS': 'Afyon Çimento',
  'BASCM.IS': 'Baştaş Çimento',
  'BSOKE.IS': 'Batısöke Çimento',
  'CMBTN.IS': 'Çimbeton',
  'CMENT.IS': 'Çimentaş',
  'GOLTS.IS': 'Göltaş Çimento',
  'KONYA.IS': 'Konya Çimento',
  'MRDIN.IS': 'Mardin Çimento',
  'USAK.IS': 'Uşak Seramik',
  'YBTAS.IS': 'Yibitaş Yozgat',
  'EDIP.IS': 'Edip Gayrimenkul',
  'ALGYO.IS': 'Alarko GYO',
  'AVGYO.IS': 'Avrasya GYO',
  'DZGYO.IS': 'Deniz GYO',
  'IDGYO.IS': 'İdealist GYO',
  'KLGYO.IS': 'Kiler GYO',
  'MRGYO.IS': 'Martı GYO',
  'NUGYO.IS': 'Nurol GYO',
  'OZGYO.IS': 'Özderici GYO',
  'PAGYO.IS': 'Panora GYO',
  'PEKGY.IS': 'Peker GYO',
  'RYGYO.IS': 'Reysaş GYO',
  'SNGYO.IS': 'Sinpaş GYO',
  'SRVGY.IS': 'Servet GYO',
  'TDGYO.IS': 'Trend GYO',
  'VKGYO.IS': 'Vakıf GYO',
  'YGYO.IS': 'Yeşil GYO',
  'YKGYO.IS': 'Yapı Kredi Koray GYO',
  'BAYRK.IS': 'Bayrak EBT',

  // Sağlık & İlaç & Kimya
  'LKMNH.IS': 'Lokman Hekim Sağlık',
  'RTALB.IS': 'RTA Laboratuvarları',
  'SEYKM.IS': 'Seyitler Kimya',
  'BAGFS.IS': 'Bagfaş Bandırma Gübre',
  'EGGUB.IS': 'Ege Gübre',
  'ACSEL.IS': 'Acıselsan Acıpayam Selüloz',
  'ATATP.IS': 'ATA Teknoloji Platformu',
  'DYOBY.IS': 'DYO Boya',
  'MRSHL.IS': 'Marshall Boya',
  'SANEL.IS': 'Sanel Mühendislik',
  'BIOTK.IS': 'Biotek Tarım',

  // Ulaştırma & Lojistik & Turizm
  'RYSAS.IS': 'Reysaş Taşımacılık',
  'BEYAZ.IS': 'Beyaz Filo',
  'AVTUR.IS': 'Avrasya Petrol Turistik',
  'AYCES.IS': 'Altınyunus Çeşme',
  'MAALT.IS': 'Marmaris Altınyunus',
  'METUR.IS': 'Metemtur Otelcilik',
  'PKENT.IS': 'Petrokent Turizm',
  'TEKTU.IS': 'Tek-Art Turizm',
  'ULAS.IS': 'Ulaşlar Turizm',
  'UTPYA.IS': 'Utopya Turizm',
  'SNPAM.IS': 'Sönmez Pamuklu',
  'TLMAN.IS': 'Trabzon Liman İşletmeciliği',

  // Sigorta
  'AKGRT.IS': 'Aksigorta',
  'ANHYT.IS': 'Anadolu Hayat Emeklilik',
  'ANSGR.IS': 'Anadolu Sigorta',
  'RAYSG.IS': 'Ray Sigorta',
  'AGESA.IS': 'Agesa Hayat ve Emeklilik',

  // Medya, Eğitim & Hizmet
  'HURGZ.IS': 'Hürriyet Gazetecilik',
  'DGNMO.IS': 'Doğan Trend Otomotiv',
  'PRDGS.IS': 'Pardus Girişim',
  'ADESE.IS': 'Adese Gayrimenkul',
  'BLCYT.IS': 'Bilici Yatırım',
  'EGEPO.IS': 'Ege Profil',
  'KRSTL.IS': 'Kristal Kola',
  'PSDTC.IS': 'Pergamon Dış Ticaret',
  'SEKUR.IS': 'Sekuro Plastik',
  'UFUK.IS': 'Ufuk Yatırım',
  'IZFAS.IS': 'İzmir Fırça',
  'BNTAS.IS': 'Bantaş Ambalaj',
  'KAPLM.IS': 'Kaplamin Ambalaj',
  'VKING.IS': 'Viking Kağıt',
  'DURDO.IS': 'Duran Doğan Basım',
  'IZINV.IS': 'İz Yatırım Holding',
  'TRILC.IS': 'Turk İlaç ve Serum',
  'EUPWR.IS': 'Europower Enerji',
  'CWENE.IS': 'CW Enerji',
  'KZBGY.IS': 'Kızılbük GYO',
  'OBASE.IS': 'Obase Bilgisayar',
  'BINHO.IS': 'Bin Holding',
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
