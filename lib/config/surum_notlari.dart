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
    surum: '1.1.5',
    tarih: 'Eylül 2026',
    onemli: true,
    baslik: 'Fiyat alarmları ve bildirim merkezi',
    yenilikler: [
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
            'sekmesinde açılır — fiyatın gün içinde ne yaptığını tek bakışta '
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
            'aşağı iniyordu — üstelik bazen. Sebep iki ayrı fiyat '
            'kaynağıydı: veri gelmediğinde grafik, spot altın yerine vadeli '
            'sözleşmeye düşüyor ve tüm çizgi biraz yukarı kayıyordu. Artık '
            'tüm dönem sekmeleri aynı kaynağı aynı sırayla kullanıyor ve '
            'seri güncel fiyatın ölçeğine oturuyor.',
      ),
    ],
  ),
];
