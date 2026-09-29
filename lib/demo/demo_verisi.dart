import '../models/asset.dart';
import '../models/user_model.dart';
import '../services/csv_import_service.dart';

/// Örnek portföyün sahibi. Sunucuda böyle bir kullanıcı YOK ve olmayacak:
/// demo hiçbir satır yazmaz (ADR-1). Kimlik yalnızca demo defterini
/// "sahibine göre" ayıran hesaplar (`lotlarSahibeGore`, gün içi seri
/// önbelleğinin sahip damgası) için tutarlı bir anahtar.
const String kDemoKullaniciId = 'demo-ornek-portfoy';

/// Demo oturumunun kullanıcısı. Ad BOŞ: ana ekran boş adı "B" baş harfiyle
/// çizer; uydurma bir isim ("Ayşe") kullanıcının kendi hesabı sanılabilirdi.
final AppUser demoKullanici = AppUser(
  id: kDemoKullaniciId,
  email: '',
  displayName: '',
  createdAt: DateTime(2025, 9, 1),
  onboardingCompleted: true,
  username: 'ornek',
);

/// Örnek portföyün kaynağı — `store_listing/demo_portfoy.csv` ile BİREBİR.
///
/// Neden CSV metni ve neden asset değil: pubspec'e asset eklenmedi (demo
/// verisi uygulama paketinin bir parçası değil, kodun parçası). Metin
/// uygulamanın kendi ayrıştırıcısından (`CsvImportService.parse`) geçer;
/// böylece sembol biçimi (`KCHOL.IS`, `USDTRY=X`, `ALTIN_CEYREK`), tür ve
/// para birimi kullanıcının CSV ile yapıştırdığında göreceğinin AYNISI olur.
/// Elle yazılmış `Asset` listesi o kuralları ikinci kez kodlamak olurdu.
///
/// Kompozisyonun gerekçesi (karışık türler, biri zararda, alımlar reel
/// getiri penceresinin başından önce) `store_listing/DEMO_PORTFOY.md`'de.
/// Fiyat sütunu ALIŞ fiyatıdır; güncel fiyat canlı kaynaktan gelir
/// (uydurma sayı yok — `fiyat_kaynagi.dart` §3).
const String kDemoPortfoyCsv = 'sembol;adet;fiyat;tarih\n'
    'ALTIN_CEYREK;20;7850,00;05.09.2025\n'
    'DLY;32000;4,30;12.09.2025\n'
    'AFT;70000;0,69;19.09.2025\n'
    'KCHOL;620;148,00;26.09.2025\n'
    'USD;2200;38,50;03.10.2025\n'
    'SAHOL;550;93,50;10.10.2025\n';

/// Demo defterini kurar. Her çağrı YENİ nesneler döndürür: fiyat turu
/// `Asset.currentPrice`'ı yerinde yazar; iki demo oturumu aynı nesneleri
/// paylaşmasın.
///
/// `currentPrice: 0` BİLEREK: `Asset` fiyat verilmezse alış fiyatını güncel
/// sayar ve ilk karede her satır %0 görünürdü. 0 = "fiyatsız" — toplam ve
/// maliyet hesapları o lotu atlar (`ownerScopedTotalValue`), ilk fiyat turu
/// gerçek kotasyonu yazar.
List<Asset> demoLotlari({DateTime? bugun}) {
  final sonuc = CsvImportService.parse(kDemoPortfoyCsv, today: bugun);
  var i = 0;
  return [
    for (final r in sonuc.rows)
      Asset(
        id: 'demo-lot-${i++}',
        userId: kDemoKullaniciId,
        name: r.name,
        ticker: r.ticker,
        type: r.type,
        quantity: r.quantity,
        purchasePrice: r.price,
        currency: r.currency,
        notes: '',
        subCategory: r.subCategory,
        unitType: r.unitType,
        isManualPrice: r.isManualPrice,
        currentPrice: 0,
        addedDate: r.addedDate,
      ),
  ];
}
