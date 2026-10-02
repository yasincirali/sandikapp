/// Sürüm notları — "Yenilikler" ekranının TEK kaynağı.
///
/// **Neden uygulama içi sabit (Remote Config ya da Supabase değil):** yeni
/// sürüm zaten yeni bir derleme demektir, yani notu uzaktan güncelleyebilmenin
/// bir karşılığı yok. Buna karşılık uygulama içi liste çevrimdışı çalışır,
/// test edilebilir ve i18n'e girer. Uzak kaynak seçilseydi ağı olmayan
/// kullanıcı güncelleme sonrası boş ekran görürdü.
///
/// ## Yeni sürüm çıkarırken
/// 1. Listenin BAŞINA yeni bir [SurumNotu] ekle (en yeni önce).
/// 2. [surum] alanı `pubspec.yaml`'daki sürümle AYNI olmalı — build numarası
///    (`+7`) olmadan. Eşleşmezse not hiç gösterilmez (bkz. `SurumNotuService`).
///
///    ⚠️ Sürümü `pubspec.yaml`'da ELLE bump ETME: fastlane bunu CI'da yapar
///    (bkz. `YAPMAN_GEREKENLER` / TestFlight akışı). Buraya YAYINLANACAK
///    sürümü yaz; pubspec o değere CI'da ulaşır. `surum_notu_test.dart`
///    biçimi denetler ama pubspec eşitliğini denetleyemez — çünkü doğru
///    değer henüz pubspec'te değildir.
/// 3. Kullanıcının fark edeceği şeyleri yaz; "refactor", "bağımlılık
///    güncellendi" gibi maddeler buraya girmez — onlar CHANGELOG'un işi.
/// 4. Özellik uygulamanın ANA yüzeylerinden birini değiştiriyorsa
///    [onemli] işaretle: hem Yenilikler otomatik açılır hem de tanıtım
///    turuna girmeye adaydır (bkz. `onboarding_screen.dart`).
library;

/// Tek bir yenilik maddesi.
class Yenilik {
  const Yenilik({
    required this.baslik,
    required this.aciklama,
    this.ikon = YenilikIkonu.genel,
  });

  final String baslik;
  final String aciklama;

  /// Satırın ikonu. Varsayılan [YenilikIkonu.genel].
  ///
  /// **Neden enum, neden `IconData` değil:** sabit listeye `IconData`
  /// yazmak ikon tree-shake'ini bozar (derleme `--no-tree-shake-icons`
  /// ister, uygulama boyutu büyür). Kod noktasından `IconData` üretmek de
  /// aynı sorunu doğuruyor ("codePoint must be a constant"). Enum, ikonu
  /// gösterim katmanındaki sabit bir `switch`'e bağlar — hem tree-shake
  /// çalışır hem de sürüm notu yazarken ikon seçimi sınırlı ve tutarlı
  /// kalır.
  final YenilikIkonu ikon;
}

/// Yenilik satırında kullanılabilecek ikonlar.
///
/// Liste kasıtlı olarak kısa: her yeniliğe ayrı bir ikon aramak, sürüm
/// notunu yazma maliyetini artırır ve görsel tutarlılığı bozar.
enum YenilikIkonu {
  /// Varsayılan — özel bir karşılığı olmayan yenilik.
  genel,
  bildirim,
  grafik,
  para,
  liste,
  ayar,
  guvenlik,
}

/// Bir sürümün notu.
class SurumNotu {
  const SurumNotu({
    required this.surum,
    required this.tarih,
    required this.yenilikler,
    this.onemli = false,
    this.baslik,
  });

  /// `pubspec.yaml` sürümü, build numarası OLMADAN: '1.2.0'.
  final String surum;

  /// Yayın tarihi — 'Eylül 2026' gibi okunur biçim, kullanıcıya gösterilir.
  final String tarih;

  /// Sürümün tek cümlelik başlığı. null → jenerik başlık kullanılır.
  final String? baslik;

  /// Ana yüzeyleri değiştiren sürüm mü?
  ///
  /// `true` → güncelleme sonrası Yenilikler ekranı KENDİLİĞİNDEN açılır.
  /// `false` → yalnızca Ayarlar'dan bakılır (yama sürümleri).
  ///
  /// Her sürümde otomatik açmak, iki satırlık bir düzeltme için kullanıcının
  /// önüne modal koymak demekti; üçüncü seferde kapatılan bir şeye dönerdi.
  final bool onemli;

  final List<Yenilik> yenilikler;
}

/// Sürüm notları — **en yeni önce**.
///
/// Sıra önemli: `SurumNotuService` "kullanıcının en son gördüğü sürümden
/// bu yana çıkanlar"ı bu listeden baştan itibaren toplar.
const List<SurumNotu> surumNotlari = [
  SurumNotu(
    surum: '1.1.6',
    tarih: 'Ekim 2026',
    onemli: true,
    // Başlık ve ilk altı madde sürümün asıl hikâyesi (2026-10-02 müşteri
    // testi): sayfa ilk altıyı gösterir, gerisi katlıdır
    // (`YeniliklerSheet.oneCikanSayisi`). Kripto ve kilit ekranı bu yüzden
    // öne alındı — App Store'daki 1.0.5'ten gelen kullanıcı ikisini de ilk
    // kez görüyor.
    baslik: 'Yeni Bugün kartı, paranın getirisi, kripto ve mevduat',
    yenilikler: [
      // 2026-10-03: tek aktif cihaz + kayıtlı cihazlar (0098). Kullanıcı
      // ilk kez kod ekranı ya da "başka cihazda açıldı" çıkışı görünce
      // nedenini buradan öğrenir; sessiz kalsa arıza sanılırdı.
      Yenilik(
        ikon: YenilikIkonu.guvenlik,
        baslik: 'Hesabın tek cihazda açık',
        aciklama: 'Hesabın artık aynı anda yalnızca bir cihazda açık '
            'kalır; başka cihazda açılınca öbüründe oturum kapanır. '
            'Listende olmayan bir cihazdan girişte e-postana 6 haneli kod '
            'gelir. Kayıtlı cihazlarını Ayarlar › Hesap & Güvenlik › '
            "Kayıtlı cihazlar'da görüp kaldırabilirsin.",
      ),
      // 2026-10-01: Bugün kartı "sakin pano" (kullanıcı seçimi D).
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Bugün kartı yenilendi',
        aciklama: 'Günün hareketi büyük rakamla, yanında gün içi eğri; kesik '
            'çizgi gün başı seviyesi. Enflasyona göre durumun çubukla '
            '(getirin dolu, TÜFE çizgi) ve hangi aylar arasında ölçüldüğüyle; '
            'yanında son 7 gün ya da artıdaki varlıklar, günden güne '
            'değişir. Hedef ve aylık özet sarı kutularda, bir dokunuşla.',
      ),
      // 2026-10-01: tek getiri dili (M1 + D2 + düzen A + kıyas kartı).
      // Ana rakam bu sürümde değişiyor (temettü dahil, para ağırlıklı);
      // not bunu açıkça söylemeli, yoksa kullanıcı farkı hata sanar.
      // 2026-10-02 (müşteri testi sadeleştirmesi, aynı sürüm): enflasyon
      // kartı tek sayı (puan farkı), pencere cümlede; Grafik kartında yüzde
      // yalnızca piyasanın kattığı; köprüde temettü kendi satırında.
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Performans özeti yenilendi',
        aciklama: 'Ana rakam artık "Paranın getirisi": eklediğin paranın ne '
            'zaman girdiği hesaba katılır ve nakit temettülerin de getiriye '
            'dahildir, bu yüzden rakam öncekinden farklı görünebilir. Her '
            'yüzdenin yanında hangi tarihler arasında ölçüldüğü yazar. '
            'Enflasyon karşılaştırması tek sayı söyler: kaç puan önde ya da '
            "geride olduğun, hangi aylar arasında ölçüldüğüyle birlikte; "
            'ayrıntı "Nasıl hesaplandı" altında. Grafik kartındaki yüzde '
            'yalnızca piyasanın kattığıdır; yatırdığın para ve cebine aldığın '
            'temettü ayrı yazılır. Yeni "Başka yere koysaydın" kartı, aynı '
            'paraları aynı günlerde dolara, altına ya da BIST 100\'e '
            'koysaydın ne olacağını gösterir.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Kilit ekranında sandık (iPhone)',
        aciklama: 'Kilit ekranına widget olarak ekle: günün yönü, yüzdesi '
            've eğrisi tek kartta. Tutar yalnız "Kilit ekranında tutar '
            "göster\" açıksa görünür. Dinamik Ada'da renkli yön halkası "
            'günün yönünü ve büyüklüğünü tek bakışta gösterir.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Kripto ekle',
        aciklama: 'Varlık Ekle\'de yeni Kripto türü var: listeden coin\'i '
            'seç, fiyatı TL karşılığıyla kendiliğinden gelir. Türk lirası '
            'paritesi olan tüm coin\'ler ve en çok işlem gören 250 coin '
            'listede. Hızlı Giriş\'e "0,05 btc" yazman da yeter.',
      ),
      // 2026-10-01: evrensel ekstre motoru (docs/EKSTRE_MOTORU.md).
      Yenilik(
        ikon: YenilikIkonu.liste,
        baslik: 'Ekstreni dosyadan içe aktar',
        aciklama: "Toplu ekle › Ekstreden içe aktar: aracı kurum ya da "
            'bankanın PDF, Excel veya CSV ekstresini seç. Sütunların adı ve '
            'sırası önemli değil; sembol, adet, maliyet, tarih ve alış/satış '
            'kendiliğinden bulunur. Emin olmadığımız sütunu sana sorarız.',
      ),
      // 2026-09-30 (çalışma seçenekleri M2 + B3). Sunucu tarafı 0088 iki
      // sunucuya ulaşmadan bu sürüm yayına çıkmamalı (YAPMAN_GEREKENLER).
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Vadeli mevduat ve BES',
        aciklama: "Varlık Ekle'de iki yeni tür. Mevduat: banka, tutar, faiz "
            've vadeyi yaz; net getiriyi stopajıyla birlikte hesaplarız, '
            'vade dolunca varlık sayfasından yeni faizle yenilersin. Günlük '
            'faizli hesaplar da olur. BES: şirketini, ana paranı, getirini '
            've fon dağılımını gir; geçmişin giriş tarihinden bugüne düz '
            'çizilir, kârın korunur. Bundan sonrası emeklilik fonlarının '
            'fiyatıyla yürür; fonunu değiştirdiğinde grafik yeni fonlarla '
            'devam eder. Devlet katkısı hak ediş oranıyla ayrı durur, aylık '
            'katkını tek dokunuşla eklersin.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Zirvedeki portföyler',
        aciklama: 'Performans\'ta tür dökümünün altındaki yeni kart, dönemin '
            'en çok kazanan anonim portföylerini gösterir. Dokununca yeni '
            'ekran: haftalık, aylık ve yıllık; herkes aynı çizgide, sen de '
            'üstünde. Bir portföye dokun, neye yatırdığını (fonlarda hangi '
            'fonlar, ne oranda) ve senden farkını oku. Katılım isteğe bağlı '
            've anonim: katılanlar birbirinin tür dağılımını ve getirisini '
            'görür; kimlik, miktar ve TL asla paylaşılmaz.',
      ),
      Yenilik(
        ikon: YenilikIkonu.liste,
        baslik: 'İşlem notların artık görünüyor',
        aciklama: "Varlık eklerken yazdığın not kayboluyordu. Artık notu olan "
            "işlemin tarihinin yanında küçük bir işaret var; harekete "
            "dokununca notu okur, düzeltir ya da yeni not yazarsın. Notlar "
            "Portföy'de varlık kartını açınca da görünür, Tüm Hareketler'de "
            "aranır.",
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Daha net rakamlar',
        aciklama: 'Bugün kartında günlük yüzde artık tutarla aynı işareti '
            'taşıyor (+%1,23 / −%0,06); yön yalnızca renkten okunmuyor. '
            'Enflasyon farkı yönüyle yazılıyor: "20,6 puan geride", '
            '"5,2 puan önde".',
      ),
      // Büyüme bayrakları 2026-09-30'da açık doğdu (remote_config_service);
      // notlar onlarla birlikte geldi. Bir bayrak Console'dan kapatılırsa
      // notu da buradan çıkar — kapalı özelliği anlatan not kullanıcıya
      // görmediği şeyi vaat eder. Örnek portföy ve ilk açılış sırası yeni
      // kullanıcı akışı, not gerektirmez.
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Fon karnesi',
        aciklama: 'Fon ekranında fonun kendi kategorisindeki sırası (1 ay, '
            'yılbaşından beri, 1 yıl) ve kategori ortancasına farkı. '
            "Portföy'de fon kartını açınca tek satırlık özeti görünür.",
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Temettülerini kaçırma',
        aciklama: 'Hisse ekranında son 12 ayın temettüleri; "Kaydet" ile '
            'tutar hazır gelir, yalnızca onaylarsın. Elindeki bir hisse '
            'temettü dağıttığında akşam haber veririz.',
      ),
      Yenilik(
        ikon: YenilikIkonu.liste,
        baslik: 'Halka arz takvimi',
        aciklama: 'Profil › Halka arzlar: kaynağıyla birlikte yaklaşan ve '
            'son halka arzlar. "Katıldım" ile lotunu halka arz fiyatı ve '
            'tarihiyle portföyüne eklersin.',
      ),
      // 2026-09-30 karar tahtası (4–8). Aynı sürüm (1.1.6) notunu bugün
      // görmüş TestFlight kullanıcısına bunlar otomatik açılmaz (kural 3,
      // `yeniNotlar`); Ayarlar › Yenilikler'de durur. Mağazadan 1.1.6'yı
      // ilk alan kullanıcı hepsini görür.
      Yenilik(
        ikon: YenilikIkonu.liste,
        baslik: 'Aracı kurum ekstresi: alış ve satış',
        aciklama: 'Toplu ekle › yapıştır artık kurumların sütun adlarını '
            '(Menkul Kıymet, Nominal, Ortalama Maliyet…) tanıyor; satış '
            'satırları da kendi tarihiyle deftere girer. Elinde olandan '
            'fazla satış kaydedilmez.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Temettüde net tutar ve KAP',
        aciklama: 'Temettü önerisi %15 stopaj düşülmüş net tutarla gelir; '
            'düşülen tutar yazar, istersen düzeltirsin. Hisse ekranındaki '
            '"KAP bildirimleri" şirketin KAP sayfasını açar.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Daha okunaklı, daha hızlı',
        aciklama: 'Koyu temada ikincil yazılar daha okunaklı; sekmeler '
            'arasında geçiş anında. Grafiklerde eksen yazıları artık hiç '
            'iki satıra kırılmıyor. Fiyatlar yenilenince ana sayfadaki '
            'toplam, değişimin yönünü kısa bir renkle gösterir.',
      ),
      // Kripto (2026-09-25) ayrı bir 1.1.7 notu olarak yazılmıştı; ASC'de
      // 1.1.6 train'i hâlâ açık ve fastlane yalnızca kapalı train'de bump
      // yapıyor, yani derleme 1.1.6 çıkacak. '1.1.7' notu hiç gösterilmezdi
      // (sessiz arıza, dosya başı). Bu yüzden 1.1.6 notuna katıldı.
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Toplamda, grafikte, alarmda',
        aciklama: 'Kripto, portföy toplamına TL olarak girer; miktar '
            'gerektiği kadar ondalıkla tutulur. Kripto 7/24 işlediği için '
            'grafikte hafta sonu da görünür. Takip listesine ekleyebilir, '
            'fiyat alarmı kurabilirsin.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Takip listesi: Ekle üstte, 7 varlık',
        aciklama: 'Ekle düğmesi listenin dibinden üstteki karta taşındı; '
            'yanındaki bölmeli şerit kaç yerin kaldığını gösterir. Takip '
            'listesi şimdilik 7 varlıkla sınırlı: grafik okunur kalsın diye.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Fiyatlar nereden geliyor',
        aciklama: 'Kripto fiyatları Binance\'ten, dakikada bir güncellenir. '
            'Fiyat 10 dakikadan eskiyse varlık ekranında "Gecikmeli" yazar. '
            'Yatırım tavsiyesi değildir.',
      ),
      Yenilik(
        ikon: YenilikIkonu.ayar,
        baslik: 'Giriş: artık şifre sormuyor',
        aciklama: 'Biyometrik kilidin açıksa uzun aradan sonra da çıkış '
            'yapılmıyor, yalnızca kilitleniyor: Face ID ya da parmak izinle '
            'giriyorsun. '
            'Güncelleme sonrası da öyle. Oturumun kapanmadığı için fiyat '
            'alarmların ve günlük özetin kesintisiz geliyor. Kilit ekranına '
            '"Farklı hesapla giriş yap" eklendi; giriş sayfasında boş alana '
            'dokununca klavye kapanıyor.',
      ),
      Yenilik(
        ikon: YenilikIkonu.ayar,
        baslik: 'Kilit önerisi',
        aciklama: 'Kilidi kapalıysan uygulama bir kez Face ID / parmak izi '
            'kilidini açmayı '
            'öneriyor: neden işine yaradığını da anlatıyor. İstemezsen '
            '"Şimdi değil" diyebilirsin, sonra Ayarlar\'dan açılır.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Kâr/zarar hesabı düzeltildi',
        aciklama: 'Sattığın lotlar artık maliyete sayılmıyor: kısmi satış '
            'yaptığın varlıklarda toplam kâr ve yüzde doğru çıkıyor. '
            'Ortak görünümünde de herkesin hesabı kendi defterinden.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Hangi varlıktan ne temettü aldın',
        aciklama: 'Portföy sayfasında bir varlığa dokunup açtığında '
            '"Tahsil Edilen Temettü" satırını görüyorsun. Daha önce bu '
            'bilgi yalnızca portföy genelindeydi.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Temettü artık kartta yazıyor',
        aciklama: 'Üstteki kâr/zarar temettüyü de içeriyordu ama bunu '
            'söylemiyordu; varlık satırlarını toplayınca tutmuyordu. '
            'Artık "bunun temettüsü" ayrı satırda.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Ortak görünümünde Özet düzeldi',
        aciklama: 'Performans › Özet\'te ortağına ya da Birlikte\'ye '
            'geçtiğinde günlük kâr/zarar ve toplam artık yalnızca o '
            'defteri anlatıyor. Birlikte\'deki tutar da kişilerin '
            'toplamını veriyor; eskiden ikisi tutmuyordu.',
      ),
      Yenilik(
        ikon: YenilikIkonu.ayar,
        baslik: 'VPN açıkken ne olduğu anlaşılıyor',
        aciklama: 'Bağlantı kurulamadığında uygulama artık VPN\'i de '
            'hatırlatıyor. VPN çoğu zaman fiyat ve hesap sunucularına '
            'erişimi kesiyor; mesaj kapatıp denemeni söylüyor.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Bugün kartı yenilendi',
        aciklama: 'Tarih ve günün hareketi başta; enflasyona göre durumun, '
            'geçen hafta, hedef ve artıdaki varlıkların defter gibi alt '
            'alta, her birinin altında kısa açıklamayla. Yaklaşan tarih en '
            'altta.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Bugün kartı ortaklarda da',
        aciklama: 'Ortağına ya da Birlikte\'ye geçince kart o defterin '
            'gününü anlatır; başında kimin olduğu yazar. Hedef yalnızca '
            'senin görünümünde.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Ana ekran ve Performans sadeleşti',
        aciklama: 'Reel getiri ve haftalık özet artık Bugün kartının '
            'satırları; Ben/ortak/Birlikte seçimi toplam kartının başlığında. '
            'Performans › Özet üç başlığa ayrıldı: Bu dönem, Varlıklar, '
            'Derinlik (katlanır). Hiçbir bilgi kaldırılmadı, yeri değişti.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Ana ekranda piyasa şeridi',
        aciklama: 'Dolar, euro, gram altın ve BIST 100 günlük değişimiyle '
            'ana ekranın en üstünde. Portföyüne bakmadan önce piyasayı gör.',
      ),
      Yenilik(
        ikon: YenilikIkonu.bildirim,
        baslik: 'Takip listende büyük hareket',
        aciklama: 'İzlediğin bir varlık gün içinde %5\'ten fazla oynadıysa '
            'kapanışta tek bildirimle haber verir; alarm kurman gerekmez.',
      ),
      Yenilik(
        ikon: YenilikIkonu.bildirim,
        baslik: 'Enflasyon günü bildirimi',
        aciklama: 'TÜİK aylık enflasyonu açıkladığında oran cebine gelir; '
            'dokununca portföyünün enflasyonu geçip geçmediğini görürsün.',
      ),
      Yenilik(
        ikon: YenilikIkonu.bildirim,
        baslik: 'Brifing saati: sabah ya da akşam',
        aciklama: 'Günlük portföy özetini sabah 09:45 yerine kapanışta '
            '18:30\'da alabilirsin. Ayarlar › Bildirimler › Brifing saati.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Varlık eklerken alarm önerisi',
        aciklama: 'Yeni varlık kaydettiğinde tek dokunuşla fiyat alarmı '
            'kurabilirsin.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Aylık özet bildirimi',
        aciklama: 'Her ayın 1\'inde geçen ayın özeti cebine gelir; '
            'dokununca Özet\'te getirin, enflasyon farkı ve en iyi varlığın '
            'açılır. Sessiz saatlerine uyar.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Paylaşımlarda indirme bağlantısı',
        aciklama: 'Özet kartını ya da ortak davetini paylaştığında mesaja '
            'indirme bağlantısı eklenir; karşı taraf mağazada aramaz.',
      ),
      Yenilik(
        ikon: YenilikIkonu.genel,
        baslik: 'Ana ekranda "Bugün" kartı',
        aciklama: 'Günün hareketi, kaç varlığının artıda olduğu, hedefine '
            'kalan yol ve yaklaşan tarihler (TÜİK enflasyon açıklaması, '
            'borsa tatili, ay sonu) tek kartta. Her gün değişir; ayın ilk '
            'günlerinde geçen ayın özetine buradan gidersin.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Portföy hedefi',
        aciklama: 'Bir tutar belirle, ilerlemeyi ve kalanı her gün Bugün '
            'kartında gör. Yalnızca gösterim; hesapları değiştirmez.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Daha dolu bir paylaşım kartı',
        aciklama: 'Performans özetini ve yıl sonu özetini paylaşırken kart '
            'artık en iyi / en zayıf varlığını, artıda kapanan gün oranını, '
            'reel getiriyi ve portföy dağılımını da gösteriyor. Tutar yine '
            'yok. iPad\'de paylaş düğmesinin hata vermesi de düzeltildi.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Enflasyon farkı her yerde aynı',
        aciklama: 'Ana ekrandaki "enflasyonun X puan önündesin" rozeti, '
            'Performans kartı ve paylaşım kartı artık aynı hesabı kullanıyor: '
            'son 12 ayın nakit akışı düzeltilmiş piyasa getirisi. Eskiden ana '
            'ekran yıl içinde eklediğin parayı görmüyor ve farklı bir puan '
            'söylüyordu.',
      ),
      Yenilik(
        ikon: YenilikIkonu.bildirim,
        baslik: 'Fiyat alarmı kur',
        aciklama: 'Bir varlık hedeflediğin fiyata gelince haber ver. '
            'Varlık ekranındaki zil simgesinden kurulur; uygulama kapalıyken '
            'de çalışır.',
      ),
      Yenilik(
        ikon: YenilikIkonu.liste,
        baslik: 'Bildirim merkezi',
        aciklama: 'Teknik sinyaller ve tetiklenen fiyat alarmları artık aynı '
            'listede. Bildirimi kaçırsan bile ne olduğunu buradan görürsün.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Bildirimden doğrudan varlığa',
        aciklama: 'Alarm bildirimine dokununca o varlığın ekranı GÜNLÜK '
            'sekmesinde açılır; fiyatın gün içinde ne yaptığını tek bakışta '
            'görürsün.',
      ),
      Yenilik(
        ikon: YenilikIkonu.para,
        baslik: 'Altın fiyatlarında düzeltme',
        aciklama: 'Gram altın 22 ayar üzerinden fiyatlanıyor. Veri '
            'kaynağındaki bir değişiklik yüzünden bir süredir farklı bir '
            'ayardan okunuyordu; düzeltildi.',
      ),
      Yenilik(
        ikon: YenilikIkonu.grafik,
        baslik: 'Altın grafiğindeki sahte düşüş gitti',
        aciklama: 'Altın grafiğinin son noktası, olmayan bir düşüş gibi '
            'aşağı iniyordu, üstelik bazen. Sebep iki ayrı fiyat '
            'kaynağıydı: veri gelmediğinde grafik, spot altın yerine vadeli '
            'sözleşmeye düşüyor ve tüm çizgi biraz yukarı kayıyordu. Artık '
            'tüm dönem sekmeleri aynı kaynağı aynı sırayla kullanıyor ve '
            'seri güncel fiyatın ölçeğine oturuyor.',
      ),
    ],
  ),
];
