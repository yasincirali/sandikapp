# Gizlilik Politikası — sandık

**Yürürlük tarihi:** 4 Ekim 2026
**Son güncelleme:** 4 Ekim 2026
**Sürüm:** 1.2

---

## 1. Veri Sorumlusu

Bu uygulamayı (**sandık**, "Uygulama") `Yasin Çıralı` ("biz", "Şirket") işletmektedir.

- **Adres:** `İstanbul, Türkiye`
- **E-posta:** `sandikapp.destek@gmail.com`
- **Web:** `https://yasincirali.github.io/sandikapp`
- **VERBİS:** `Kayıtlı değil (bireysel geliştirici)` (uygulanabilirse)

KVKK Madde 3(1)(ı) uyarınca veri sorumlusu sıfatıyla hareket ediyoruz.

---

## 2. Bu Politikanın Kapsamı

Bu politika, Uygulamayı indirip kullandığınızda hangi kişisel verilerinizi topladığımızı, neden topladığımızı, kimlerle paylaştığımızı, ne kadar sakladığımızı ve yasal haklarınızı açıklar.

Politika; KVKK (6698 sayılı Kişisel Verilerin Korunması Kanunu), GDPR (EU 2016/679), Apple App Store Privacy Guidelines ve Google Play Data Safety gerekliliklerini karşılayacak şekilde hazırlanmıştır.

---

## 3. Topladığımız Veriler

### 3.1 Hesap Verileri (zorunlu)
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| E-posta adresi | Hesap oluşturma, oturum açma, şifre sıfırlama, yeni cihaz doğrulama kodu | KVKK 5(2)(c) — sözleşme; GDPR 6(1)(b) |
| Şifre (hash) | Kimlik doğrulama (Apple veya Google ile girişte şifre yoktur) | KVKK 5(2)(c); GDPR 6(1)(b) |
| Kullanıcı adı (görünen ad) | Ortağınıza, bildirimlerde ve davet yanıtında görünen ad | KVKK 5(2)(c); GDPR 6(1)(b) |
| Apple veya Google ile girişte sağlayıcının paylaştığı e-posta ve ad | Hesap oluşturma; ad yalnızca ilk görünen ad olarak kullanılır | KVKK 5(2)(c); GDPR 6(1)(b) |

### 3.2 Uygulama İçeriği Verileri (kullanıcı tarafından girilir)
| Veri | Amaç |
|---|---|
| Varlık kayıtları (sembol, tür, miktar, alış fiyatı, komisyon, para birimi, tarih, not), vadeli mevduat ve BES sözleşme bilgileri, temettü kayıtları | Portföy takibi (Uygulamanın ana işlevi) |
| Takip listesi, fiyat alarmları, bildirim tercihleri (sinyal ayarları, sessiz saatler, brifing saati), hedef tutarı | İlgili özelliklerin çalışması |
| Portföy anlık görüntüleri (saatlik toplam değer) | Performans grafikleri |
| Dönemsel getiri (%), varlık türü payları (%) ve fon kodu bazında paylar (%) — sunucuda hesaplanır | Zirvedeki Portföyler (anonim karşılaştırma, bkz. §5.1; yalnızca açık rıza verirseniz) |
| Dönemsel getiri (%) ve varlık türü payları (%) — sunucuda günlük hesaplanır | Yarış (isteğe bağlı; yüzdelik diliminiz ve ortağınızla karşılaştırma) |
| Ortaklık davet kodları ve karşılıklı bağlantılar | Çoklu kullanıcı paylaşımı özelliği |

**Ekstre içe aktarma:** İçe aktardığınız banka veya aracı kurum ekstresi (PDF, Excel, CSV) yalnızca cihazınızda okunur; dosya sunucuya gönderilmez ve saklanmaz. Yalnızca sizin onayladığınız varlık kayıtları kaydedilir.

### 3.3 Cihaz ve Bildirim Verileri
| Veri | Amaç |
|---|---|
| Push bildirim token'ı (FCM) | Bildirim teslimi (fiyat alarmı, sinyal, günlük brifing, dönemsel özet, ortaklık, temettü ve takvim hatırlatmaları) |
| Kayıtlı cihazlar: cihaz adı (model, iOS sürümü), platform, uygulamanın ürettiği rastgele cihaz numarası, ilk ve son görülme zamanı | Hesap güvenliği: hesabın aynı anda tek cihazda açık kalması, yeni cihazda e-posta kodu |
| Kilit ekranı canlı etkinliği (iOS, açarsanız): etkinlik token'ı ile portföy toplamı ve günlük değişim metni ("tutarları gizle" açıksa maskelenir) | Kilit ekranındaki portföy özetinin güncellenmesi |
| Cihaz modeli, OS sürümü, uygulama sürümü | Hata teşhisi, kayıtlı cihazlar listesi, onay kayıtları |
| Yerel ayar (locale) | Dil/tarih formatı, onay kayıtları |
| IP adresi ve cihaz/tarayıcı bilgisi (oturum açma, kod doğrulama ve oturum yenileme anında) | Hesap güvenliği ve kötüye kullanım tespiti (Supabase Auth güvenlik kaydı) |

### 3.4 Yasal Onay Kayıtları
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| Yasal metin onayları: onaylanan metin ve sürümü, onay zamanı, onayın alındığı ekran, platform, uygulama sürümü, dil ve size gösterilen sunucu ülkesi; yatırım uyarısında ayrıca cihaz modeli | Hangi metni hangi sürümüyle ne zaman onayladığınızın kanıtı | KVKK 5(2)(e) — bir hakkın tesisi, kullanılması veya korunması; yatırım uyarısı için KVKK 5(2)(a) |

### 3.5 Otomatik Toplanan Veriler
| Veri | Amaç |
|---|---|
| Hata raporları (Firebase Crashlytics): çökme ve hata kaydı, cihaz modeli, OS ve uygulama sürümü, Crashlytics'in rastgele kurulum kimliği | Çökme teşhisi; e-posta, ad ve portföy değeri gönderilmez |
| Kullanım istatistikleri (Firebase Analytics): hesap numaranız (rastgele kullanıcı kimliği), görüntülenen ekranlar, özellik kullanım olayları (ör. varlık ekleme ve türü, bildirim açma, sinyal görüntüleme ve sembolü), kaba aralıklar (ör. varlık sayısı aralığı), cihaz ve uygulama bilgisi, Google'ın IP adresinden çıkardığı yaklaşık konum (ülke/şehir) | Ürünün nasıl kullanıldığını anlamak ve iyileştirmek; tutar, miktar ve e-posta gönderilmez, reklam kimliği toplanmaz |
| Uzaktan ayarlar (Firebase Remote Config): Firebase'in rastgele kurulum kimliği | Özelliklerin uzaktan açılıp kapatılması |
| Kurulum adımları (kayıt hunisi): uygulamanın ürettiği rastgele kurulum numarası, adım (ilk açılış, kayıt ekranı, kod doğrulama vb.), platform, uygulama sürümü, kayıt hatasının kodu; giriş yapınca hesabınıza bağlanır | Kayıt sürecindeki sorunların tespiti |
| Yapısal hata kayıtları | Yalnızca **hata** durumunda; istek bilgisi ve hata mesajı, hassas alanlar (e-posta, şifre, token, IP) maskelenerek |

### Toplamadığımız Veriler
- GPS konumu (uygulama konum izni istemez)
- Telefon defteri
- Fotoğraf / kamera
- Reklam tanımlayıcısı
- Üçüncü taraf reklam ağı izleme verisi
- Banka hesap bilgileri (uygulama hiçbir banka API'sine bağlanmaz; ekstre dosyası yalnızca cihazda okunur)
- Biyometrik veri (uygulama kilidi cihazın kendi Face ID / parmak izi doğrulamasını kullanır; biyometrik veri uygulamaya ulaşmaz)

---

## 4. Verilerin Kullanım Amaçları

1. Hesabınızı oluşturmak ve oturumunuzu sürdürmek
2. Portföyünüzü cihazınızda ve sunucularımızda saklamak
3. Performans grafiklerinizi hesaplamak
4. Ortaklık davetlerinizi diğer kullanıcılara iletmek
5. Bildirim göndermek (yalnızca işletim sisteminin bildirim izni verildiyse)
6. Yasal yükümlülüklerimizi yerine getirmek ve onaylarınızı kanıtlamak (yasal metin onayları, yetkili merci talepleri)
7. Hata teşhisi ve servis kalitesinin iyileştirilmesi; kullanım istatistikleri
8. Hesap güvenliği (tek aktif cihaz, yeni cihazda e-posta kodu) ile kötüye kullanım, sahtekarlık ve siber saldırıların tespiti (KVKK 5(2)(f) meşru menfaat)
9. Zirvedeki Portföyler: dönemin en çok kazanan portföylerinin getirisini ve varlık türü dağılımını katılımcılar arasında anonim olarak göstermek (KVKK 5(1) — açık rıza; isteğe bağlı, uygulama içinde verilir)
10. Yarış: katılırsanız dönemsel getirinizi hesaplayıp yüzdelik diliminizi ve ortağınızla karşılaştırmanızı göstermek

---

## 5. Verilerin Paylaşıldığı Üçüncü Taraflar (Veri İşleyenler)

| Hizmet | Sağlayıcı | Veri | Amaç | Yer |
|---|---|---|---|---|
| Backend & veritabanı | Supabase Inc. | Tüm hesap ve uygulama verileri, güvenlik kayıtları | Saklama, kimlik doğrulama | {SUPABASE_ULKE} |
| Push bildirimi | Google Firebase Cloud Messaging | Push token, bildirim içeriği | Bildirim teslimi | Küresel (Google) |
| iOS bildirimleri ve canlı etkinlik | Apple Push Notification service | Bildirim içeriği, canlı etkinlik token'ı ve kilit ekranı özeti | iPhone'a teslim | Küresel (Apple) |
| Hata raporu | Google Firebase Crashlytics | Hata kaydı, cihaz modeli, OS ve uygulama sürümü | Çökme teşhisi | Küresel (Google) |
| Kullanım istatistikleri | Google Firebase Analytics | Bkz. §3.5 | Ürün iyileştirme | Küresel (Google) |
| Uzaktan ayarlar | Google Firebase Remote Config | Rastgele kurulum kimliği | Özellik ayarları | Küresel (Google) |
| E-posta gönderimi | Google (Gmail e-posta altyapısı) | E-posta adresi, doğrulama/giriş kodu | Kod e-postalarının teslimi | Küresel (Google) |
| Apple ile Giriş / Google ile Giriş (seçerseniz) | Apple Inc. / Google LLC | Giriş sırasında sağlayıcıyla doğrulama | Kimlik doğrulama | Küresel |
| Fiyat ve piyasa verisi | Yahoo Finance, TEFAS, finans.truncgil.com, Binance, TCMB EVDS, EGM, open.er-api.com, yasincirali.github.io (halka arz takvimi) | Kişisel veri gönderilmez; yalnızca sembol / fon kodu sorgusu. Cihazdan giden isteklerde sağlayıcı, her internet isteğinde olduğu gibi cihazın IP adresini görür | Fiyat çekme | Küresel |

**Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder. Veri sorumlusu sıfatı tarafımızda kalır.**

### 5.1 Diğer Kullanıcılarla Anonim Paylaşım (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

### 5.2 Ortağınızla ve Yarış'ta Paylaşım

Ortaklık kurduğunuz kullanıcı, kullanıcı adınızı, portföyünüzdeki varlıkları, miktarları ve performansı görür. Yarış'ta diğer katılımcılara kimliğiniz ve tutarlarınız gösterilmez; size yalnızca kendi yüzdelik diliminiz gösterilir, ortağınızla getirilerinizi karşılaştırabilirsiniz.

---

## 6. Yurt Dışına Veri Aktarımı

Supabase veritabanı {SUPABASE_ULKEDE}, Firebase ABD'de barındırıldığı için verileriniz Türkiye dışına aktarılır. Uygulama içindeki metin, bağlı olduğunuz sunucunun ülkesini gösterir. Apple ve Google'ın bildirim, giriş ve e-posta hizmetleri de küresel altyapıda çalışır. KVKK Madde 9 ve GDPR Madde 44-49 uyarınca:

- **AB üyesi kullanıcılar için:** Standart Sözleşme Maddeleri (SCC) ve sağlayıcıların GDPR uyumluluk taahhütleri çerçevesinde aktarım yapılır.
- **Türk kullanıcılar için:** KVKK Madde 9(1) kapsamında **açık rıza** alınmaktadır. Açık rızanızı kayıt sırasında onayladığınız "Açık Rıza Metni" ile vermektesiniz.

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase: ABD), KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde olmadığından, yurt dışı aktarımı **açık rızanıza** dayanmaktadır.

---

## 7. Veri Saklama Süreleri

| Veri | Süre |
|---|---|
| Hesap verileri | Hesap silinene kadar |
| Varlık kayıtları ve sözleşme bilgileri | Hesap silinene kadar |
| Portföy anlık görüntüleri | Son 2 yıl (730 gün) rolling; eskileri her gün otomatik silinir |
| Zirve havuzu ölçümleri (getiri %, tür payı %) | Son 365 gün rolling; rıza geri alınınca ya da hesap silinince hemen |
| Yarış ölçümleri (getiri %, tür payı %) | Son 365 gün rolling; hesap silinince hemen |
| Kayıtlı cihazlar | Cihazı listeden silene ya da hesap silinene kadar |
| Yasal metin onay kayıtları (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı) | Hesap silindikten sonra **3 yıl** (TBK Madde 146 zamanaşımı) |
| Push token | Çıkış yapıldığında silinir; uygulama silinirse bir sonraki gönderimde geçersiz bulunup silinir |
| Bildirim kayıtları (uygulama içi bildirimler, fiyat alarmı bildirimleri) | 90 gün |
| Sinyal bildirimleri | Siz silene ya da hesap silinene kadar |
| Bildirim gönderim günlükleri (aynı bildirimin tekrar gönderilmemesi için) | Türüne göre 30 gün ile 18 ay arası |
| Yapısal hata kayıtları (db_logs, yalnızca hatalar) | 30 gün |
| Kayıt hunisi adımları | 400 gün |
| Hata raporları (Crashlytics) | 90 gün |
| Kullanım istatistikleri (Firebase Analytics) | Firebase'deki saklama ayarı kadar, en fazla 14 ay |
| Oturum açma güvenlik kaydı (IP, cihaz/tarayıcı) | Supabase Auth güvenlik kaydında tutulur; uygulama bu kayıt için otomatik silme süresi tanımlamamıştır |

Hesabınızı uygulamadan sildiğinizde hesabınız ve girdiğiniz bütün veriler canlı veritabanından **hemen** silinir. İstisnalar: yasal metin onay kayıtları (3 yıl), yapısal hata kayıtları ve kayıt hunisi adımları (hesapla bağı kaldırılarak kendi sürelerinin sonuna kadar), Firebase'deki hata raporları ve kullanım istatistikleri (kendi sürelerinin sonuna kadar), oturum açma güvenlik kaydı ve hesap kimliğinizin tek yönlü özeti ile e-posta alan adınızdan oluşan anonim silme kaydı.

---

## 8. Haklarınız (KVKK Madde 11 / GDPR Madde 15-22)

Bize başvurarak şu haklarınızı kullanabilirsiniz:

- **Bilgi alma hakkı:** Hangi verilerinizin işlendiğini öğrenmek
- **Erişim hakkı:** Verilerinizin bir kopyasını talep etmek
- **Düzeltme hakkı:** Yanlış/eksik verinin düzeltilmesi
- **Silme hakkı (right to erasure):** Verilerinizin silinmesi
- **Taşınabilirlik hakkı (GDPR):** Verilerinizi makine-okur formatta (JSON) almak
- **İşlemeye itiraz hakkı (GDPR):** Meşru menfaate dayanan işlemeye itiraz
- **Açık rızanızı geri çekme hakkı:** İlerideki işlemeyi durdurma

**Talep yöntemleri:**
1. **Uygulama içi:** Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"
2. **E-posta:** `sandikapp.destek@gmail.com` adresine kimlik doğrulayıcı bilgilerle başvuru
3. **Web formu:** `https://yasincirali.github.io/sandikapp/data-request`

KVKK Madde 13(2) uyarınca taleplerinize **30 gün** içinde yanıt veririz.

**Şikayet hakkı:** Cevap memnun edici değilse:
- Türkiye: Kişisel Verileri Koruma Kurumu — kvkk.gov.tr
- AB: Yerel veri koruma otoriteniz (DPA)

---

## 9. Çocukların Verileri

Uygulama 18 yaş altı için tasarlanmamıştır. Kayıt sırasında 18 yaş üzeri olduğunuzu beyan edersiniz. 18 yaş altı bir kullanıcının veri girdiğini fark edersek, hesap derhal silinir.

GDPR Madde 8 uyarınca AB içinde 16 yaş altı için ebeveyn rızası gerekir; bu yaş grubunu kabul etmiyoruz.

---

## 10. Veri Güvenliği

Aldığımız teknik ve idari önlemler:

- **Aktarım:** TLS 1.2+ (HTTPS) zorunlu
- **Saklama:** Supabase tarafında at-rest şifreleme (AES-256)
- **Erişim:** Row-Level Security (RLS) ile her kullanıcı yalnızca kendi verisine (ve ortaklık kurduğu kullanıcının paylaşılan portföyüne) erişebilir
- **Şifre:** Bcrypt hash (Supabase Auth)
- **Oturum:** 1 saat geçerli erişim token'ı ve her yenilemede değişen yenileme token'ı; token cihazın güvenli anahtar deposunda (Keychain / Android Keystore) saklanır. Uygulama 10 dakikadan uzun arka planda kalırsa uygulama kilidi açıksa kilitlenir, değilse oturum kapanır. Hesap aynı anda tek cihazda açık kalır; yeni cihazda e-posta kodu istenir
- **Kötüye kullanım:** Sunucu tarafında istek sınırlaması (rate limiting)
- **Loglama:** Üretimde sadece hatalar; hassas alanlar (e-posta, şifre, token, IP) maskelenir
- **Geliştirici erişimi:** Veritabanına teknik erişim yalnızca geliştiricidedir ve yalnızca destek, hata teşhisi ve yasal yükümlülükler için kullanılır. Yönetim paneli (yetkisi sunucuda denetlenir) hata kayıtlarını, oturum açma güvenlik kayıtlarını, kayıt hunisini ve hesap bilgisini (e-posta, ad, varlık sayısı) gösterir; portföy içeriğini göstermez

KVKK Madde 12 uyarınca veri ihlali tespiti halinde:
- En geç **72 saat** içinde KVK Kurulu'na bildirim
- Etkilenen kullanıcılara doğrudan bildirim
- AB kullanıcıları için GDPR Madde 33-34 uyumlu süreç

---

## 11. Tanımlama Bilgileri (Çerez ve Yerel Depolama)

Uygulama mobil ortamda çalıştığı için web çerezleri **kullanılmaz**. Cihazda tutulanlar:

- Oturum token'ı — güvenli anahtar deposunda (Keychain / Android Keystore)
- Tercihler (tema, dil, görünüm, bildirim ve kilit ayarları) ve "Beni hatırla" seçerseniz (ya da kayıttan hemen sonra) e-posta adresiniz — SharedPreferences / NSUserDefaults
- Çevrimdışı açılış için son portföy kaydı ile fiyat ve grafik önbelleği
- Ana ekran widget'ı için portföy özeti (iOS'ta uygulama grubu, Android'de uygulama verisi)

Çıkış yaptığınızda oturum token'ı, size ait önbellek ve tercihler ile widget verisi cihazdan silinir. Uygulamada Firebase Analytics (kullanım istatistiği) ve Crashlytics (hata raporu) bulunur (bkz. §3.5); reklam SDK'sı ve reklam kimliği yoktur. Ayrıntı: Çerez ve Yerel Depolama Politikası.

---

## 12. Yatırım Tavsiyesi Reddi (Disclaimer)

**sandık** bir portföy takip aracıdır. SPK (Sermaye Piyasası Kurulu) lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. Uygulamada gösterilen fiyat, performans, sinyal ve grafikler bilgilendirme amaçlıdır ve yatırım tavsiyesi niteliği taşımaz. Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.

Bu uyarının özeti kayıt ekranındaki onay kutusunda yer alır; Apple veya Google ile ilk girişte tam metni ayrıca gösterilir. Onayın kaydı yasal kanıt olarak saklanır.

---

## 13. Politikada Değişiklikler

Bu politikada değişiklik yaptığımızda:
- Yeni metin yeni bir sürüm numarasıyla yayımlanır; web sitesindeki ve uygulamadaki metin her zaman aynıdır
- "Son güncelleme" tarihi yenilenir
- Önemli değişikliklerde bir sonraki açılışta güncel metin ve değişikliklerin özeti gösterilir ve yeniden onayınız istenir
- Yeni bir veri işleme, üçüncü taraf ya da saklama süresi ancak bu metin güncellenerek eklenir

---

## 14. İletişim

Veri korumayla ilgili tüm soru, talep ve şikayetler için:

- **E-posta:** `sandikapp.destek@gmail.com`
- **Adres:** `İstanbul, Türkiye`
- **Veri Koruma Sorumlusu (DPO):** Atanmamıştır. Veri koruma iletişimi: `sandikapp.destek@gmail.com`

---

*Bu politika Türkçe ve İngilizce dillerinde sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*
