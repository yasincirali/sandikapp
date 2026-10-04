// ÜRETİLDİ — elle düzenleme. Kaynak: legal/tr/*.md; üreten:
// `python docs/_build_legal.py`. Kayma kilidi: test/yasal_web_esleme_test.dart.
//
// Değerler md'nin KANONİK hâlidir (BOM yok, LF, sondaki boşluk kırpılmış;
// yer tutucular doldurulmamış). Veritabanındaki `govde` ve `govde_hash`
// bu metinlerdir (`YasalMetinKatalogu`).

/// Uygulamada gösterilen yasal belgelerin kanonik md metni — anahtar
/// depo köküne göre kaynak yolu.
const yasalBelgeKaynaklari = <String, String>{
  'legal/tr/TERMS_OF_SERVICE.md': r'''# Kullanım Koşulları — sandık

**Yürürlük tarihi:** 4 Ekim 2026
**Son güncelleme:** 4 Ekim 2026
**Sürüm:** 1.2

---

## 1. Taraflar ve Kabul

Bu Kullanım Koşulları ("Koşullar"), `Yasin Çıralı` ("Şirket", "biz") tarafından sunulan **sandık** mobil uygulaması ("Uygulama", "Hizmet") ile uygulamayı kullanan gerçek kişi ("Kullanıcı", "siz") arasındaki sözleşmedir.

Uygulamayı indirip hesap oluşturarak bu Koşulları, **Gizlilik Politikası**'nı ve **KVKK Aydınlatma Metni**'ni okuduğunuzu, anladığınızı ve kabul ettiğinizi beyan edersiniz.

---

## 2. Hizmetin Tanımı

sandık, kullanıcıların aşağıdaki varlık türlerini takip edebileceği bir kişisel portföy izleme aracıdır:

- BIST hisse senetleri
- TEFAS yatırım fonları
- Döviz (USD, EUR, GBP, vb.)
- Kıymetli madenler (altın, gümüş)
- Kripto para (varsa)

Uygulama; portföy değerini, dağılımını, performansını ve isteğe bağlı olarak teknik analiz sinyallerini gösterir. Çoklu kullanıcı ortaklığı özelliğiyle iki kullanıcı portföylerini paylaşabilir.

**Zirvedeki Portföyler (isteğe bağlı):** Uygulama içinde açık rıza verirseniz dönemsel getiriniz ve varlık türü paylarınız anonim bir karşılaştırma havuzunda değerlendirilir (portföy 5 günden eski, en az 2 farklı varlık); en çok kazanan portföylerin yalnızca sırası, getirisi, tür payları ve fonların TEFAS kodu ile payları, kimlik ve tutar olmadan diğer katılımcılara gösterilir; karşılığında siz de katılımcıların aynı anonim bilgilerini görürsünüz (ayrıntı: Gizlilik Politikası §5.1). İstediğiniz an ayrılabilirsiniz; katılmamak başka hiçbir özelliği etkilemez.

---

## 3. ÖNEMLİ UYARI — Yatırım Tavsiyesi Reddi

**sandık BİR YATIRIM DANIŞMANI, ARACI KURUM VEYA PORTFÖY YÖNETİM ŞİRKETİ DEĞİLDİR.**

- Şirket, Sermaye Piyasası Kurulu (SPK) tarafından lisanslı bir kurum değildir.
- Uygulamada gösterilen fiyatlar, performans rakamları, sinyal ve grafikler **yalnızca bilgilendirme** amaçlıdır.
- Hiçbir içerik **yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık** niteliği taşımaz.
- Verilerin doğruluğu, güncelliği ve eksiksizliği için garanti vermiyoruz; üçüncü taraf veri sağlayıcılarının (Yahoo Finance, TEFAS, vb.) verileri olduğu gibi sunulur.
- Yatırım kararlarınızı **SPK lisanslı bir aracı kurum veya yatırım danışmanına danışarak** veriniz.
- Uygulamada görüntülenen verilere dayanarak verdiğiniz yatırım kararlarından doğan **hiçbir kâr/zarardan Şirket sorumlu tutulamaz**.

Bu uyarı, uygulamayı ilk açtığınızda ayrı bir disclaimer ekranında onaylatılır ve onay kaydı yasal kanıt olarak saklanır.

---

## 4. Hesap

### 4.1 Hesap Açma
- 18 yaşından büyük olmalısınız.
- Geçerli bir e-posta adresi sağlamalısınız.
- Doğru ve güncel bilgi vermelisiniz.

### 4.2 Hesap Güvenliği
- Şifrenizi kimseyle paylaşmayın.
- Şifrenizin güvenliğinden siz sorumlusunuz.
- Yetkisiz erişim şüphesinde derhal şifrenizi değiştirin ve bizi `sandikapp.destek@gmail.com` adresinden bilgilendirin.
- Hesap üzerinden gerçekleştirilen tüm işlemler size ait sayılır.

### 4.3 Tek Hesap
- Bir kişi yalnızca bir hesap oluşturabilir.
- Hesabınızı başkalarına devredemez veya satamazsınız.

---

## 5. Ortaklık Özelliği

Uygulamada bir başka kullanıcıyı "ortak" olarak ekleyebilirsiniz. Bu özellik aktive edildiğinde:

- Ortağınız sizin portföyünüzdeki varlıkları, miktarları ve performansı görebilir.
- Siz de ortağınızın portföyünü görebilirsiniz.
- Bu paylaşım **iki tarafın da onayıyla** başlar (davet kodu sistemi).
- İstediğiniz zaman ortaklığı sonlandırabilirsiniz.

**Sorumluluk:**
- Davet kodunuzu yalnızca güvendiğiniz kişiyle paylaşın.
- Ortaklık aktifken paylaşılan veriden Şirket sorumlu değildir.
- Ortaklığı sonlandırdığınızda karşı tarafın daha önce gördüğü veri kendisinde kalmış olabilir.

---

## 6. Kabul Edilebilir Kullanım

Uygulamayı kullanırken **YAPMAYACAĞINIZ** şeyler:

1. Yasalara aykırı amaçlarla kullanmak
2. Başkasının hesabına yetkisiz erişim sağlamaya çalışmak
3. Uygulamayı tersine mühendislik, decompile veya hack etmek
4. Otomatik scraping, bot veya zararlı yazılım kullanmak
5. Şirketin altyapısına aşırı yük bindiren talepler göndermek (DoS)
6. Sahte veya yanıltıcı bilgi girmek
7. Diğer kullanıcılara taciz, tehdit veya spam göndermek
8. Uygulamayı kara para aklama veya terör finansmanı amacıyla kullanmak
9. Uygulamayı modifiye edilmiş APK / jailbreak'li cihaz / emülatör tespit edilmemesi için yamayla kullanmak
10. Telif hakkı veya marka ihlali yapmak

Bu kuralların ihlali halinde **hesabınız bildirimsiz kapatılabilir**.

---

## 7. Üçüncü Taraf Servisleri

Uygulama; Supabase (backend), Firebase (bildirim), Yahoo Finance / TEFAS (fiyat verisi) gibi üçüncü taraf servisleri kullanır. Bu servislerin kesintileri, gecikmeleri veya hataları nedeniyle oluşacak sorunlardan **Şirket sorumlu değildir**.

Yahoo Finance, TEFAS gibi veri kaynaklarının sağladığı bilgiler dahil olmak üzere üçüncü taraf veri sağlayıcılarının kendi kullanım koşulları geçerlidir. Veri çekiminin geçici olarak engellenmesi durumunda, alternatif kaynaklar veya manuel veri girişi seçenekleri sunulabilir.

---

## 8. Fikri Mülkiyet

- Uygulamanın tasarımı, kodu, logosu, marka ismi ve içeriği `Yasin Çıralı`'na aittir.
- "sandık" markası, logo ve görsel kimliği telif hakkı ve marka koruması altındadır.
- Uygulamayı kişisel kullanım için indirme ve kullanma haklarınız vardır; bu haklar **devredilemez, alt-lisanslanamaz, münhasır olmayan** bir lisans niteliğindedir.
- Kendi girdiğiniz veriler (varlık kayıtlarınız) size aittir; Şirket bu veriler üzerinde yalnızca size hizmet sunmak için işleme yetkisine sahiptir.

---

## 9. Hizmet Değişiklikleri ve Sona Erdirme

### 9.1 Şirketin Hakları
- Uygulamayı önceden bildirimde bulunarak veya bulunmayarak güncelleyebiliriz.
- Belirli özellikleri kaldırabilir veya yenilerini ekleyebiliriz.
- Hizmeti tamamen sonlandırma kararı alırsak en az **30 gün önceden** bildirim yaparız ve verilerinizi indirme imkanı sunarız.

### 9.2 Kullanıcının Hakları
- İstediğiniz zaman hesabınızı silebilirsiniz (Profil → Ayarlar → Hesabımı Sil).
- Hesap silme talebi 30 gün içinde işleme alınır; tüm verileriniz kalıcı olarak silinir (yasal saklama yükümlülükleri hariç — bkz. Gizlilik Politikası §7).

### 9.3 Şirketin Sona Erdirme Hakkı
Bu Koşulları ihlal ettiğiniz tespit edilirse hesabınızı bildirimsiz askıya alabilir veya silebiliriz. Yasal mevzuat gereği zorunlu durumlarda yetkili mercilere bildirim yaparız.

---

## 10. Sorumluluğun Sınırlandırılması

Yürürlükteki kanunların izin verdiği azami ölçüde:

- Uygulama "olduğu gibi" (as-is) sunulur; her türlü açık veya zımni garanti reddedilir.
- Şirket, uygulamanın kesintisiz, hatasız veya güvenli çalışacağını garanti etmez.
- Şirketin toplam sorumluluğu, sizin son 12 ayda Şirket'e ödediğiniz toplam tutarla sınırlıdır (ücretsiz kullanımda **sıfır TL**).
- Dolaylı, arızi, özel veya cezai zararlardan (kâr kaybı, veri kaybı, iş kesintisi) sorumlu tutulamayız.

**İstisnalar:** Şirketin kasıtlı kusurundan veya ağır ihmalinden doğan zararlar; tüketici hukuku kapsamındaki devredilemez haklar bu sınırlamadan etkilenmez.

---

## 11. Tazminat

Uygulamayı ihlal ederek (Madde 6) Şirkete veya üçüncü taraflara verdiğiniz zararlardan, açılan davaların masraf ve avukat ücretleri dahil tüm sonuçlardan **siz sorumlusunuz** ve Şirketi tazmin etmeyi kabul edersiniz.

---

## 12. Tüketici Hakları

6502 sayılı Tüketicinin Korunması Hakkında Kanun (TKHK) kapsamındaki devredilemez haklarınız bu Koşullarla sınırlandırılamaz. Tüketici Hakem Heyeti veya Tüketici Mahkemesi'ne başvuru hakkınız saklıdır.

AB üyesi tüketicileri için: GDPR ve EU tüketici mevzuatından doğan haklar saklıdır. Online uyuşmazlık çözüm platformu: https://ec.europa.eu/consumers/odr

---

## 13. Mücbir Sebep

Doğal afet, savaş, terör, salgın hastalık, hükümet kararı, internet altyapısı kesintisi, üçüncü taraf servis kesintisi gibi Şirketin kontrolü dışındaki sebeplerden doğan hizmet aksaklıklarından sorumlu değiliz.

---

## 14. Bildirimler

Bize yapılacak tüm bildirimler `sandikapp.destek@gmail.com` adresine gönderilmelidir.

Size yapılacak bildirimler:
- Uygulama içi bildirim
- Hesap e-postanıza e-posta
- Push bildirimi (izin verdiyseniz)

ile gönderilebilir ve gönderim tarihinde tebliğ edilmiş sayılır.

---

## 15. Devir

- Siz haklarınızı/yükümlülüklerinizi başkasına devredemezsiniz.
- Şirket, birleşme, devralma veya yeniden yapılanma durumunda haklarını ve yükümlülüklerini halefine devredebilir; bu durumda 30 gün önceden bildirim yapılır.

---

## 16. Bölünebilirlik

Bu Koşulların herhangi bir maddesi geçersiz sayılırsa, geri kalan maddeler yürürlükte kalmaya devam eder.

---

## 17. Uygulanacak Hukuk ve Yetkili Mahkeme

- **Uygulanacak hukuk:** Türkiye Cumhuriyeti hukuku
- **Yetkili mahkeme:** `[YETKİLİ MAHKEME — örn. İstanbul Anadolu Tüketici Mahkemeleri ve İcra Daireleri]`

Tüketici sıfatı taşıyan kullanıcılar için TKHK uyarınca yerleşim yeri mahkemeleri de yetkilidir.

AB üyesi tüketiciler için Roma I Tüzüğü uyarınca yerleşim yeri ülkesinin zorunlu tüketici koruma hükümleri saklıdır.

---

## 18. Koşullarda Değişiklik

Bu Koşullarda değişiklik yaparsak:
- En az **30 gün önceden** uygulama içi bildirim ve e-posta ile haber veririz.
- Önemli değişiklikler için tekrar onay isteyebiliriz.
- Değişikliği kabul etmiyorsanız hesabınızı silme hakkınız vardır.
- 30 gün içinde itiraz etmezseniz değişikliği kabul etmiş sayılırsınız.

---

## 19. İletişim

`Yasin Çıralı`
`İstanbul, Türkiye`
E-posta: `sandikapp.destek@gmail.com`
Web: `https://yasincirali.github.io/sandikapp`

---

*Bu Koşullar [Türkçe] ve [İngilizce] olarak sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*''',
  'legal/tr/PRIVACY_POLICY.md': r'''# Gizlilik Politikası — sandık

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
| E-posta adresi | Hesap oluşturma, oturum açma, şifre sıfırlama | KVKK 5(2)(c) — sözleşme; GDPR 6(1)(b) |
| Şifre (hash) | Kimlik doğrulama | KVKK 5(2)(c); GDPR 6(1)(b) |
| Görünen ad (display name) | Ortaklık özelliğinde diğer kullanıcılara isim göstermek | KVKK 5(2)(c); GDPR 6(1)(b) |

### 3.2 Uygulama İçeriği Verileri (kullanıcı tarafından girilir)
| Veri | Amaç |
|---|---|
| Varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not) | Portföy takibi (Uygulamanın ana işlevi) |
| Portföy snapshot geçmişi | Performans grafikleri |
| Dönemsel getiri (%), varlık türü payları (%) ve fon kodu bazında paylar (%) — sunucuda hesaplanır | Zirvedeki Portföyler (anonim karşılaştırma, bkz. §5.1) |
| Ortaklık davet kodları ve karşılıklı bağlantılar | Çoklu kullanıcı paylaşımı özelliği |

### 3.3 Cihaz ve Bildirim Verileri
| Veri | Amaç |
|---|---|
| Push bildirim token'ı (FCM) | Ortaklık daveti ve sinyal bildirimleri |
| Cihaz modeli, OS sürümü, uygulama sürümü | Hata teşhisi (yalnızca disclaimer onayı sırasında) |
| Yerel ayar (locale) | Dil/tarih formatı |

### 3.4 Yasal Onay Kayıtları
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| Disclaimer onay zamanı, IP, sürüm, platform | Yatırım danışmanlığı reddi onayının kanıtı | KVKK 5(2)(a) — kanunda öngörülmesi; SPK mevzuatı |

### 3.5 Otomatik Toplanan Veriler
| Veri | Amaç |
|---|---|
| Hata raporları (Crashlytics) | Çökme teşhisi (kişisel veri içermez, anonim cihaz id) |
| Yapısal log kayıtları | Yalnızca üretimde **hata** durumunda; hassas alanlar (e-posta, şifre, token) maskelenir |

### Toplamadığımız Veriler
- Konum
- Telefon defteri
- Fotoğraf / kamera
- Reklam tanımlayıcısı
- Üçüncü taraf reklam ağı izleme verisi
- Banka hesap bilgileri (uygulama hiçbir banka API'sine bağlanmaz)

---

## 4. Verilerin Kullanım Amaçları

1. Hesabınızı oluşturmak ve oturumunuzu sürdürmek
2. Portföyünüzü yerel cihazınızda ve sunucularımızda saklamak
3. Performans grafiklerinizi hesaplamak
4. Ortaklık davetlerinizi diğer kullanıcılara iletmek
5. Bildirim göndermek (yalnızca açıkça izin verdiyseniz)
6. Yasal yükümlülüklerimizi yerine getirmek (disclaimer kanıtı, yetkili merci talepleri)
7. Hata teşhisi ve servis kalitesinin iyileştirilmesi
8. Kötüye kullanım, sahtekarlık ve siber saldırıların tespiti (KVKK 5(2)(f) meşru menfaat)
9. Zirvedeki Portföyler: dönemin en çok kazanan portföylerinin getirisini ve varlık türü dağılımını katılımcılar arasında anonim olarak göstermek (KVKK 5(1) — açık rıza; isteğe bağlı, uygulama içinde verilir)

---

## 5. Verilerin Paylaşıldığı Üçüncü Taraflar (Veri İşleyenler)

| Hizmet | Sağlayıcı | Veri | Amaç | Yer |
|---|---|---|---|---|
| Backend & veritabanı | Supabase Inc. | Tüm hesap ve uygulama verileri | Saklama, kimlik doğrulama | {SUPABASE_ULKE} |
| Push bildirimi | Google Firebase Cloud Messaging | Push token, bildirim içeriği | Bildirim teslimi | Küresel (Google) |
| Hata raporu (eklenirse) | Google Firebase Crashlytics | Cihaz modeli, OS, hata stack trace | Çökme teşhisi | Küresel |
| Hisse/fon fiyat bilgisi | Yahoo Finance, TEFAS, finans.truncgil.com | YOK — sadece sembol query'si gönderilir | Fiyat çekme | Küresel |

**Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder. Veri sorumlusu sıfatı tarafımızda kalır.**

### 5.1 Diğer Kullanıcılarla Anonim Paylaşım (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

---

## 6. Yurt Dışına Veri Aktarımı

Supabase veritabanı {SUPABASE_ULKEDE}, Firebase ABD'de barındırıldığı için verileriniz Türkiye dışına aktarılır. Uygulama içindeki metin, bağlı olduğunuz sunucunun ülkesini gösterir. KVKK Madde 9 ve GDPR Madde 44-49 uyarınca:

- **AB üyesi kullanıcılar için:** Standart Sözleşme Maddeleri (SCC) ve sağlayıcıların GDPR uyumluluk taahhütleri çerçevesinde aktarım yapılır.
- **Türk kullanıcılar için:** KVKK Madde 9(1) kapsamında **açık rıza** alınmaktadır. Açık rızanızı kayıt sırasında onayladığınız "Açık Rıza Metni" ile vermektesiniz.

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase: ABD), KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde olmadığından, yurt dışı aktarımı **açık rızanıza** dayanmaktadır.

---

## 7. Veri Saklama Süreleri

| Veri | Süre |
|---|---|
| Hesap verileri | Hesap silinene kadar |
| Varlık kayıtları | Hesap silinene kadar |
| Snapshot geçmişi | Son 365 gün rolling (eski kayıtlar otomatik silinir) |
| Zirve havuzu ölçümleri (getiri %, tür payı %) | Son 365 gün rolling; rıza geri alınınca ya da hesap silinince hemen |
| Yasal metin onay kayıtları (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı) | Hesap silindikten sonra **3 yıl** (TBK Madde 146 zamanaşımı) |
| Push token | Cihaz uygulamayı sildiğinde veya logout'ta otomatik silinir |
| Hata raporları | 90 gün |
| db_logs (yalnızca hatalar) | 30 gün |

Hesabınızı sildiğinizde, yukarıda özel saklama süresi belirtilenler hariç tüm verileriniz **30 gün içinde** kalıcı olarak silinir.

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
- **Erişim:** Row-Level Security (RLS) ile her kullanıcı yalnızca kendi verisine erişebilir
- **Şifre:** Bcrypt hash (Supabase Auth)
- **Oturum:** JWT, 1 saat erişim + 7 gün yenileme tokenı; uygulama içi 10 dakika boşta kalma timeout'u
- **Loglama:** Üretimde sadece hatalar; hassas alanlar (e-posta, şifre, token) maskelenir
- **Geliştirici erişimi:** Yalnızca destek talebi sırasında ve müşteri onayıyla

KVKK Madde 12 uyarınca veri ihlali tespiti halinde:
- En geç **72 saat** içinde KVK Kurulu'na bildirim
- Etkilenen kullanıcılara doğrudan bildirim
- AB kullanıcıları için GDPR Madde 33-34 uyumlu süreç

---

## 11. Tanımlama Bilgileri (Çerez ve Yerel Depolama)

Uygulama mobil ortamda çalıştığı için web çerezleri **kullanılmaz**. Yerel depolama (SharedPreferences, SQLite cache) yalnızca:

- Oturum tokenı (Supabase Auth)
- Tema/dil tercihi
- Kayıtlı e-posta (kullanıcı isterse)
- Disclaimer onay durumu (yerel kopya)

için kullanılır. Üçüncü taraf takip / analitik / reklam SDK'sı içermez.

---

## 12. Yatırım Tavsiyesi Reddi (Disclaimer)

**sandık** bir portföy takip aracıdır. SPK (Sermaye Piyasası Kurulu) lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. Uygulamada gösterilen fiyat, performans, sinyal ve grafikler bilgilendirme amaçlıdır ve yatırım tavsiyesi niteliği taşımaz. Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.

Bu disclaimer, ilk kullanım sırasında ayrıca onaylatılır ve onay kaydı yasal kanıt olarak saklanır.

---

## 13. Politikada Değişiklikler

Bu politikada değişiklik yaptığımızda:
- Uygulama içinde bildirim gösterilir
- "Son güncelleme" tarihi yenilenir
- Önemli değişikliklerde e-posta gönderilir
- Yeni KVKK aydınlatma metni gerektiren değişikliklerde tekrar onay istenir

30 gün içinde itiraz etmezseniz değişikliği kabul etmiş sayılırsınız.

---

## 14. İletişim

Veri korumayla ilgili tüm soru, talep ve şikayetler için:

- **E-posta:** `sandikapp.destek@gmail.com`
- **Adres:** `İstanbul, Türkiye`
- **Veri Koruma Sorumlusu (DPO):** Atanmamıştır. Veri koruma iletişimi: `sandikapp.destek@gmail.com`

---

*Bu politika [Türkçe] ve [İngilizce] dillerinde sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*''',
  'legal/tr/KVKK_AYDINLATMA_METNI.md': r'''# KVKK Aydınlatma Metni — sandık

**Yürürlük tarihi:** 4 Ekim 2026
**Son güncelleme:** 4 Ekim 2026
**Sürüm:** 1.2

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
- Görünen ad (display name)

### 2.2 İletişim Verisi
- Bildirim için kayıtlı cihaz token'ı (push)

### 2.3 Müşteri İşlem Verisi
- Portföy varlık kayıtları (sembol, miktar, alış fiyatı, tarih, not)
- Snapshot geçmişi (toplam değer, getiri yüzdesi)
- Dönemsel getiri yüzdesi, varlık türü payları ve fon kodu bazında paylar (Zirvedeki Portföyler anonim havuzu)
- Ortaklık bağlantıları ve davet kodları

### 2.4 İşlem Güvenliği Verisi
- Şifre (bcrypt hash — geri çevrilemez)
- Oturum tokenı (JWT)
- Cihaz IP adresi (oturum açma anında)
- Cihaz modeli, OS sürümü, uygulama sürümü

### 2.5 Hukuki İşlem Verisi
- Yasal metin onayları: onaylanan metin ve sürümü, onay zamanı, platform, uygulama sürümü, dil

---

## 3. Kişisel Verilerin İşlenme Amaçları

| Amaç | Veri kategorileri |
|---|---|
| Hesap oluşturma ve oturum yönetimi | 2.1, 2.4 |
| Portföy takibi (uygulamanın ana işlevi) | 2.3 |
| Zirvedeki Portföyler — anonim karşılaştırma | 2.3 |
| Performans grafiklerinin hesaplanması | 2.3 |
| Ortaklık özelliği (kullanıcılar arası paylaşım) | 2.1, 2.3 |
| Push bildirim gönderimi | 2.2 |
| Yasal yükümlülüklerin yerine getirilmesi (disclaimer onayı, mahkeme/savcılık talepleri) | 2.5, 2.4 |
| Hata teşhisi ve uygulama güvenliği | 2.4 |
| Kötüye kullanım, sahtekarlık ve siber saldırı tespiti | 2.4 |

---

## 4. Kişisel Verilerin Toplanma Yöntemi ve Hukuki Sebebi

### 4.1 Toplanma Yöntemi
- **Doğrudan kullanıcıdan:** Kayıt formu, varlık ekleme, profil ayarları
- **Otomatik:** Oturum açma anında IP/cihaz bilgisi, push token kaydı, hata logları

### 4.2 Hukuki Sebep (KVKK Madde 5 ve 6)

| Veri | Hukuki sebep |
|---|---|
| E-posta, şifre, display name | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası için zorunlu |
| Portföy verileri | KVKK 5(2)(c) — sözleşmenin ifası |
| Zirve havuzu ölçümleri (getiri %, tür payı %) | KVKK 5(1) — açık rıza (uygulama içinde, isteğe bağlı; her an geri alınabilir) |
| Push token | KVKK 5(1) — açık rıza |
| IP, cihaz bilgisi | KVKK 5(2)(f) — meşru menfaat (güvenlik) |
| Disclaimer onayı | KVKK 5(2)(a) — kanunlarda öngörülmesi (SPK) |
| Yurt dışı aktarımı (Supabase: {SUPABASE_ULKE}; Firebase: ABD) | KVKK 5(1) ve 9(1) — açık rıza |

---

## 5. Kişisel Verilerin Aktarıldığı Taraflar ve Aktarım Amacı

### 5.1 Yurt İçi Aktarım
Mevcut işleme faaliyetlerinde **yurt içi üçüncü taraf aktarımı yapılmamaktadır** (Şirket çalışanları ve Şirketin doğrudan denetimindeki teknik destek personeli hariç).

### 5.2 Yurt Dışı Aktarım

| Alıcı | Ülke | Veri | Amaç | Hukuki sebep |
|---|---|---|---|---|
| Supabase Inc. | {SUPABASE_ULKE} | Tüm hesap ve uygulama verileri | Veritabanı ve kimlik doğrulama altyapısı | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Cloud Messaging) | ABD / Küresel | Push token, bildirim içeriği | Bildirim teslimi | KVKK 9(1) — açık rıza |
| Google LLC (Firebase Crashlytics) - **eklendiğinde** | ABD / Küresel | Cihaz modeli, OS, hata stack trace | Çökme teşhisi | KVKK 5(2)(f) ve 9(1) — açık rıza |

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase: ABD), Kişisel Verileri Koruma Kurulu'nun (KVK Kurulu) ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmamaktadır**. Bu nedenle yurt dışı aktarımı KVKK Madde 9(1) kapsamında **açık rızanıza** dayanmaktadır.

Açık rızanız, kayıt sırasında onayladığınız "Açık Rıza Metni" içerisinde belirli, bilgilendirilmiş ve özgür iradeyle alınmaktadır.

### 5.3 Diğer Kullanıcılara Anonim Çıktı (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

---

## 6. Kişisel Verilerin Saklanma Süresi

| Veri | Saklama süresi | Dayanak |
|---|---|---|
| Hesap verileri (e-posta, display name) | Hesap silinene kadar | Sözleşme süresi |
| Portföy varlık kayıtları | Hesap silinene kadar | Sözleşme süresi |
| Snapshot geçmişi | Son 365 gün rolling | Servis ihtiyacı |
| Zirve havuzu ölçümleri | Son 365 gün rolling; rıza geri alınınca ya da hesap silinince hemen | Servis ihtiyacı |
| Push token | Logout veya uninstall'a kadar | Sözleşme süresi |
| Yasal metin onay kayıtları (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı) | Hesap silinmesinden sonra **3 yıl** | TBK Madde 146 (zamanaşımı) |
| Oturum logları (IP, cihaz) | 90 gün | KVKK 5(2)(f) meşru menfaat |
| Hata logları (error db_logs) | 30 gün | KVKK 5(2)(f) meşru menfaat |

Saklama süresi sona eren veriler **kalıcı olarak silinir veya anonimleştirilir**.

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

1. **Uygulama içi:** Profil → Ayarlar → "Hesabımı Sil" / "Verilerimi İndir"
2. **E-posta:** `sandikapp.destek@gmail.com` adresine kimlik bilgileri (ad-soyad, T.C. kimlik no veya başka kimlik tanımlayıcı), iletişim bilgileri ve talep konusunu açıkça belirten yazılı başvuru
3. **KEP:** `Yok (bireysel geliştirici)` adresine güvenli elektronik imzalı belge
4. **Posta:** `İstanbul, Türkiye` adresine ıslak imzalı dilekçe

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
- 10 dakika idle session timeout
- Production loglarında PII maskeleme

**İdari Önlemler:**
- Veri işleyenlerle (Supabase, Firebase) yazılı veri işleme sözleşmeleri (DPA)
- Personel için gizlilik taahhütleri
- Erişim yetkisi prensibi (least-privilege)
- Veri ihlali yönetimi süreci (72 saat içinde Kurul'a bildirim)
- Düzenli güvenlik denetimleri ve testler

---

## 9. Veri İhlali Durumunda Bildirim

KVKK Madde 12(5) uyarınca, kişisel verilerinizin yetkisiz kişilerce ele geçirildiğini tespit etmemiz hâlinde:

- En geç **72 saat** içinde KVK Kurulu'na bildirim yaparız
- Etkilenen veri sahiplerine (size) **makul en kısa sürede** doğrudan bildirim yaparız (e-posta + uygulama içi)
- KVK Kurulu'nun ilan ettiği "Veri İhlali Bildirim Formu"nu kullanırız

---

## 10. Politikada Değişiklikler

Bu Aydınlatma Metni'nde değişiklik yaptığımızda:
- Yeni sürüm uygulama içinde gösterilir
- "Sürüm" numarası artırılır
- Önemli değişikliklerde tekrar onay isteriz
- Önceki sürümlere `https://yasincirali.github.io/sandikapp/legal/kvkk-history` adresinden ulaşılabilir

---

*Bu Aydınlatma Metni'ni okuyup anladığınızı, kayıt sırasında ilgili onay kutusunu işaretleyerek beyan etmektesiniz.*

---

**`Yasin Çıralı`**
**`Türkiye`**
**`sandikapp.destek@gmail.com`**''',
  'legal/tr/ACIK_RIZA_METNI.md': r'''# Açık Rıza Metni — sandık

**Yürürlük tarihi:** 4 Ekim 2026
**Sürüm:** 1.2

> Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 5(1) ve 9(1) uyarınca **açık rızanızı** almak için hazırlanmıştır. Bu metni dikkatle okuyup, devamındaki onay kutularını bilinçli iradenizle işaretlemeniz beklenmektedir.

---

## 1. Açık Rıza Veriyorum

`Yasin Çıralı` ("Şirket") tarafından sunulan **sandık** mobil uygulamasını kullanmak amacıyla:

### A) Yurt Dışına Veri Aktarımı

KVKK Madde 9(1) uyarınca aşağıdaki kişisel verilerimin sunucuları **{SUPABASE_ULKEDE}** bulunan **Supabase Inc.** ve **Amerika Birleşik Devletleri'nde (ABD)** bulunan **Google LLC (Firebase)** servislerine aktarılmasına;

- E-posta adresim
- Görünen adım (display name)
- Şifremin hash hâli
- Portföy varlık kayıtlarım (sembol, miktar, alış fiyatı, tarih, not)
- Performans snapshot geçmişim
- Ortaklık bağlantı kayıtlarım
- Push bildirim token'ım
- Oturum açma anındaki IP adresim, cihaz modelim, OS sürümüm
- Disclaimer onayımın metadatası (zaman, sürüm, platform, IP)

amacıyla aktarılmasına; bu ülkelerin KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmadığını** bildiğimi beyan ederek **AÇIK RIZA VERİYORUM**.

☐ **Onaylıyorum** *(zorunlu — kayıt için gerekli)*

---

### B) Push Bildirim Servisi

Aşağıdaki bildirim türlerinin tarafıma gönderilmesi için cihaz bildirim token'ımın işlenmesine ve yukarıdaki Firebase servisi üzerinden iletilmesine **AÇIK RIZA VERİYORUM**:

- Ortaklık daveti bildirimleri
- Servis duyuruları (önemli güvenlik uyarıları, politika değişiklikleri)
- (Opsiyonel) Teknik analiz sinyal bildirimleri

☐ **Bildirimleri kabul ediyorum** *(opsiyonel — istediğiniz zaman uygulama ayarlarından geri alabilirsiniz)*

---

### C) (Opsiyonel — Eklenirse) Hata Raporu Toplama

Uygulamada teknik bir çökme yaşanması durumunda, çökme nedenini teşhis edebilmek için cihaz modeli, OS sürümü, uygulama sürümü ve hata stack trace bilgisinin **Firebase Crashlytics** üzerinden tarafımıza gönderilmesine **AÇIK RIZA VERİYORUM**.

Bu rapor **e-posta, parola, portföy değeri** gibi kişisel veri içermez; cihaz tanımlayıcı (anonymous device id) ve teknik hata bilgisi içerir.

☐ **Hata raporlarını paylaşmayı kabul ediyorum** *(opsiyonel)*

---

### D) (Opsiyonel — Eklenirse) Pazarlama İletişimi

Yeni özellik duyuruları, kampanyalar ve kullanım ipuçlarının e-posta adresime gönderilmesine **AÇIK RIZA VERİYORUM**.

☐ **E-posta pazarlamasını kabul ediyorum** *(opsiyonel — her e-postada "abonelikten çık" linki bulunur)*

---

### E) Zirvedeki Portföyler (uygulama içinde ayrıca istenir)

Bu rıza kayıt sırasında DEĞİL, Zirvedeki Portföyler ekranını ilk açtığımda ayrı bir kartla istenir. Dönemsel getiri yüzdemin, varlık türü paylarımın ve fonlarda TEFAS fon kodu ile portföy içindeki payının anonim bir karşılaştırma havuzunda işlenmesine ve havuza katılan diğer kullanıcılara kimliğim, tutarlarım ve miktarlarım olmadan gösterilmesine; karşılığında katılımcıların aynı anonim bilgilerini görmeye **AÇIK RIZA VERİYORUM** (ayrıntı: Gizlilik Politikası §5.1, KVKK Aydınlatma Metni §5.3). Rıza vermezsem getirim bu amaçla hesaplanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanın verildiği tarih ve gösterilen metnin sürümü ispat için kaydedilir.

☐ **Zirvedeki Portföyler'e katılıyorum** *(opsiyonel — ekrandaki "Katılıyorum" düğmesiyle verilir)*

---

## 2. Açık Rızamın Geri Alınması

Vermiş olduğum açık rızayı, KVKK Madde 7 ve 11 uyarınca **istediğim zaman geri alabileceğimi** biliyorum:

- **Push bildirimi rızası:** Uygulama → Profil → Ayarlar → Bildirimler → Kapat
- **Hata raporu rızası:** Uygulama → Profil → Ayarlar → Hata raporları → Kapat
- **Pazarlama rızası:** Her e-postanın altındaki "abonelikten çık" linki veya Profil → Ayarlar → İletişim tercihi
- **Zirvedeki Portföyler rızası:** Performans → Zirvedeki Portföyler → "Zirvedeki Portföyler'den ayrıl" (havuzdaki ölçümler anında silinir)
- **Yurt dışı aktarım rızası:** Açık rızamın geri çekilmesi, hizmetin sunulamaması anlamına gelir; bu durumda hesabımı silmem gerekir (Profil → Ayarlar → Hesabımı Sil).

Rızamı geri çektiğim tarihten önceki işleme faaliyetleri hukuka uygun sayılmaya devam eder.

---

## 3. Açık Rızanın Geri Alınmasının Sonuçları

| Geri çekilen rıza | Sonuç |
|---|---|
| Yurt dışı aktarım (A) | Hizmet sunulamaz, hesap silinir |
| Push bildirimi (B) | Bildirim alamazsınız; ortaklık davetlerini uygulama içinden manuel kontrol edersiniz |
| Hata raporu (C) | Çökme yaşadığınızda otomatik teşhis yapamayız; destek talebine yanıt süremiz uzar |
| Pazarlama (D) | Promosyon e-postası alamazsınız; servis e-postaları (güvenlik, fatura) gönderilmeye devam eder |

---

## 4. Beyan

- Bu Açık Rıza Metni'ni okuduğumu,
- Kişisel verilerimin nasıl işleneceğini, hangi amaçlarla kullanılacağını, kimlere aktarılacağını ve haklarımı **KVKK Aydınlatma Metni**'nden ayrıntılı olarak öğrendiğimi,
- Verdiğim açık rızanın **özgür iradem ile, belirli ve bilgilendirilmiş** şekilde verildiğini,
- 18 yaşından büyük olduğumu ve bu rızayı verme ehliyetinin bulunduğunu

beyan ve kabul ederim.

---

**Tarih:** [Onay anında otomatik kaydedilir]
**Sürüm:** 1.2
**IP:** [Onay anında otomatik kaydedilir]
**Platform:** [Android / iOS — otomatik kaydedilir]

---

*Açık rıza onayınız, KVKK Madde 12 uyarınca hesabınız silinene kadar Şirket tarafından kanıt olarak saklanır. Sildiğiniz hesabın açık rıza kayıtları, TBK Madde 146 zamanaşımı süresi olan **3 yıl** boyunca saklanır.*''',
};
