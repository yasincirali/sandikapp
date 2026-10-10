import '../services/remote_config_service.dart';
import 'asset_categories.dart';
import 'asset_type.dart';

/// İşlem türü — audit trail için.
/// - buy: alım (default, geriye dönük uyumluluk)
/// - sell: satım (refAssetId ile ilgili buy lot'una bağlı; net miktarda düşer)
/// - delete_log: silinen bir buy lot'unun mezar taşı (portföyden çıkar, işlem
///   defterinde "SILDI" olarak kalır)
/// - dividend: nakit temettü. **Miktarı DEĞİŞTİRMEZ** — eline geçen parayı
///   `dividendAmount` alanında taşır. Getiriye eklenir, pozisyona eklenmez.
enum AssetKind {
  buy,
  sell,
  deleteLog,
  dividend;

  String get dbValue {
    switch (this) {
      case AssetKind.buy:
        return 'buy';
      case AssetKind.sell:
        return 'sell';
      case AssetKind.deleteLog:
        return 'delete_log';
      case AssetKind.dividend:
        return 'dividend';
    }
  }

  static AssetKind fromDb(String? v) {
    switch (v) {
      case 'sell':
        return AssetKind.sell;
      case 'delete_log':
        return AssetKind.deleteLog;
      case 'dividend':
        return AssetKind.dividend;
      case 'buy':
      case null:
      default:
        return AssetKind.buy;
    }
  }
}

/// Miktar birimi etiketi — uygulamanın TEK kaynağı.
///
/// ## Neden serbest fonksiyon
/// Etiket iki yerde gerekiyor: kaydedilmiş bir [Asset] ve henüz
/// kaydedilmemiş bir sepet satırı (`BulkCartItem`). İkisi ortak bir taban
/// sınıfı paylaşmıyor. Mantık `Asset`'in içinde kaldığı sürece sepet
/// tarafı kendi kopyasını tutmak zorundaydı — ve tuttu:
/// `bulk_add_asset_screen._unitLabel()` yalnızca `unitType`'a bakıyor,
/// `type`'ı hiç sormuyordu. Sonuç, hisse/fon için sepette **"adet"**,
/// kaydedildikten sonra **"lot"** yazmasıydı: aynı varlık iki ekranda iki
/// farklı birim.
///
/// Kopyayı silmek yerine mantığı dışarı almak, bir sonraki çağrı yerinin
/// de doğru başlamasını sağlıyor.
String birimEtiketi({
  required AssetType type,
  required String unitType,
  required String currency,
  String? currencySymbol,
  String ticker = '',
}) {
  switch (type) {
    case AssetType.doviz:
      return currencySymbol ?? currency.toUpperCase();
    case AssetType.hisse:
    case AssetType.fon:
      // "adet" DEĞİL: borsada işlem birimi lot'tur.
      return 'lot';
    case AssetType.altin:
    case AssetType.emtia:
      switch (unitType) {
        case 'gram':
        case 'gr':
          return 'gr';
        case 'ounce':
        case 'oz':
          return 'oz';
        case 'kilogram':
        case 'kg':
          return 'kg';
        case 'liter':
        case 'lt':
          return 'lt';
        case 'barrel':
        case 'bbl':
          return 'bbl';
        default:
          // Çeyrek/yarım/ata altın: `unitType == 'piece'`.
          return 'adet';
      }
    case AssetType.kripto:
      // Coin'in kendi kodu: "0,0045 BTC". Kod çözülemezse "adet" — boş
      // birim ekranda sayıyı çıplak bırakırdı.
      return kriptoKodu(ticker) ?? 'adet';
    case AssetType.bes:
      // Emeklilik fonu payı; BES'te "lot" denmez.
      return 'pay';
    case AssetType.mevduat:
      // Birim değerli pay (bkz. `mevduat_hesabi.dart`). Ekranlar mevduatta
      // miktarı değil tutarı gösterir; etiket yalnız ham satırlarda çıkar.
      return 'birim';
    case AssetType.eurobond:
      // Miktar nominal tutardır ("10.000 nominal"), adet değil.
      return 'nominal';
    case AssetType.diger:
      return 'adet';
  }
}

/// Kripto miktarında gösterilecek en çok ondalık hane.
///
/// 8 = 1 satoshi (0,00000001 BTC). Binance/BtcTurk miktarı da bu hassasiyette
/// gösterir. Daha fazlası kayan nokta gürültüsüdür.
const int kriptoAzamiOndalik = 8;

/// [miktar]'ı kaybetmeden göstermek için gereken ondalık hane (en çok
/// [azami]). 0,004521 → 6; 1,5 → 1; 2 → 0.
///
/// Sabit 2 hane kriptoda miktarı SİLER: 0,0045 BTC "0,00" görünür. Sabit 8
/// hane ise "1,50000000 ETH" gibi okunmaz bir satır üretir. Gereken kadar
/// hane yazmak ikisini de önler.
int gerekenOndalik(double miktar, {int azami = kriptoAzamiOndalik}) {
  for (var d = 0; d < azami; d++) {
    final olcek = _onUssu(d);
    final yuvarlak = (miktar * olcek).roundToDouble() / olcek;
    // Göreli tolerans: büyük miktarlarda mutlak 1e-12 anlamsız.
    if ((miktar - yuvarlak).abs() <= 1e-12 * (miktar.abs() > 1 ? miktar.abs() : 1)) {
      return d;
    }
  }
  return azami;
}

double _onUssu(int d) {
  var v = 1.0;
  for (var i = 0; i < d; i++) {
    v *= 10;
  }
  return v;
}

class Asset {
  final String id;
  final String userId;
  String name;
  String ticker;
  AssetType type;
  String? subCategory; // Altın: gr22, çeyrek vb. | Fon: bankFund, bist100 vb. | Hisse: StockSubCategory etiketi ya da abd (bkz. orası)
  String unitType; // Birim: piece, gram, ounce, etc. (varsayılan: piece)
  double quantity;
  double purchasePrice;
  String currency;
  double currentPrice;
  DateTime? lastUpdated;
  final DateTime addedDate;
  String notes;
  bool isManualPrice;
  double purchaseFxRate;

  /// İşlem türü — buy (default) / sell / delete_log
  final AssetKind kind;

  /// Sell veya delete_log satırlarının hangi buy lot'una referans verdiği.
  /// null → bağımsız kayıt (buy için normal)
  final String? refAssetId;

  /// Sell işleminde gerçekleşen birim satış fiyatı (raporlama/kar-zarar için).
  final double? sellPrice;

  /// Satış GÜNÜNÜN kuru (1 birim döviz = ? TL) — yalnız dövizli sell
  /// satırlarında, 0111 sütunu `sell_fx_rate`.
  ///
  /// ## Neden (2026-10-05, kullanıcı onayı)
  /// Satış satırı [purchaseFxRate]'te ALIM kurunu (pozisyonun ağırlıklı alım
  /// kurunu) taşır; ele geçen tutar da o kurla TL'ye çevriliyordu. 30 TL'den
  /// alınıp 41 TL'den satılan dolar varlığın kur kazancı gerçekleşen
  /// kâra ve nakit akışına (para ağırlıklı getiri, XIRR) hiç girmiyordu.
  /// Maliyet yine alım kuruyla kalır (bankacılık standardı, [totalCostTRY]);
  /// yalnız SATIŞ TARAFI bu kurla çevrilir.
  ///
  /// `null` → eski kayıt ya da `satis_gunu_kuru` bayrağı kapalıyken yazılmış
  /// satış: hesap birebir eski davranışa (alım kuru) düşer.
  final double? sellFxRate;

  /// Satış tarafını TL'ye çeviren kur: satış günü kuru varsa o, yoksa alım
  /// kuru (eski davranış). Komisyon da satışla aynı anda ödendiği için bu
  /// kurdan çevrilir.
  double get satisKuru => sellFxRate ?? purchaseFxRate;

  /// İşlem komisyonu + masrafı — varlığın PARA BİRİMİNDE (purchasePrice ile
  /// aynı birim), işlem başına toplam (birim başına değil).
  ///
  /// Alımda maliyeti artırır. Komisyon hesaba katılmazsa kâr olduğundan
  /// yüksek görünür. Varsayılan 0 → kullanıcı girmedikçe eski davranış.
  double commission;

  /// Nakit temettü tutarı — yalnızca `kind == dividend` satırlarında anlamlı.
  /// Varlığın para biriminde, ELE GEÇEN NET tutar (stopaj sonrası).
  ///
  /// Temettü satırı miktarı değiştirmez; bu tutar realize edilmiş getiri
  /// olarak kâr/zarara eklenir.
  double dividendAmount;

  /// Bu silme işleminde kaldırılan ledger kaydı sayısı — yalnızca
  /// `kind == deleteLog` satırlarında anlamlı.
  ///
  /// Silme artık lot başına değil, POZİSYON başına tek satır yazar; kaç
  /// kaydın (alım + satım + temettü) gittiği burada taşınır. 0 → eski
  /// kayıt, sayı bilinmiyor.
  final int deletedCount;

  /// Yumuşak silme damgası. NULL → aktif kayıt.
  ///
  /// Silme lot'ları FİZİKSEL olarak kaldırmaz; damgalar. Böylece varlığın
  /// Alım/Satım/Temettü satırları hareket geçmişinde kalır ve kullanıcı
  /// "ne aldım, ne sattım, sonra sildim" zincirini okuyabilir.
  ///
  /// Damgalı kayıtlar portföy toplamlarına, aggregate'e ve grafiğe
  /// GİRMEZ — bkz. [isActive].
  final DateTime? deletedAt;

  /// Bağlı sözleşme (`sozlesmeler.id`, 0088) — yalnız mevduat ve BES
  /// lotlarında dolu. Faiz/vade ya da katkı planı oradadır; lot bakiyeyi
  /// taşır (bkz. `models/sozlesme.dart`).
  final String? sozlesmeId;

  /// Satırın SUNUCUYA girildiği an (0095 `assets.created_at`). İstemci
  /// yazmaz — tetikleyici her girişte ve ekonomik alan düzenlemesinde
  /// `now()` basar. Yalnız Yarış'ın "seçimlerinin getirisi" okur:
  /// [addedDate] bundan 3 günden fazla gerideyse kayıt girildiği anda
  /// yapılmış sayılır (geriye tarihli kayıtla yarış hilesi; bkz.
  /// `secim_getirisi.dart`). `null` → sütun öncesi kopya; tarih olduğu gibi.
  final DateTime? createdAt;

  /// Lotun portföyü (`portfoyler.id`, 0133). `null` = **Ana portföy** —
  /// çoklu portföy öncesi bütün satırlar ve eski sürümün yazdığı her satır.
  ///
  /// ## Neden lot başına (çoklu portföy, 2026-10-10)
  /// Portföy bir GÖRÜNÜM süzgecidir: kapsamın lotları portföye göre süzülür,
  /// toplam/seri/getiri motorları değişmeden o alt kümeyi hesaplar (bkz.
  /// `gorunum_kapsami.dart`). Satış/temettü/silme kaydı pozisyonun
  /// portföyünü taşır ki portföy defteri kendi içinde kapansın (satış
  /// portföy dışına taşmaz). Ortağın lotundaki değer bu kullanıcı için
  /// anlamsızdır; ortak görünümü portföy süzgecine hiç girmez.
  final String? portfoyId;

  /// YALNIZ ekran görünümü ([Position.asDisplayAsset]): pozisyonun lotları
  /// birden çok portföye dağılmış mı ("Tümü" görünümünde aynı sembol iki
  /// portföyde). Sunucuya yazılmaz. Doğruysa [portfoyId] anlamsızdır
  /// (`null`); al/sat/temettü önce hangi portföyün pozisyonu olduğunu sorar
  /// (`portfoy_secim_sayfasi.dart`) — aksi hâlde satış Ana'ya düşer ve
  /// Ana'da eksi, öbür portföyde fazla miktar kalırdı.
  final bool portfoyKarisik;

  /// Sunucudaki `ticker` sütununun OKUNDUĞU hâli — yalnızca [kanonikTicker]
  /// onu değiştirdiyse dolu (öneksiz eski fon kodu `AFT` → `TEFAS:AFT`).
  ///
  /// Neden: düzeltme OKUMA tarafında (bulgu #2, 2026-09-29). [updateAsset]
  /// gövdenin tamamını yazıyor; bu alan olmasa her fiyat turu eski satırı
  /// sessizce `TEFAS:AFT`'ye çevirirdi — istenmeyen bir veri göçü. Kullanıcı
  /// sembolü elle değiştirirse ([ticker] artık bu kaydın kanonik biçimi
  /// değilse) yeni değer yazılır; bkz. [toSupabase].
  String? _kayitliTicker;

  Asset({
    required this.id,
    required this.userId,
    required this.name,
    required this.ticker,
    required this.type,
    required this.quantity,
    required this.purchasePrice,
    required this.currency,
    required this.notes,
    this.subCategory,
    this.unitType = 'piece',
    this.purchaseFxRate = 1.0,
    double? currentPrice,
    this.lastUpdated,
    DateTime? addedDate,
    bool? isManualPrice,
    this.kind = AssetKind.buy,
    this.refAssetId,
    this.sellPrice,
    this.sellFxRate,
    this.commission = 0,
    this.dividendAmount = 0,
    this.deletedCount = 0,
    this.deletedAt,
    this.sozlesmeId,
    this.createdAt,
    this.portfoyId,
    this.portfoyKarisik = false,
  })  : currentPrice = currentPrice ?? purchasePrice,
        addedDate = addedDate ?? DateTime.now(),
        isManualPrice = isManualPrice ?? ticker.trim().isEmpty;

  bool get isBuy => kind == AssetKind.buy;
  bool get isSell => kind == AssetKind.sell;
  bool get isDeleteLog => kind == AssetKind.deleteLog;
  bool get isDividend => kind == AssetKind.dividend;

  /// Yumuşak silinmiş mi? Damgalı kayıtlar hareket GEÇMİŞİNDE durur ama
  /// hiçbir hesaba girmez.
  bool get isDeleted => deletedAt != null;

  /// Portföy hesaplarına giren kayıt: silinmemiş VE mezar taşı değil.
  ///
  /// Toplam, aggregate, grafik — hepsi bu filtreden geçmeli. Yalnızca
  /// hareket listesi ham ledger'ı olduğu gibi gösterir.
  bool get isActive => deletedAt == null && kind != AssetKind.deleteLog;

  /// Portföy net pozisyonuna katkı gösteren tek satırlar buy'lar. Sell'ler
  /// (negatif) ve delete_log'lar aggregator'da özel işlenir.
  ///
  /// DİKKAT: `!isBuy` ile "sell demektir" varsayımı YAPMA — temettü satırları
  /// da buy değildir ama miktara hiç dokunmaz. Miktar hesabında bu getter'ı
  /// veya açık `isSell` kontrolü kullan.
  bool get affectsPosition => kind == AssetKind.buy;

  /// Miktar hesabına hiç girmeyen satırlar (nakit hareketi / mezar taşı).
  bool get isQuantityNeutral =>
      kind == AssetKind.dividend || kind == AssetKind.deleteLog;

  /// TRY cinsinden temettü — alım kuruyla değil, TEMETTÜ ANININ kuruyla
  /// çevrilir. `purchaseFxRate` temettü satırında ödeme günü kurunu taşır.
  double get dividendTRY => dividendAmount * purchaseFxRate;

  /// Satıştan ELE GEÇEN tutar (TRY) — nakit akışı hesapları için.
  ///
  /// [totalCostTRY] bu iş için YANLIŞ araçtır: o, lot'un alım maliyetidir.
  /// Kâr/zararla satılmış bir pozisyonda cepten çıkan/cebe giren para
  /// maliyet değil, satış fiyatıdır. Dönem getirisini para giriş-çıkışından
  /// arındırırken bu fark doğrudan sonuca yansır.
  ///
  /// [sellPrice] yalnızca sell satırlarında ve migration sonrası kayıtlarda
  /// dolu; boşsa maliyete düşülür (eski davranış) — yaklaşık ama sıfırdan
  /// iyi. Komisyon satışta ele geçeni AZALTIR, bu yüzden çıkarılır.
  /// Kur [satisKuru]: satış günü kuru kayıtlıysa o (0111), yoksa alım kuru.
  double get sellProceedsTRY {
    final unit = sellPrice ?? purchasePrice;
    return (quantity * unit - commission) * satisKuru;
  }

  /// Toplam maliyet — komisyon DAHİL (gerçekte cebinden çıkan para).
  double get totalCost => quantity * purchasePrice + commission;
  double get totalValue => quantity * currentPrice;

  /// Maliyet TRY cinsinden — alım anındaki kur sabit tutulur (bankacılık
  /// standardı). Komisyon da aynı kurdan çevrilir: işlemle aynı anda ödendi.
  double get totalCostTRY =>
      (quantity * purchasePrice + commission) * purchaseFxRate;
  double get gainLoss => totalValue - totalCost;
  double get gainLossPercentage =>
      totalCost > 0 ? (gainLoss / totalCost) * 100 : 0;

  /// Temizlenmiş ticker kodu — sadece fon ve hisse için anlamlı
  String? get displayTicker {
    if (ticker.trim().isEmpty) return null;
    // `TEFAS:` öneki de atılır (2026-09-29): eski fon kayıtları kodu
    // `TEFAS:IJC` biçiminde taşıyor, yenileri öneksiz (`DLY`). Aynı listede
    // biri önekli biri öneksiz görünüyordu (Silinenler, hareketler).
    final t = ticker
        .replaceFirst(RegExp(r'^TEFAS:', caseSensitive: false), '')
        .replaceAll('.IS', '')
        .replaceAll('=X', '')
        .trim();
    return t.isEmpty ? null : t;
  }

  /// BES lotunun sözleşme kurumu. Lot adı `kurum · fon` ya da
  /// `kurum · fon · Devlet` biçimindedir (`BesFormu` › `adUret`). Ad bu
  /// biçimde değilse (eski kayıt, elle değiştirilmiş) `null`.
  String? get besKurumu {
    if (type != AssetType.bes) return null;
    final i = name.indexOf(' · ');
    return i > 0 ? name.substring(0, i).trim() : null;
  }

  /// Fon/Hisse için ticker gösterilmeli mi?
  bool get showTicker =>
      displayTicker != null &&
      (type == AssetType.fon ||
          type == AssetType.hisse ||
          // BES lotunun kodu emeklilik fonudur (AH5); mevduatın sembolü
          // sözleşme id'sidir, gösterilmez.
          type == AssetType.bes);

  /// ABD borsasında işlem gören hisse/ETF mi (2026-10-08, bayrak `abd_hisse`).
  ///
  /// Ayrı bir [AssetType] DEĞİL: `type='hisse'`, `sub_category='abd'`,
  /// `currency='USD'`. Eski sürüm yeni enum değerini "Diğer"e düşürür ve
  /// tam satır yazımında türü ezerdi; hisse + USD ise eski sürümde de
  /// Yahoo + USDTRY ile doğru fiyatlanır. Para birimine BAKILMAZ: kimlik
  /// alt kategoridir, para birimi ondan türer (form USD'ye kilitler).
  bool get abdHissesi =>
      type == AssetType.hisse && subCategory == StockSubCategory.abd.name;

  /// Kripto ise coin kodu (`BTC`), değilse `null`.
  String? get kriptoKod => type == AssetType.kripto ? kriptoKodu(ticker) : null;

  /// Nakit temettü kaydedilebilir mi?
  ///
  /// Yalnızca **hisse** senedi temettü dağıtır. Altın/döviz/emtia fiziksel ya
  /// da parasal varlıktır, mevduatın getirisi faizdir ve kendi alanlarında
  /// izlenir. Fonlar da dağıtım yapabilir ama TEFAS'ta bu fiyata yansıdığı
  /// için ayrıca girilmesi çift sayıma yol açar.
  bool get supportsDividend => type == AssetType.hisse;

  /// Döviz varlığı için para sembolü ($ € £ vb.)
  String? get currencySymbol =>
      type == AssetType.doviz ? currencySymbolFor(ticker, currency) : null;

  /// Miktar için kullanılacak birim etiketi (adet/lot/gr/oz/₺-$ vb.).
  /// Ekranlarda "1 lot", "2,5 gr", "$100" gibi göstermek için kullanılır.
  String get unitLabel => birimEtiketi(
        type: type,
        unitType: unitType,
        currency: currency,
        currencySymbol: currencySymbol,
        ticker: ticker,
      );

  /// Birim para birimden önce mi gelmeli? (Döviz sembolleri prefix, diğerleri suffix.)
  bool get unitIsPrefix => type == AssetType.doviz;

  /// Miktar için gösterilecek ondalık hane sayısı.
  ///
  /// Tam sayı miktarlarda ondalık YAZILMAZ: "3 adet", "15.603 lot" —
  /// "3,00 adet" değil (kullanıcı isteği 2026-09-10: "adet miktar
  /// olduğundan tam adetli varlıklarda ,00 kullanmayalım").
  ///
  /// Küsurat VARSA korunur: gram altın 2,5 gr; kesirli fon payı 10,75 lot.
  /// Sabit 0 haneye inmek burada bilgi kaybı olurdu — miktar yanlış okunur.
  ///
  /// Projede bu kural elle tekrar ediliyordu (bkz. `portfolio_screen`:
  /// `digits: q == q.truncateToDouble() ? 0 : 2`); tek yere alındı.
  int get miktarOndalik => _ondalikFor(quantity);

  /// Kriptoda küsurat 2 haneye SIĞMAZ (0,0045 BTC) — gereken kadar hane,
  /// en çok 8 (kullanıcı isteği 2026-09-25: "kripto varlıkları da gerekli
  /// ondalık basamaklarla tut"). Diğer türlerde kural değişmedi.
  int _ondalikFor(double miktar) {
    if (_tamSayiMi(miktar)) return 0;
    if (type == AssetType.kripto) return gerekenOndalik(miktar);
    return 2;
  }

  /// `qtyFormatter`'ın (sondaki sıfırları atan) üst sınırı: kriptoda 8,
  /// diğerlerinde 4. Miktar ve birim maliyet satırları bunu kullanır; 4
  /// haneye kesilen 0,00012345 BTC "0,0001" okunuyordu.
  int get azamiOndalik => type == AssetType.kripto ? kriptoAzamiOndalik : 4;

  /// Değer tam sayı mı? Kayan nokta gürültüsüne karşı toleranslı.
  ///
  /// `q == q.truncateToDouble()` doğrudan karşılaştırma yapıyor ve
  /// 3.0000000000000004 gibi bir değeri "tam değil" sayardı — miktar
  /// toplama/çıkarma işlemlerinden geçtiği için bu gerçekçi bir durum
  /// (0,1 + 0,2 = 0,30000000000000004). Küçük bir tolerans, kullanıcıya
  /// "3,00 adet" yerine "3 adet" göstermeyi garanti eder.
  static bool _tamSayiMi(double v) => (v - v.roundToDouble()).abs() < 1e-9;

  /// Miktarı birimiyle birlikte biçimlendirir: "15.603 lot", "2,5 gr",
  /// "3 adet", "$100".
  ///
  /// **Neden burada:** ekranlar `unitLabel` ile `unitIsPrefix`'i ayrı ayrı
  /// okuyup kendi birleştirmesini yapıyordu ve biri ham `unitType`'ı
  /// basıyordu — kullanıcı "15.603,00 piece" görüyordu (2026-09-10).
  /// `unitType` bir DB sabitidir ('piece', 'gram', 'ounce'), ekrana
  /// basılmak için değil. Dört kural (etiket, konum, ondalık, biçim) tek
  /// yerde durursa bir sonraki çağrı yeri de doğru başlar.
  ///
  /// [bicimlendir] sayıyı ve ondalık hane sayısını alıp metne çevirir;
  /// çağıran taraf kendi `fmtNum`'ını geçer (model katmanı biçimlendirme
  /// yardımcısına bağımlı olmasın).
  String miktarMetni(
    double miktar,
    String Function(double deger, int ondalik) bicimlendir,
  ) {
    final sayi = bicimlendir(miktar, _ondalikFor(miktar));
    final birim = unitLabel;
    return unitIsPrefix ? '$birim$sayi' : '$sayi $birim';
  }

  /// Yalnızca silme damgasını değiştiren kopya.
  ///
  /// Dar tutuldu: genel bir `copyWith` yerine tek amaçlı bir kopyacı,
  /// çünkü Asset'i elle yeniden kurmak alan atlamaya çok müsait —
  /// `dividendAmount` bir kez böyle düşmüştü. Buradaki liste TÜM alanları
  /// taşır; yeni alan eklendiğinde buraya da eklenmeli.
  Asset copyWithDeletedAt(DateTime? deletedAt) => _kopya(
      deletedAt: deletedAt,
      portfoyId: portfoyId,
      portfoyKarisik: portfoyKarisik);

  /// Yalnızca portföyü değiştiren kopya — pozisyon taşıma
  /// (`PortfolioNotifier.pozisyonuTasi`) ve karışık pozisyonda seçilen
  /// portföyün görünümü. Portföyü BELLİ olan kayıt karışık değildir.
  /// Tam alan listesi [_kopya]'da.
  Asset copyWithPortfoy(String? portfoyId) =>
      _kopya(deletedAt: deletedAt, portfoyId: portfoyId, portfoyKarisik: false);

  Asset _kopya({
    required DateTime? deletedAt,
    required String? portfoyId,
    required bool portfoyKarisik,
  }) =>
      Asset(
        id: id,
        userId: userId,
        name: name,
        ticker: ticker,
        type: type,
        quantity: quantity,
        purchasePrice: purchasePrice,
        currency: currency,
        notes: notes,
        subCategory: subCategory,
        unitType: unitType,
        purchaseFxRate: purchaseFxRate,
        currentPrice: currentPrice,
        lastUpdated: lastUpdated,
        addedDate: addedDate,
        isManualPrice: isManualPrice,
        kind: kind,
        refAssetId: refAssetId,
        sellPrice: sellPrice,
        sellFxRate: sellFxRate,
        commission: commission,
        dividendAmount: dividendAmount,
        deletedCount: deletedCount,
        deletedAt: deletedAt,
        sozlesmeId: sozlesmeId,
        createdAt: createdAt,
        portfoyId: portfoyId,
        portfoyKarisik: portfoyKarisik,
      ).._kayitliTicker = _kayitliTicker;

  /// Yalnızca notu değiştiren kopya — [copyWithDeletedAt] ile aynı gerekçe
  /// (tam alan listesi; yeni alan eklendiğinde buraya da eklenmeli).
  /// Mevcut nesneyi yerinde DEĞİŞTİRMEZ: durumdaki listeyi paylaşan
  /// herkes eski notu görmeye devam ederdi ve Riverpod değişikliği fark
  /// etmezdi. Taze kopya üzerinde yazar.
  Asset copyWithNotes(String notes) =>
      copyWithDeletedAt(deletedAt)..notes = notes;

  // `toMap()` / `fromMap()` (SQLite/camelCase çifti) 2026-09'da SİLİNDİ:
  // kod tabanında sıfır çağıranı vardı ve `toSupabase()` ile alan kümesi
  // ayrışmıştı (purchaseFxRate, commission, dividendAmount, deletedCount,
  // deletedAt taşımıyordu). Yeniden bir taşıma biçimi gerekirse
  // `toSupabase()`/`fromSupabase()` kullanılır — tek serileştirme şeması.

  /// Supabase snake_case sütunlarına map
  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'ticker': _yazilacakTicker,
        'type': type.name,
        'sub_category': subCategory,
        'unit_type': unitType,
        'quantity': quantity,
        'purchase_price': purchasePrice,
        'currency': currency,
        'current_price': currentPrice,
        'last_updated': lastUpdated?.toUtc().toIso8601String(),
        'added_date': addedDate.toUtc().toIso8601String(),
        'notes': notes,
        'is_manual_price': isManualPrice,
        'purchase_fx_rate': purchaseFxRate,
        'kind': kind.dbValue,
        'ref_asset_id': refAssetId,
        'sell_price': sellPrice,
        'commission': commission,
        'dividend_amount': dividendAmount,
        'deleted_count': deletedCount,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        // YALNIZ doluyken yazılır: sütun 0088 ile geldi. Göç iki sunucuya
        // ulaşmadan yayınlanan bir sürümde anahtar her gövdede olsaydı
        // PostgREST bilinmeyen sütun için TÜM varlık yazımlarını reddederdi
        // (PGRST204) — mevduat/BES dışındaki kullanıcı da kaydedemezdi.
        if (sozlesmeId != null) 'sozlesme_id': sozlesmeId,
        // Aynı gerekçe (0111): yalnız `satis_gunu_kuru` bayrağı açıkken
        // dolu, bayrak sütun iki sunucuya ulaşınca açılır.
        if (sellFxRate != null) 'sell_fx_rate': sellFxRate,
        // Aynı gerekçe (0133) + bayrak: `coklu_portfoy` ANCAK sütun iki
        // sunucuya ulaşınca açılır. Değer sunucudan okunmuş olsa bile bayrak
        // kapalıyken yazılmaz: uygulama sunucu değiştirirse (Tokyo ↔
        // Frankfurt) öbür projede sütun henüz olmayabilir. Yazılmaması
        // değeri SİLMEZ — UPDATE yalnız gövdedeki sütunlara dokunur; INSERT'te
        // NULL kalır ve 0133 tetikleyicisi referans lottan miras alır.
        if (portfoyId != null && RemoteConfigService.instance.cokluPortfoy)
          'portfoy_id': portfoyId,
      };

  /// Sunucu satırından okur — sembolü [kanonikTicker] biçimine çevirerek.
  ///
  /// Okuma sınırı tek giriş kapısıdır (kendi varlıkları, ortaklar, yerel
  /// önbellek hepsi buradan geçer); öneksiz eski fon kodu fiyat, seri ve
  /// kimlik yollarının HİÇBİRİNE ulaşmaz. Tek tek tüketicide (38 `a.ticker`
  /// kullanımı yalnızca `HistoryService`'te) düzeltmek, sözleşmenin (1)
  /// maddesinin önlediği ayrışmayı yeniden üretirdi. Kayıtlı biçim
  /// [_kayitliTicker]'da saklanır, yazarken geri konur.
  factory Asset.fromSupabase(Map<String, dynamic> m) {
    final a = _satirdan(m);
    final kanonik = kanonikTicker(
        type: a.type, ticker: a.ticker, isManualPrice: a.isManualPrice);
    if (kanonik != a.ticker) {
      a._kayitliTicker = a.ticker;
      a.ticker = kanonik;
    }
    return a;
  }

  /// [toSupabase]'in yazacağı sembol: okunduğu gibi kaldıysa KAYITLI biçim.
  String get _yazilacakTicker {
    final kayitli = _kayitliTicker;
    if (kayitli == null) return ticker;
    final degismedi = kanonikTicker(
            type: type, ticker: kayitli, isManualPrice: isManualPrice) ==
        ticker;
    return degismedi ? kayitli : ticker;
  }

  static Asset _satirdan(Map<String, dynamic> m) => Asset(
        id: m['id'] as String,
        userId: (m['user_id'] as String?) ?? '',
        name: m['name'] as String,
        ticker: (m['ticker'] as String?) ?? '',
        type: AssetType.fromString(m['type'] as String),
        quantity: (m['quantity'] as num).toDouble(),
        purchasePrice: (m['purchase_price'] as num).toDouble(),
        currency: m['currency'] as String,
        currentPrice: (m['current_price'] as num).toDouble(),
        subCategory: m['sub_category'] as String?,
        unitType: (m['unit_type'] as String?) ?? 'piece',
        lastUpdated: m['last_updated'] != null
            ? DateTime.parse(m['last_updated'] as String).toLocal()
            : null,
        // `.toLocal()` ŞART (2026-09-24). Sütun `timestamptz`; PostgREST
        // `+00:00` döndürür ve `DateTime.parse` UTC nesne üretir. UTC
        // nesnede `hour`/`day` UTC alanlarıdır: tarih seçiciyle "20 Eyl"
        // girilen işlem (yerel 00:00 = 19 Eyl 21:00Z) listede "19 Eyl"
        // görünüyor, `dayKey` onu önceki güne koyuyordu. Saat gösterimi
        // eklenince 14:32'lik alım 11:32 yazılacaktı. Yazma tarafı zaten
        // `.toUtc()`; an (`millisecondsSinceEpoch`) değişmez.
        addedDate: m['added_date'] != null
            ? DateTime.parse(m['added_date'] as String).toLocal()
            : DateTime.now(),
        notes: (m['notes'] as String?) ?? '',
        isManualPrice: m['is_manual_price'] as bool? ?? false,
        purchaseFxRate: (m['purchase_fx_rate'] as num?)?.toDouble() ?? 1.0,
        kind: AssetKind.fromDb(m['kind'] as String?),
        refAssetId: m['ref_asset_id'] as String?,
        sellPrice: (m['sell_price'] as num?)?.toDouble(),
        // Migration 0111 öncesi satırlarda sütun yok → null (alım kuru).
        sellFxRate: (m['sell_fx_rate'] as num?)?.toDouble(),
        // Migration 0019 öncesi kayıtlarda sütun yok → 0.
        commission: (m['commission'] as num?)?.toDouble() ?? 0,
        // Migration 0020 öncesi kayıtlarda sütun yok → 0.
        dividendAmount: (m['dividend_amount'] as num?)?.toDouble() ?? 0,
        // Migration 0026 öncesi delete_log satırlarında sütun yok → 0,
        // "sayı bilinmiyor" anlamına gelir.
        deletedCount: (m['deleted_count'] as num?)?.toInt() ?? 0,
        // Migration 0027 öncesi kayıtlarda sütun yok → null = aktif.
        deletedAt: m['deleted_at'] != null
            ? DateTime.parse(m['deleted_at'] as String).toLocal()
            : null,
        // Migration 0088 öncesi satırlarda sütun yok → null.
        sozlesmeId: m['sozlesme_id'] as String?,
        // Migration 0095 öncesi satırlarda sütun yok → null. YAZILMAZ
        // (`toSupabase`'te yok): giriş anını sunucu basar.
        createdAt: m['created_at'] != null
            ? DateTime.parse(m['created_at'] as String).toLocal()
            : null,
        // Migration 0133 öncesi satırlarda sütun yok → null = Ana portföy.
        portfoyId: m['portfoy_id'] as String?,
      );
}
