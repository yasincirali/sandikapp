import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/sandik.dart';

// ─── Belge veri modeli ────────────────────────────────────────────────────────

enum LegalBlockType { h1, h2, h3, paragraph, tableRow, tableHeader, divider, meta }

class LegalBlock {
  final LegalBlockType type;
  final String text;
  final List<String> cells;

  const LegalBlock.p(this.text) : type = LegalBlockType.paragraph, cells = const [];
  const LegalBlock.h1(this.text) : type = LegalBlockType.h1, cells = const [];
  const LegalBlock.h2(this.text) : type = LegalBlockType.h2, cells = const [];
  const LegalBlock.h3(this.text) : type = LegalBlockType.h3, cells = const [];
  const LegalBlock.meta(this.text) : type = LegalBlockType.meta, cells = const [];
  const LegalBlock.divider() : type = LegalBlockType.divider, text = '', cells = const [];
  const LegalBlock.tableHeader(this.cells) : type = LegalBlockType.tableHeader, text = '';
  const LegalBlock.tableRow(this.cells) : type = LegalBlockType.tableRow, text = '';
}

// ─── Belgeler ─────────────────────────────────────────────────────────────────

class LegalDocs {
  static const _company = 'Yasin Cirali (Bireysel Geliştirici)';
  static const _email = 'sandikapp.destek@gmail.com';
  static const _web = 'yasincirali.github.io/sandikapp';
  static const _address = 'Türkiye';

  // ── Gizlilik Politikası ──────────────────────────────────────────────────

  static const List<LegalBlock> privacy = [
    LegalBlock.h1('Gizlilik Politikası'),
    LegalBlock.meta('Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0'),
    LegalBlock.divider(),

    LegalBlock.h2('1. Veri Sorumlusu'),
    LegalBlock.p('Bu uygulamayı (sandık) $_company ("biz", "geliştirici") işletmektedir.'),
    LegalBlock.tableHeader(['Bilgi', 'Detay']),
    LegalBlock.tableRow(['E-posta', _email]),
    LegalBlock.tableRow(['Web', _web]),
    LegalBlock.tableRow(['Adres', _address]),
    LegalBlock.p('KVKK Madde 3(1)(ı) uyarınca veri sorumlusu sıfatıyla hareket ediyoruz.'),

    LegalBlock.h2('2. Bu Politikanın Kapsamı'),
    LegalBlock.p(
      'Bu politika; Uygulamayı indirip kullandığınızda hangi kişisel verilerinizi topladığımızı, '
      'neden topladığımızı, kimlerle paylaştığımızı, ne kadar sakladığımızı ve yasal haklarınızı açıklar. '
      'Politika; KVKK (6698 sayılı Kanun), GDPR (EU 2016/679), Apple App Store Privacy Guidelines ve '
      'Google Play Data Safety gerekliliklerini karşılayacak şekilde hazırlanmıştır.',
    ),

    LegalBlock.h2('3. Topladığımız Veriler'),
    LegalBlock.h3('3.1 Hesap Verileri (zorunlu)'),
    LegalBlock.tableHeader(['Veri', 'Amaç', 'Hukuki Dayanak']),
    LegalBlock.tableRow(['E-posta adresi', 'Hesap oluşturma, oturum açma, şifre sıfırlama', 'KVKK 5(2)(c) — sözleşme']),
    LegalBlock.tableRow(['Şifre (hash)', 'Kimlik doğrulama', 'KVKK 5(2)(c)']),
    LegalBlock.tableRow(['Görünen ad', 'Ortaklık özelliğinde isim göstermek', 'KVKK 5(2)(c)']),

    LegalBlock.h3('3.2 Uygulama İçeriği Verileri'),
    LegalBlock.tableHeader(['Veri', 'Amaç']),
    LegalBlock.tableRow(['Varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not)', 'Portföy takibi']),
    LegalBlock.tableRow(['Portföy snapshot geçmişi', 'Performans grafikleri']),
    LegalBlock.tableRow(['Ortaklık davet kodları ve bağlantılar', 'Çoklu kullanıcı paylaşımı']),

    LegalBlock.h3('3.3 Cihaz ve Bildirim Verileri'),
    LegalBlock.tableHeader(['Veri', 'Amaç']),
    LegalBlock.tableRow(['Push bildirim token\'ı (FCM)', 'Ortaklık daveti ve sinyal bildirimleri']),
    LegalBlock.tableRow(['Cihaz modeli, OS sürümü, uygulama sürümü', 'Hata teşhisi']),
    LegalBlock.tableRow(['Yerel ayar (locale)', 'Dil / tarih formatı']),

    LegalBlock.h3('3.4 Toplamadığımız Veriler'),
    LegalBlock.p(
      'Konum · Telefon defteri · Fotoğraf / kamera · Reklam tanımlayıcısı · '
      'Üçüncü taraf reklam ağı izleme verisi · Banka hesap bilgileri.',
    ),

    LegalBlock.h2('4. Verilerin Kullanım Amaçları'),
    LegalBlock.p(
      '1. Hesabınızı oluşturmak ve oturumunuzu sürdürmek\n'
      '2. Portföyünüzü yerel cihazınızda ve sunucularımızda saklamak\n'
      '3. Performans grafiklerinizi hesaplamak\n'
      '4. Ortaklık davetlerinizi diğer kullanıcılara iletmek\n'
      '5. Bildirim göndermek (yalnızca açıkça izin verdiyseniz)\n'
      '6. Yasal yükümlülüklerimizi yerine getirmek\n'
      '7. Hata teşhisi ve servis kalitesinin iyileştirilmesi',
    ),

    LegalBlock.h2('5. Üçüncü Taraflarla Paylaşım'),
    LegalBlock.tableHeader(['Hizmet', 'Sağlayıcı', 'Amaç', 'Yer']),
    LegalBlock.tableRow(['Backend & veritabanı', 'Supabase Inc.', 'Saklama, kimlik doğrulama', 'ABD (AWS)']),
    LegalBlock.tableRow(['Push bildirimi', 'Google Firebase (FCM)', 'Bildirim teslimi', 'Küresel']),
    LegalBlock.tableRow(['Hata raporu', 'Firebase Crashlytics', 'Çökme teşhisi', 'Küresel']),
    LegalBlock.tableRow(['Fiyat verisi', 'Yahoo Finance, TEFAS', 'Fiyat çekme (kişisel veri aktarılmaz)', 'Küresel']),
    LegalBlock.p(
      'Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder.',
    ),

    LegalBlock.h2('6. Yurt Dışına Veri Aktarımı'),
    LegalBlock.p(
      'Supabase ve Firebase ABD\'de barındırıldığından verileriniz Türkiye dışına aktarılır. '
      'ABD, KVK Kurulu\'nun "yeterli korumaya sahip ülkeler" listesinde olmadığından aktarım '
      'KVKK Madde 9(1) kapsamında açık rızanıza dayanmaktadır.',
    ),

    LegalBlock.h2('7. Veri Saklama Süreleri'),
    LegalBlock.tableHeader(['Veri', 'Süre']),
    LegalBlock.tableRow(['Hesap verileri', 'Hesap silinene kadar']),
    LegalBlock.tableRow(['Varlık kayıtları', 'Hesap silinene kadar']),
    LegalBlock.tableRow(['Snapshot geçmişi', 'Son 365 gün (rolling)']),
    LegalBlock.tableRow(['Disclaimer onay logu', 'Hesap silindikten sonra 3 yıl (TBK 146)']),
    LegalBlock.tableRow(['Push token', 'Logout / uninstall\'a kadar']),
    LegalBlock.tableRow(['Hata logları', '90 gün']),
    LegalBlock.p(
      'Hesabınızı sildiğinizde, yukarıda özel saklama süresi belirtilenlerin haricindeki tüm '
      'verileriniz 30 gün içinde kalıcı olarak silinir.',
    ),

    LegalBlock.h2('8. Haklarınız (KVKK Madde 11 / GDPR Madde 15-22)'),
    LegalBlock.p(
      'Bilgi alma · Erişim · Düzeltme · Silme (right to erasure) · Taşınabilirlik (GDPR) · '
      'İşlemeye itiraz (GDPR) · Açık rızayı geri çekme haklarına sahipsiniz.\n\n'
      'Başvuru: $_email adresine veya Profil → Ayarlar → "Hesabımı Sil" üzerinden.\n'
      'KVKK Madde 13(2) uyarınca taleplerinize 30 gün içinde yanıt veririz.\n\n'
      'Şikayet: Kişisel Verileri Koruma Kurumu — kvkk.gov.tr',
    ),

    LegalBlock.h2('9. Veri Güvenliği'),
    LegalBlock.p(
      'TLS 1.2+ aktarım şifrelemesi · AES-256 at-rest şifreleme · Bcrypt şifre hash · '
      'Row-Level Security (RLS) erişim kontrolü · Rate limiting · '
      '10 dk idle session timeout · PII maskeleme (üretim logları).\n\n'
      'Veri ihlali tespiti halinde 72 saat içinde KVK Kurulu\'na ve etkilenen kullanıcılara bildirim yapılır.',
    ),

    LegalBlock.h2('10. Yatırım Tavsiyesi Reddi'),
    LegalBlock.p(
      'sandık bir portföy takip aracıdır. SPK lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. '
      'Uygulamada gösterilen fiyat, performans, sinyal ve grafikler bilgilendirme amaçlıdır ve '
      'yatırım tavsiyesi niteliği taşımaz.',
    ),

    LegalBlock.h2('11. İletişim'),
    LegalBlock.p('E-posta: $_email\nWeb: $_web'),
    LegalBlock.divider(),
    LegalBlock.meta(
      'Bu politika Türkçe ve İngilizce dillerinde sunulmaktadır.\nYorum farklılığında Türkçe versiyon esastır.',
    ),
  ];

  // ── Kullanım Koşulları ───────────────────────────────────────────────────

  static const List<LegalBlock> terms = [
    LegalBlock.h1('Kullanım Koşulları'),
    LegalBlock.meta('Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0'),
    LegalBlock.divider(),

    LegalBlock.h2('1. Taraflar ve Kabul'),
    LegalBlock.p(
      'Bu Kullanım Koşulları ("Koşullar"), $_company ("Geliştirici", "biz") tarafından sunulan '
      'sandık mobil uygulaması ("Uygulama") ile uygulamayı kullanan gerçek kişi ("Kullanıcı", "siz") '
      'arasındaki sözleşmedir.\n\n'
      'Uygulamayı indirip hesap oluşturarak bu Koşulları, Gizlilik Politikası\'nı ve '
      'KVKK Aydınlatma Metni\'ni okuduğunuzu, anladığınızı ve kabul ettiğinizi beyan edersiniz.',
    ),

    LegalBlock.h2('2. Hizmetin Tanımı'),
    LegalBlock.p(
      'sandık, kullanıcıların aşağıdaki varlık türlerini takip edebileceği bir kişisel portföy izleme aracıdır:\n\n'
      '· BIST hisse senetleri\n'
      '· TEFAS yatırım fonları\n'
      '· Döviz (USD, EUR, GBP, vb.)\n'
      '· Kıymetli madenler (altın)\n\n'
      'Uygulama; portföy değerini, dağılımını, performansını ve isteğe bağlı olarak teknik analiz '
      'sinyallerini gösterir. Çoklu kullanıcı ortaklığı özelliğiyle iki kullanıcı portföylerini paylaşabilir.',
    ),

    LegalBlock.h2('3. ÖNEMLİ UYARI — Yatırım Tavsiyesi Reddi'),
    LegalBlock.p(
      'sandık BİR YATIRIM DANIŞMANI, ARACI KURUM VEYA PORTFÖY YÖNETİM ŞİRKETİ DEĞİLDİR.\n\n'
      '· Geliştirici, Sermaye Piyasası Kurulu (SPK) tarafından lisanslı bir kurum değildir.\n'
      '· Uygulamada gösterilen fiyatlar, performans rakamları, sinyal ve grafikler yalnızca bilgilendirme amaçlıdır.\n'
      '· Hiçbir içerik yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık niteliği taşımaz.\n'
      '· Verilerin doğruluğu için garanti verilmez; üçüncü taraf veri sağlayıcılarının verileri olduğu gibi sunulur.\n'
      '· Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.\n'
      '· Uygulamada görüntülenen verilere dayanarak verdiğiniz yatırım kararlarından doğan hiçbir '
      'kâr/zarardan Geliştirici sorumlu tutulamaz.',
    ),

    LegalBlock.h2('4. Hesap'),
    LegalBlock.h3('4.1 Hesap Açma'),
    LegalBlock.p('· 18 yaşından büyük olmalısınız.\n· Geçerli bir e-posta adresi sağlamalısınız.\n· Doğru ve güncel bilgi vermelisiniz.'),
    LegalBlock.h3('4.2 Hesap Güvenliği'),
    LegalBlock.p(
      '· Şifrenizi kimseyle paylaşmayın.\n'
      '· Şifrenizin güvenliğinden siz sorumlusunuz.\n'
      '· Yetkisiz erişim şüphesinde derhal şifrenizi değiştirin ve bizi bilgilendirin.\n'
      '· Hesap üzerinden gerçekleştirilen tüm işlemler size ait sayılır.',
    ),

    LegalBlock.h2('5. Ortaklık Özelliği'),
    LegalBlock.p(
      'Uygulamada bir başka kullanıcıyı "ortak" olarak ekleyebilirsiniz. Bu özellik aktive edildiğinde:\n\n'
      '· Ortağınız sizin portföyünüzdeki varlıkları görebilir.\n'
      '· Siz de ortağınızın portföyünü görebilirsiniz.\n'
      '· Bu paylaşım iki tarafın da onayıyla başlar (davet kodu sistemi).\n'
      '· İstediğiniz zaman ortaklığı sonlandırabilirsiniz.\n\n'
      'Davet kodunuzu yalnızca güvendiğiniz kişiyle paylaşın.',
    ),

    LegalBlock.h2('6. Kabul Edilebilir Kullanım'),
    LegalBlock.p(
      'Uygulamayı kullanırken yapılmaması gerekenler:\n\n'
      '1. Yasalara aykırı amaçlarla kullanmak\n'
      '2. Başkasının hesabına yetkisiz erişim sağlamaya çalışmak\n'
      '3. Uygulamayı tersine mühendislik, decompile veya hack etmek\n'
      '4. Otomatik scraping, bot veya zararlı yazılım kullanmak\n'
      '5. Altyapıya aşırı yük bindiren talepler göndermek (DoS)\n'
      '6. Sahte veya yanıltıcı bilgi girmek\n'
      '7. Kara para aklama veya terör finansmanı amacıyla kullanmak\n\n'
      'Bu kuralların ihlali halinde hesabınız bildirimsiz kapatılabilir.',
    ),

    LegalBlock.h2('7. Üçüncü Taraf Servisleri'),
    LegalBlock.p(
      'Uygulama; Supabase (backend), Firebase (bildirim), Yahoo Finance / TEFAS (fiyat verisi) '
      'gibi üçüncü taraf servisleri kullanır. Bu servislerin kesintileri veya hataları nedeniyle '
      'oluşacak sorunlardan Geliştirici sorumlu değildir.',
    ),

    LegalBlock.h2('8. Fikri Mülkiyet'),
    LegalBlock.p(
      'Uygulamanın tasarımı, kodu, logosu, marka ismi ve içeriği Geliştiriciye aittir. '
      '"sandık" markası, logo ve görsel kimliği telif hakkı ve marka koruması altındadır. '
      'Kendi girdiğiniz veriler (varlık kayıtlarınız) size aittir.',
    ),

    LegalBlock.h2('9. Hizmet Değişiklikleri ve Sona Erdirme'),
    LegalBlock.p(
      '· Uygulamayı güncelleme, özellik kaldırma veya ekleme hakkı saklıdır.\n'
      '· Hizmeti tamamen sonlandırma kararı alınırsa en az 30 gün önceden bildirim yapılır.\n'
      '· İstediğiniz zaman hesabınızı silebilirsiniz (Profil → Ayarlar → Hesabımı Sil).\n'
      '· Koşulları ihlal ettiğiniz tespit edilirse hesabınız bildirimsiz askıya alınabilir.',
    ),

    LegalBlock.h2('10. Sorumluluğun Sınırlandırılması'),
    LegalBlock.p(
      'Uygulama "olduğu gibi" (as-is) sunulur; her türlü açık veya zımni garanti reddedilir. '
      'Geliştiricinin toplam sorumluluğu, son 12 ayda ödenen toplam tutarla sınırlıdır '
      '(ücretsiz kullanımda sıfır TL). Dolaylı, arızi veya cezai zararlardan sorumlu tutulamayız.\n\n'
      'İstisna: Kasıtlı kusur veya ağır ihmalden doğan zararlar; tüketici hukuku kapsamındaki '
      'devredilemez haklar bu sınırlamadan etkilenmez.',
    ),

    LegalBlock.h2('11. Tüketici Hakları'),
    LegalBlock.p(
      '6502 sayılı Tüketicinin Korunması Hakkında Kanun (TKHK) kapsamındaki devredilemez '
      'haklarınız bu Koşullarla sınırlandırılamaz. Tüketici Hakem Heyeti veya Tüketici '
      'Mahkemesi\'ne başvuru hakkınız saklıdır.',
    ),

    LegalBlock.h2('12. Uygulanacak Hukuk'),
    LegalBlock.p(
      'Uygulanacak hukuk: Türkiye Cumhuriyeti hukuku.\n'
      'AB üyesi tüketiciler için Roma I Tüzüğü uyarınca yerleşim yeri ülkesinin zorunlu '
      'tüketici koruma hükümleri saklıdır.',
    ),

    LegalBlock.h2('13. Koşullarda Değişiklik'),
    LegalBlock.p(
      'Değişiklik yapılırsa en az 30 gün önceden uygulama içi bildirim ve e-posta ile '
      'haber verilir. Değişikliği kabul etmiyorsanız hesabınızı silme hakkınız vardır.',
    ),

    LegalBlock.h2('14. İletişim'),
    LegalBlock.p('E-posta: $_email\nWeb: $_web'),
    LegalBlock.divider(),
    LegalBlock.meta(
      'Bu Koşullar Türkçe ve İngilizce olarak sunulmaktadır.\nYorum farklılığında Türkçe versiyon esastır.',
    ),
  ];

  // ── KVKK Aydınlatma Metni ───────────────────────────────────────────────

  static const List<LegalBlock> kvkk = [
    LegalBlock.h1('KVKK Aydınlatma Metni'),
    LegalBlock.meta('Yürürlük tarihi: 11 Mayıs 2026  ·  Sürüm: 1.0'),
    LegalBlock.divider(),

    LegalBlock.h2('1. Veri Sorumlusunun Kimliği'),
    LegalBlock.p(
      '6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 10 uyarınca, '
      'kişisel verilerinizin işlenmesine ilişkin olarak veri sorumlusu sıfatıyla '
      'aşağıdaki bilgilendirmeyi yaparız.',
    ),
    LegalBlock.tableHeader(['Bilgi', 'Detay']),
    LegalBlock.tableRow(['Veri Sorumlusu', _company]),
    LegalBlock.tableRow(['E-posta', _email]),
    LegalBlock.tableRow(['Web', _web]),
    LegalBlock.tableRow(['Adres', _address]),

    LegalBlock.h2('2. İşlenen Kişisel Veri Kategorileri'),
    LegalBlock.h3('2.1 Kimlik Verisi'),
    LegalBlock.p('· E-posta adresi\n· Görünen ad (display name)'),
    LegalBlock.h3('2.2 İletişim Verisi'),
    LegalBlock.p('· Push bildirim için kayıtlı cihaz token\'ı'),
    LegalBlock.h3('2.3 Müşteri İşlem Verisi'),
    LegalBlock.p('· Portföy varlık kayıtları\n· Snapshot geçmişi\n· Ortaklık bağlantıları ve davet kodları'),
    LegalBlock.h3('2.4 İşlem Güvenliği Verisi'),
    LegalBlock.p('· Şifre (bcrypt hash — geri çevrilemez)\n· Oturum tokenı (JWT)\n· Cihaz IP adresi (oturum açma anında)\n· Cihaz modeli, OS sürümü, uygulama sürümü'),
    LegalBlock.h3('2.5 Hukuki İşlem Verisi'),
    LegalBlock.p('· Disclaimer onay zamanı, sürümü, platformu, IP\'si'),

    LegalBlock.h2('3. Kişisel Verilerin İşlenme Amaçları'),
    LegalBlock.tableHeader(['Amaç', 'Veri Kategorileri']),
    LegalBlock.tableRow(['Hesap oluşturma ve oturum yönetimi', '2.1, 2.4']),
    LegalBlock.tableRow(['Portföy takibi (uygulamanın ana işlevi)', '2.3']),
    LegalBlock.tableRow(['Performans grafiklerinin hesaplanması', '2.3']),
    LegalBlock.tableRow(['Ortaklık özelliği', '2.1, 2.3']),
    LegalBlock.tableRow(['Push bildirim gönderimi', '2.2']),
    LegalBlock.tableRow(['Yasal yükümlülüklerin yerine getirilmesi', '2.5, 2.4']),
    LegalBlock.tableRow(['Hata teşhisi ve uygulama güvenliği', '2.4']),

    LegalBlock.h2('4. Hukuki Dayanak'),
    LegalBlock.tableHeader(['Veri', 'Hukuki Sebep']),
    LegalBlock.tableRow(['E-posta, şifre, display name', 'KVKK 5(2)(c) — sözleşmenin ifası']),
    LegalBlock.tableRow(['Portföy verileri', 'KVKK 5(2)(c) — sözleşmenin ifası']),
    LegalBlock.tableRow(['Push token', 'KVKK 5(1) — açık rıza']),
    LegalBlock.tableRow(['IP, cihaz bilgisi', 'KVKK 5(2)(f) — meşru menfaat (güvenlik)']),
    LegalBlock.tableRow(['Disclaimer onayı', 'KVKK 5(2)(a) — kanunlarda öngörülmesi']),
    LegalBlock.tableRow(['Yurt dışı aktarımı', 'KVKK 5(1) ve 9(1) — açık rıza']),

    LegalBlock.h2('5. Yurt Dışına Veri Aktarımı'),
    LegalBlock.tableHeader(['Alıcı', 'Ülke', 'Amaç', 'Hukuki Sebep']),
    LegalBlock.tableRow(['Supabase Inc.', 'ABD', 'Veritabanı ve kimlik doğrulama', 'KVKK 9(1) — açık rıza']),
    LegalBlock.tableRow(['Google LLC (Firebase)', 'ABD / Küresel', 'Push bildirim teslimi', 'KVKK 9(1) — açık rıza']),
    LegalBlock.tableRow(['Google LLC (Crashlytics)', 'ABD / Küresel', 'Çökme teşhisi', 'KVKK 9(1) — açık rıza']),
    LegalBlock.p(
      'ABD, KVK Kurulu\'nun "yeterli korumaya sahip ülkeler" listesinde bulunmamaktadır. '
      'Yurt dışı aktarımı KVKK Madde 9(1) kapsamında açık rızanıza dayanmaktadır.',
    ),

    LegalBlock.h2('6. Veri Saklama Süreleri'),
    LegalBlock.tableHeader(['Veri', 'Süre', 'Dayanak']),
    LegalBlock.tableRow(['Hesap verileri', 'Hesap silinene kadar', 'Sözleşme süresi']),
    LegalBlock.tableRow(['Portföy varlık kayıtları', 'Hesap silinene kadar', 'Sözleşme süresi']),
    LegalBlock.tableRow(['Snapshot geçmişi', 'Son 365 gün rolling', 'Servis ihtiyacı']),
    LegalBlock.tableRow(['Push token', 'Logout / uninstall\'a kadar', 'Sözleşme süresi']),
    LegalBlock.tableRow(['Disclaimer onay logu', 'Hesap silinmesinden sonra 3 yıl', 'TBK Madde 146']),
    LegalBlock.tableRow(['Oturum logları (IP, cihaz)', '90 gün', 'KVKK 5(2)(f) meşru menfaat']),
    LegalBlock.tableRow(['Hata logları', '30 gün', 'KVKK 5(2)(f) meşru menfaat']),

    LegalBlock.h2('7. KVKK Madde 11 Kapsamındaki Haklarınız'),
    LegalBlock.p(
      'a) Kişisel verilerinizin işlenip işlenmediğini öğrenme\n'
      'b) İşlenmişse buna ilişkin bilgi talep etme\n'
      'c) İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme\n'
      'ç) Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme\n'
      'd) Eksik veya yanlış işlenmişse düzeltilmesini isteme\n'
      'e) KVKK Madde 7 kapsamında silinmesini veya yok edilmesini isteme\n'
      'f) Yapılan işlemlerin üçüncü kişilere bildirilmesini isteme\n'
      'g) Münhasıran otomatik sistemlerle aleyhinize sonuç çıkmasına itiraz etme\n'
      'ğ) Kanuna aykırı işleme sebebiyle zararın giderilmesini talep etme',
    ),

    LegalBlock.h3('7.1 Başvuru Yöntemi'),
    LegalBlock.p(
      'KVKK Madde 13 uyarınca taleplerinizi şu yöntemlerden biriyle iletebilirsiniz:\n\n'
      '1. Uygulama içi: Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"\n'
      '2. E-posta: $_email adresine kimlik bilgilerinizle yazılı başvuru\n\n'
      'Başvurunuza 30 gün içinde ücretsiz olarak yanıt veririz.',
    ),

    LegalBlock.h3('7.2 KVK Kurulu\'na Şikayet'),
    LegalBlock.p(
      'Yanıttan memnun kalmazsanız Kişisel Verileri Koruma Kurulu\'na şikayet edebilirsiniz.\n\n'
      'Kişisel Verileri Koruma Kurumu\n'
      'Nasuh Akar Mah. Ziyabey Cad. 1407. Sok. No:4, 06520 Balgat / Ankara\n'
      'Web: www.kvkk.gov.tr',
    ),

    LegalBlock.h2('8. Veri Güvenliği'),
    LegalBlock.p(
      'Teknik Önlemler: TLS 1.2+ aktarım şifrelemesi · AES-256 at-rest şifreleme · '
      'Bcrypt şifre hash · Row-Level Security (RLS) · Rate limiting · '
      '10 dk idle session timeout · PII maskeleme (üretim logları)\n\n'
      'İdari Önlemler: Supabase ve Firebase ile yazılı DPA sözleşmeleri · '
      'Least-privilege erişim prensibi · Veri ihlali yönetimi süreci\n\n'
      'Veri ihlali tespiti halinde 72 saat içinde KVK Kurulu\'na ve etkilenen '
      'kullanıcılara bildirim yapılır.',
    ),

    LegalBlock.h2('9. Politikada Değişiklikler'),
    LegalBlock.p(
      'Bu Aydınlatma Metni\'nde değişiklik yapıldığında yeni sürüm uygulama içinde gösterilir, '
      '"Sürüm" numarası artırılır ve önemli değişikliklerde tekrar onay istenir.',
    ),

    LegalBlock.h2('10. İletişim'),
    LegalBlock.p('Veri korumayla ilgili tüm soru, talep ve şikayetler için:\nE-posta: $_email\nWeb: $_web'),
    LegalBlock.divider(),
    LegalBlock.meta(
      'Bu Aydınlatma Metni\'ni okuyup anladığınızı, kayıt sırasında ilgili onay kutusunu '
      'işaretleyerek beyan etmektesiniz.',
    ),
  ];
}

// ─── Ekran ────────────────────────────────────────────────────────────────────

class LegalDocScreen extends StatefulWidget {
  final String title;
  final List<LegalBlock> blocks;
  final IconData icon;
  /// Onay akışında kullanılıyorsa: sayfanın sonunda "Okudum ve onaylıyorum"
  /// butonu görünür. Buton yalnızca kullanıcı en aşağıya kaydırdıktan sonra
  /// aktifleşir. Butona basınca `Navigator.pop(ctx, true)` döner.
  final bool confirmMode;
  final String confirmButtonLabel;

  const LegalDocScreen({
    super.key,
    required this.title,
    required this.blocks,
    required this.icon,
    this.confirmMode = false,
    this.confirmButtonLabel = 'Okudum ve onaylıyorum',
  });

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    if (widget.confirmMode) {
      _scrollCtrl.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_reachedBottom) return;
    // maxScrollExtent'e yakınsak (~40px tolerans) "okundu" say.
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 40) {
      setState(() => _reachedBottom = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: context.c.text90),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(widget.icon, color: context.c.amberText, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.title,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.c.text90,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Üst bant ────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: const Color(0xFF1A1A2E),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Resmi Belge',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.c.amberText,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'sandık · ${LegalDocs._web}',
                  style:
                      GoogleFonts.dmSans(fontSize: 11, color: context.c.text58),
                ),
              ],
            ),
          ),
          // ── İçerik ──────────────────────────────────────────────────────
          Expanded(
            child: NotificationListener<ScrollMetricsNotification>(
              // Kısa belgelerde scroll gerekmiyorsa buton hemen aktifleşsin.
              onNotification: (n) {
                if (!widget.confirmMode || _reachedBottom) return false;
                if (n.metrics.maxScrollExtent <= 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _reachedBottom = true);
                  });
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: EdgeInsets.only(
                    bottom: widget.confirmMode ? 24 : 48),
                itemCount: widget.blocks.length,
                itemBuilder: (_, i) => _buildBlock(widget.blocks[i], i),
              ),
            ),
          ),
          if (widget.confirmMode) _buildConfirmBar(context),
        ],
      ),
    );
  }

  Widget _buildConfirmBar(BuildContext context) {
    final active = _reachedBottom;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          border: Border(
            top: BorderSide(color: context.c.hairline, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!active)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: context.c.text58),
                    const SizedBox(width: 4),
                    Text(
                      'Onaylamak için belgeyi sona kadar okuyun',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: context.c.text58,
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: active ? () => Navigator.pop(context, true) : null,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: active
                      ? context.c.amberFill.withValues(alpha: 0.95)
                      : context.c.amberFill.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      active
                          ? Icons.check_circle_rounded
                          : Icons.lock_outline_rounded,
                      size: 18,
                      color: active
                          ? const Color(0xFF1A1A2E)
                          : Colors.black.withValues(alpha: 0.35),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.confirmButtonLabel,
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: active
                            ? const Color(0xFF1A1A2E)
                            : Colors.black.withValues(alpha: 0.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlock(LegalBlock block, int index) {
    switch (block.type) {
      case LegalBlockType.h1:
        return _DocH1(block.text);
      case LegalBlockType.h2:
        return _DocH2(block.text);
      case LegalBlockType.h3:
        return _DocH3(block.text);
      case LegalBlockType.paragraph:
        return _DocParagraph(block.text);
      case LegalBlockType.meta:
        return _DocMeta(block.text);
      case LegalBlockType.divider:
        return const _DocDivider();
      case LegalBlockType.tableHeader:
        return _DocTableRow(block.cells, isHeader: true);
      case LegalBlockType.tableRow:
        // Her satır için index tabanlı zebra rengi
        return _DocTableRow(block.cells, isHeader: false, isEven: index.isEven);
    }
  }
}

// ─── Blok widget'ları ─────────────────────────────────────────────────────────

const _kPH = 20.0;

class _DocH1 extends StatelessWidget {
  final String text;
  const _DocH1(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 28, _kPH, 8),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0D1B2A),
            height: 1.2,
          ),
        ),
      );
}

class _DocH2 extends StatelessWidget {
  final String text;
  const _DocH2(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 24, _kPH, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0D1B2A),
              ),
            ),
            const SizedBox(height: 6),
            Container(height: 2, width: 32, color: context.c.amberText),
          ],
        ),
      );
}

class _DocH3 extends StatelessWidget {
  final String text;
  const _DocH3(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 16, _kPH, 4),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1B5E20),
          ),
        ),
      );
}

class _DocParagraph extends StatelessWidget {
  final String text;
  const _DocParagraph(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 8, _kPH, 0),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 13.5,
            color: const Color(0xFF2C3E50),
            height: 1.65,
          ),
        ),
      );
}

class _DocMeta extends StatelessWidget {
  final String text;
  const _DocMeta(this.text);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(_kPH, 8, _kPH, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8E4DC),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: const Color(0xFF5A6478),
            height: 1.5,
          ),
        ),
      );
}

class _DocDivider extends StatelessWidget {
  const _DocDivider();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(_kPH, 20, _kPH, 4),
        child: Divider(
          color: const Color(0xFF0D1B2A).withValues(alpha: 0.12),
          height: 1,
        ),
      );
}

class _DocTableRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool isEven;
  const _DocTableRow(this.cells, {required this.isHeader, this.isEven = false});

  @override
  Widget build(BuildContext context) {
    final rowBg = isHeader
        ? const Color(0xFF1A1A2E)
        : isEven
            ? const Color(0xFFF0EDE6)
            : const Color(0xFFF7F5F0);

    return Container(
      margin: EdgeInsets.only(
        top: isHeader ? 16 : 0,
        left: _kPH,
        right: _kPH,
      ),
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(color: const Color(0xFF0D1B2A).withValues(alpha: 0.08)),
          left: BorderSide(
            color: isHeader
                ? context.c.amberFill
                : const Color(0xFF0D1B2A).withValues(alpha: 0.08),
            width: isHeader ? 3 : 1,
          ),
          right: BorderSide(color: const Color(0xFF0D1B2A).withValues(alpha: 0.08)),
          top: isHeader
              ? BorderSide.none
              : BorderSide(color: const Color(0xFF0D1B2A).withValues(alpha: 0.04)),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(cells.length, (i) {
            final isLast = i == cells.length - 1;
            return Expanded(
              flex: i == 0 ? 2 : 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: isLast
                    ? null
                    : BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: const Color(0xFF0D1B2A).withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                child: Text(
                  cells[i],
                  style: GoogleFonts.dmSans(
                    fontSize: isHeader ? 11 : 12.5,
                    fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
                    color: isHeader ? Colors.white : const Color(0xFF2C3E50),
                    height: 1.4,
                    letterSpacing: isHeader ? 0.4 : 0,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
