# KVKK Aydınlatma Metni — sandık

**Yürürlük tarihi:** 5 Ekim 2026
**Son güncelleme:** 5 Ekim 2026
**Sürüm:** 1.4

---

## 1. Veri Sorumlusunun Kimliği

6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 10 uyarınca, kişisel verilerinizin işlenmesine ilişkin olarak veri sorumlusu sıfatıyla aşağıdaki bilgilendirmeyi yaparız.

| Bilgi | Detay |
|---|---|
| Veri Sorumlusu | `Yasin Çıralı` |
| Adres | `İstanbul, Türkiye` |
| Vergi No | `Yok (bireysel geliştirici — ticari faaliyet başlatılmamıştır)` |
| VERBİS No | `Kayıtlı değil (bireysel geliştirici; VERBİS kaydı ticari faaliyet başlangıcında yapılacaktır)` |
| KEP Adresi | `Yok (bireysel geliştirici)` |
| E-posta | `sandikapp.destek@gmail.com` |
| Telefon | `E-posta ile iletişim: sandikapp.destek@gmail.com` |

---

## 2. İşlenen Kişisel Veri Kategorileri

### 2.1 Kimlik Verisi
- E-posta adresi
- Kullanıcı adı (görünen ad)
- Apple veya Google ile girişte sağlayıcının paylaştığı e-posta ve ad

### 2.2 İletişim Verisi
- Bildirim için kayıtlı cihaz token'ı (push)
- Kilit ekranı canlı etkinliği token'ı (iOS, açarsanız)

### 2.3 Müşteri İşlem Verisi
- Portföy varlık kayıtları (sembol, tür, miktar, alış fiyatı, komisyon, para birimi, tarih, not), vadeli mevduat ve BES sözleşme bilgileri, temettü kayıtları
- Takip listesi, fiyat alarmları, bildirim tercihleri, hedef tutarı
- Portföy anlık görüntüleri (saatlik toplam değer)
- Dönemsel getiri yüzdesi, varlık türü payları ve fon kodu bazında paylar (Zirvedeki Portföyler anonim havuzu; yalnızca açık rıza verirseniz)
- Dönemsel getiri yüzdesi ve varlık türü payları (Yarış; yalnızca katılırsanız)
- Ortaklık bağlantıları ve davet kodları

### 2.4 İşlem Güvenliği Verisi
- Şifre (bcrypt hash — geri çevrilemez)
- Oturum token'ı (JWT)
- IP adresi ve cihaz/tarayıcı bilgisi (oturum açma, kod doğrulama ve oturum yenileme anında; Supabase Auth güvenlik kaydı)
- Kayıtlı cihazlar: cihaz adı (model, iOS sürümü), platform, rastgele cihaz numarası, ilk ve son görülme zamanı
- Cihaz modeli, OS sürümü, uygulama sürümü
- Hata kayıtları ve hata raporları (hassas alanlar maskelenerek)

### 2.5 Hukuki İşlem Verisi
- Yasal metin onay ve bilgilendirme kayıtları: kabul edilen ya da size sunulan metin ve sürümü, zamanı, alındığı ekran, platform, uygulama sürümü, dil, size gösterilen sunucu ülkesi, belgeyi açıp açmadığınız ve metnin sonuna kadar okunup okunmadığı; yatırım uyarısında ayrıca cihaz modeli

### 2.6 Kullanım Verisi
- Kullanım istatistikleri (Firebase Analytics): hesap numaranız (rastgele kullanıcı kimliği), görüntülenen ekranlar, özellik kullanım olayları, kaba aralıklar, cihaz ve uygulama bilgisi, IP adresinden çıkarılan yaklaşık konum; tutar, miktar ve e-posta gönderilmez
- Kurulum adımları (kayıt hunisi): rastgele kurulum numarası, adım, platform, uygulama sürümü, kayıt hatasının kodu

---

## 3. Kişisel Verilerin İşlenme Amaçları

| Amaç | Veri kategorileri |
|---|---|
| Hesap oluşturma ve oturum yönetimi | 2.1, 2.4 |
| Portföy takibi (uygulamanın ana işlevi) | 2.3 |
| Zirvedeki Portföyler — anonim karşılaştırma | 2.3 |
| Yarış — yüzdelik dilim ve ortakla karşılaştırma | 2.3 |
| Performans grafiklerinin hesaplanması | 2.3 |
| Ortaklık özelliği (kullanıcılar arası paylaşım) | 2.1, 2.3 |
| Push bildirim ve kilit ekranı canlı etkinliği | 2.2, 2.3 |
| Yasal yükümlülüklerin yerine getirilmesi ve onayların kanıtlanması (yasal metin onayları, mahkeme/savcılık talepleri) | 2.5, 2.4 |
| Hata teşhisi ve uygulama güvenliği (tek aktif cihaz, yeni cihazda e-posta kodu) | 2.4 |
| Kötüye kullanım, sahtekarlık ve siber saldırı tespiti | 2.4 |
| Ürünün iyileştirilmesi ve kayıt sürecindeki sorunların tespiti | 2.6 |

---

## 4. Kişisel Verilerin Toplanma Yöntemi ve Hukuki Sebebi

### 4.1 Toplanma Yöntemi
- **Doğrudan kullanıcıdan:** Kayıt formu, Apple/Google ile giriş, varlık ekleme ve ekstre içe aktarma (ekstre dosyası yalnızca cihazda okunur, sunucuya gönderilmez), profil ve bildirim ayarları
- **Otomatik:** Oturum açma anında IP/cihaz bilgisi, push token kaydı, kayıtlı cihaz bilgisi, hata kayıtları ve hata raporları, kullanım istatistikleri, kayıt hunisi adımları

### 4.2 Hukuki Sebep (KVKK Madde 5 ve 6)

| Veri | Hukuki sebep |
|---|---|
| E-posta, şifre, kullanıcı adı | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası için zorunlu |
| Portföy verileri | KVKK 5(2)(c) — sözleşmenin ifası |
| Yarış ölçümleri (getiri %, tür payı %) | KVKK 5(2)(c) — isteğe bağlı özelliğin ifası (katılırsanız) |
| Zirve havuzu ölçümleri (getiri %, tür payı %) | KVKK 5(1) — açık rıza (uygulama içinde, isteğe bağlı; her an geri alınabilir) |
| Push token | KVKK 5(2)(c) — bildirim izni verdiğinizde istediğiniz bildirimlerin teslimi |
| IP, cihaz bilgisi, kayıtlı cihazlar, hata kayıtları | KVKK 5(2)(f) — meşru menfaat (güvenlik ve hata teşhisi) |
| Kullanım istatistikleri ve kayıt hunisi | KVKK 5(2)(f) — meşru menfaat (ürünün iyileştirilmesi) |
| Yasal metin onay kayıtları | KVKK 5(2)(e) — bir hakkın tesisi, kullanılması veya korunması; yatırım uyarısı için KVKK 5(2)(a) |
| Yurt dışı aktarımı (Supabase: {SUPABASE_ULKE}; Firebase: ABD) | KVKK 5(1) ve 9(1) — açık rıza |

---

## 5. Kişisel Verilerin Aktarıldığı Taraflar ve Aktarım Amacı

### 5.1 Yurt İçi Aktarım
Yurt içinde üçüncü kişilere aktarım yapılmamaktadır. Ortaklık kurduğunuz kullanıcı, kullanıcı adınızı ve paylaşılan portföyünüzü görür.

### 5.2 Yurt Dışı Aktarım

| Alıcı | Ülke | Veri | Amaç | Hukuki sebep |
|---|---|---|---|---|
| Supabase Inc. | {SUPABASE_ULKE} | Tüm hesap ve uygulama verileri, güvenlik kayıtları | Veritabanı ve kimlik doğrulama altyapısı | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Cloud Messaging) | ABD / Küresel | Push token, bildirim içeriği | Bildirim teslimi | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Crashlytics) | ABD / Küresel | Hata kaydı, cihaz modeli, OS ve uygulama sürümü | Çökme teşhisi | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Analytics ve Remote Config) | ABD / Küresel | Kullanım istatistikleri, rastgele kurulum kimliği | Ürün iyileştirme, özellik ayarları | KVKK 9(1) — açık rıza |
| Google LLC (Gmail e-posta altyapısı) | ABD / Küresel | E-posta adresi, doğrulama kodu | Kod e-postalarının teslimi | KVKK 9(1) — açık rıza |
| Apple Inc. (Apple Push Notification service) | ABD / Küresel | Bildirim içeriği, canlı etkinlik token'ı ve kilit ekranı özeti | iPhone'a teslim | KVKK 9(1) — açık rıza |
| Apple Inc. / Google LLC (Apple ile Giriş, Google ile Giriş — seçerseniz) | ABD / Küresel | Giriş sırasında sağlayıcıyla doğrulama | Kimlik doğrulama | KVKK 9(1) — açık rıza |

Fiyat ve piyasa verisi sağlayıcılarına (Yahoo Finance, TEFAS, finans.truncgil.com, Binance, TCMB, EGM, open.er-api.com) kişisel veri aktarılmaz; yalnızca sembol / fon kodu sorgusu gönderilir. Cihazdan giden isteklerde sağlayıcı, her internet isteğinde olduğu gibi cihazın IP adresini görür.

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase: ABD), Kişisel Verileri Koruma Kurulu'nun (KVK Kurulu) ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmamaktadır**. Bu nedenle yurt dışı aktarımı KVKK Madde 9(1) kapsamında **açık rızanıza** dayanmaktadır.

Açık rızanız, kayıt sırasında (Apple veya Google ile ilk girişte onay ekranında) sonuna kadar okuyup metnin sonunda onayladığınız "Açık Rıza Metni" ile, başka bir beyanla birleştirilmeden, belirli, bilgilendirilmiş ve özgür iradeyle alınmaktadır.

### 5.3 Diğer Kullanıcılara Anonim Çıktı (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

---

## 6. Kişisel Verilerin Saklanma Süresi

| Veri | Saklama süresi | Dayanak |
|---|---|---|
| Hesap verileri (e-posta, kullanıcı adı) | Hesap silinene kadar | Sözleşme süresi |
| Portföy varlık kayıtları ve sözleşme bilgileri | Hesap silinene kadar | Sözleşme süresi |
| Portföy anlık görüntüleri | Son 2 yıl (730 gün) rolling | Servis ihtiyacı |
| Zirve havuzu ölçümleri | Son 365 gün rolling; rıza geri alınınca ya da hesap silinince hemen | Servis ihtiyacı |
| Yarış ölçümleri | Son 365 gün rolling; hesap silinince hemen | Servis ihtiyacı |
| Kayıtlı cihazlar | Cihazı listeden silene ya da hesap silinene kadar | KVKK 5(2)(f) meşru menfaat |
| Push token | Çıkış yapılana ya da token geçersizleşene (uygulama silinene) kadar | Sözleşme süresi |
| Yasal metin onay kayıtları (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı) | Hesap silinmesinden sonra **3 yıl** | TBK Madde 146 (zamanaşımı) |
| Anonim hesap silme kaydı (hesap kimliğinin tek yönlü özeti, e-posta alan adı, silme zamanı ve nedeni) | Hesap silinmesinden sonra **3 yıl**; süresi dolanlar her gün otomatik silinir | TBK Madde 146 (zamanaşımı) |
| Bildirim kayıtları (uygulama içi, fiyat alarmı) | 90 gün | Servis ihtiyacı |
| Hata kayıtları (db_logs, yalnızca hatalar) | 30 gün | KVKK 5(2)(f) meşru menfaat |
| Hata raporları (Crashlytics) | 90 gün | KVKK 5(2)(f) meşru menfaat |
| Kullanım istatistikleri (Firebase Analytics) | Firebase'deki saklama ayarı kadar, en fazla 14 ay | KVKK 5(2)(f) meşru menfaat |
| Kayıt hunisi adımları | 400 gün | KVKK 5(2)(f) meşru menfaat |
| Oturum açma güvenlik kaydı (IP, cihaz/tarayıcı; Supabase Auth güvenlik kaydı) | 90 gün; eskileri her gün otomatik silinir | KVKK 5(2)(f) meşru menfaat |

Saklama süresi sona eren veriler **kalıcı olarak silinir veya anonimleştirilir**. Hesabınızı uygulamadan sildiğinizde hesabınız ve girdiğiniz veriler hemen silinir; yukarıda hesap silindikten sonra da süresi devam eden kayıtlar istisnadır (hata kayıtları ve kayıt hunisi adımları hesapla bağı kaldırılarak tutulur).

---

## 7. Kişisel Veri Sahibinin KVKK Madde 11 Hakları

KVKK Madde 11 uyarınca aşağıdaki haklara sahipsiniz:

a) Kişisel verilerinizin işlenip işlenmediğini öğrenme,
b) İşlenmişse buna ilişkin bilgi talep etme,
c) İşlenme amacını ve amacına uygun kullanılıp kullanılmadığını öğrenme,
ç) Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme,
d) Eksik veya yanlış işlenmişse düzeltilmesini isteme,
e) KVKK 7. madde kapsamında silinmesini veya yok edilmesini isteme,
f) (d) ve (e) bentleri uyarınca yapılan işlemlerin aktarıldığı üçüncü kişilere bildirilmesini isteme,
g) İşlenen verilerin münhasıran otomatik sistemler vasıtasıyla analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme,
ğ) Kanuna aykırı işlenmesi sebebiyle zarara uğramanız hâlinde zararın giderilmesini talep etme.

### 7.1 Başvuru Yöntemi

KVKK Madde 13 ve "Veri Sorumlusuna Başvuru Usul ve Esasları Hakkında Tebliğ" uyarınca taleplerinizi şu yöntemlerden biriyle iletebilirsiniz:

1. **Uygulama içi:** Profil → Ayarlar → "Hesabımı Sil" (anında silme) / "Verilerimi İndir" (JSON dosyası)
2. **E-posta:** `sandikapp.destek@gmail.com` adresine, sistemimizde kayıtlı e-posta adresinizden, kimlik bilgileriniz (ad-soyad, T.C. kimlik no veya başka kimlik tanımlayıcı), iletişim bilgileriniz ve talep konusunu açıkça belirten yazılı başvuru
3. **Web formu:** `https://yasincirali.github.io/sandikapp/data-request`

Başvurunuza **30 gün** içinde ücretsiz olarak yanıt veririz. KVK Kurulu'nun belirlediği tarifedeki ücretler haklı sebeplerle istenebilir (Tebliğ Madde 7).

### 7.2 Şikayet Hakkı

Yanıttan memnun kalmazsanız veya 30 gün içinde yanıt alamazsanız, KVKK Madde 14 uyarınca **Kişisel Verileri Koruma Kurulu**'na şikayet edebilirsiniz:

Kişisel Verileri Koruma Kurumu
Nasuh Akar Mah. Ziyabey Cad. 1407. Sok. No: 4 06520 Balgat / Çankaya / ANKARA
Web: www.kvkk.gov.tr
E-posta: kvkk@kvkk.gov.tr

---

## 8. Veri Güvenliği

KVKK Madde 12 uyarınca aldığımız önlemler:

**Teknik Önlemler:**
- TLS 1.2+ ile aktarım şifrelemesi
- AES-256 ile at-rest şifreleme
- Bcrypt ile şifre hash'leme
- Row-Level Security (RLS) ile yetkisiz erişim engeli
- Rate limiting ile brute-force saldırı koruması
- Oturum token'ının cihazın güvenli anahtar deposunda saklanması; 10 dakikadan uzun arka planda kalınca kilit ya da oturum kapanışı
- Hesabın aynı anda tek cihazda açık kalması; yeni cihazda e-posta kodu
- Production loglarında PII maskeleme

**İdari Önlemler:**
- Veri işleyenlerin (Supabase, Google, Apple) veri işleme sözleşmeleri (DPA)
- Bireysel geliştirici: veriye geliştiriciden başka kimse erişmez; erişim yalnızca destek, hata teşhisi ve yasal yükümlülükler için kullanılır
- Erişim yetkisi prensibi (least-privilege); yönetim paneli yetkisi sunucuda denetlenir
- Veri ihlali yönetimi süreci (72 saat içinde Kurul'a bildirim)
- Düzenli güvenlik denetimleri

---

## 9. Veri İhlali Durumunda Bildirim

KVKK Madde 12(5) uyarınca, kişisel verilerinizin yetkisiz kişilerce ele geçirildiğini tespit etmemiz hâlinde:

- En geç **72 saat** içinde KVK Kurulu'na bildirim yaparız
- Etkilenen veri sahiplerine (size) **makul en kısa sürede** doğrudan bildirim yaparız (e-posta + uygulama içi)
- KVK Kurulu'nun ilan ettiği "Veri İhlali Bildirim Formu"nu kullanırız

---

## 10. Politikada Değişiklikler

Bu Aydınlatma Metni'nde değişiklik yaptığımızda:
- Yeni sürüm uygulama içinde ve web sitesinde aynı metinle yayımlanır
- "Sürüm" numarası artırılır
- Önemli değişikliklerde bir sonraki açılışta güncel metin ve değişikliklerin özeti gösterilir; devam etmeden önce güncel metinle bilgilendirildiğinizi onay kutusunda belirtmeniz istenir
- Önceki sürümlerin tam metni ve hangi sürümün size ne zaman sunulduğu kayıt altında tutulur; talep ederseniz e-postayla gönderilir

---

*Bu Aydınlatma Metni kayıt sırasında (Apple veya Google ile ilk girişte açılan onay ekranında da) size bağlantı olarak sunulur; dokunduğunuzda tam metni açılır. Aydınlatma bilgilendirme amaçlıdır ve onayınıza bağlı değildir: onay kutusunda bu metinle bilgilendirildiğinizi belirtirsiniz ve metnin size sunulduğu kayıt altına alınır. Yurt dışı aktarım için açık rızanız bundan ayrı olarak Açık Rıza Metni ile alınır.*

---

**`Yasin Çıralı`**
**`Türkiye`**
**`sandikapp.destek@gmail.com`**
