// Mağaza bağlantıları — tek kaynak.
//
// Neden var (2026-09-20): paylaşım kartı ve ortak daveti uygulamanın tek
// organik yayılma kanalı, ama ikisi de LİNKSİZDİ. Alan kişi "sandık"
// yazıp aradığında App Store'un ı→i katlaması yüzünden uygulamayı
// bulamıyordu (bkz. store_listing/ios/ASO_2026_09.md §1). Link gidince
// arama sorunu da ortadan kalkar; UTM ile hangi kanalın kurulum
// getirdiği ölçülür.
//
// Doğrudan mağaza URL'si yerine web sayfasındaki `/indir/` kapısı: iOS ve
// Android'i sayfa ayırır, Play yayını başlayınca link DEĞİŞMEZ (eski
// paylaşımlar çalışmaya devam eder) ve ortak kodu `kod=` ile taşınabilir.
abstract final class Magaza {
  static const appStoreId = '6786837699';
  static const appStoreUrl = 'https://apps.apple.com/tr/app/id$appStoreId';
  static const androidPaket = 'com.sandik.app';
  static const playUrl =
      'https://play.google.com/store/apps/details?id=$androidPaket';

  /// İndirme kapısı (GitHub Pages, `docs/indir/index.html`).
  static const indirKapisi = 'https://yasincirali.github.io/sandikapp/indir/';

  /// Kanal etiketli indirme bağlantısı.
  ///
  /// [kaynak] `utm_source` (share_card, invite…), [kampanya] `utm_campaign`
  /// (dönem adı gibi). [kod] ortak davet kodu; sayfa onu görünür yazar ki
  /// alan kişi uygulamayı kurduktan sonra kodu mesajda aramasın.
  static String indirBaglantisi({
    required String kaynak,
    String kampanya = 'app',
    String? kod,
  }) {
    final q = <String, String>{
      'utm_source': kaynak,
      'utm_medium': 'share',
      'utm_campaign': kampanya,
      if (kod != null && kod.isNotEmpty) 'kod': kod,
    };
    return Uri.parse(indirKapisi).replace(queryParameters: q).toString();
  }
}
