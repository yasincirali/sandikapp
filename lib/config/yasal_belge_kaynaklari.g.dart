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

**Yürürlük tarihi:** 8 Ekim 2026
**Son güncelleme:** 8 Ekim 2026
**Sürüm:** 1.6
**Onay sürümü:** 1.6

---

## 1. Taraflar ve Kabul

Bu Kullanım Koşulları ("Koşullar"), `Yasin Çıralı` ("Şirket", "biz") tarafından sunulan **sandık** mobil uygulaması ("Uygulama", "Hizmet") ile uygulamayı kullanan gerçek kişi ("Kullanıcı", "siz") arasındaki sözleşmedir.

Hesap oluştururken bu Koşulları kabul edersiniz. **Gizlilik Politikası** ve **KVKK Aydınlatma Metni** kişisel verilerinizin nasıl işlendiğini anlatan bilgilendirme belgeleridir; kabulünüze bağlı değildir. Yurt dışına veri aktarımı için açık rızanız bu Koşulların kabulünden ayrıdır ve yalnız **Açık Rıza Metni** ile alınır.

Kayıt sırasında (Apple veya Google ile ilk girişte açılan onay ekranında da):
- Kullanım Koşulları, Gizlilik Politikası ve KVKK Aydınlatma Metni bağlantı olarak sunulur; dokunduğunuzda tam metni açılır. Bu Koşulları tek bir onay kutusunu işaretleyerek kabul edersiniz; aynı kutuyla 18 yaşından büyük olduğunuzu beyan eder, Gizlilik Politikası ve KVKK Aydınlatma Metni ile bilgilendirildiğinizi belirtirsiniz. Onay kutusu açık rıza içermez.
- Açık Rıza Metni size tam metniyle gösterilir; sonuna kadar okuduktan sonra açık rızanızı metnin sonundaki düğmeyle verirsiniz.
- Yatırım uyarısı (§3) tam metniyle gösterilir; sonuna kadar okuduktan sonra en altta onaylarsınız.

---

## 2. Hizmetin Tanımı

sandık, kullanıcıların aşağıdaki varlık türlerini takip edebileceği bir kişisel portföy izleme aracıdır:

- Hisse senetleri (Borsa İstanbul ve yurt dışı borsalar)
- Tahviller (eurobond)
- TEFAS yatırım fonları
- Döviz (USD, EUR, GBP, vb.)
- Altın ve diğer emtialar
- Kripto paralar
- Vadeli mevduat ve bireysel emeklilik (BES) sözleşmeleri
- Elle tanımladığınız diğer varlıklar

Uygulama; portföy değerini, dağılımını, performansını ve isteğe bağlı olarak teknik analiz sinyallerini, fiyat alarmlarını ve dönemsel özetleri gösterir. Varlıklarınızı elle, toplu olarak ya da banka/aracı kurum ekstresinden içe aktararak girebilirsiniz. Çoklu kullanıcı ortaklığı özelliğiyle iki kullanıcı portföylerini paylaşabilir.

**Zirvedeki Portföyler (isteğe bağlı):** Uygulama içinde açık rıza verirseniz dönemsel getiriniz ve varlık türü paylarınız anonim bir karşılaştırma havuzunda değerlendirilir (portföy 5 günden eski, en az 2 farklı varlık); en çok kazanan portföylerin yalnızca sırası, getirisi, tür payları ve fonların TEFAS kodu ile payları, kimlik ve tutar olmadan diğer katılımcılara gösterilir; karşılığında siz de katılımcıların aynı anonim bilgilerini görürsünüz (ayrıntı: Gizlilik Politikası §5.1). İstediğiniz an ayrılabilirsiniz; katılmamak başka hiçbir özelliği etkilemez.

**Yarış (isteğe bağlı):** Yarış'a katılırsanız dönemsel getiriniz ve varlık türü paylarınız günlük olarak sunucuda hesaplanır; katılımcılar arasındaki yeriniz size yüzdelik dilim olarak gösterilir, ortağınızla getirinizi karşılaştırabilirsiniz. Diğer katılımcılara kimliğiniz ve tutarlarınız gösterilmez. Yarış'tan istediğiniz an ayrılabilirsiniz.

**Piyasa hareketi ve varlık notları:** Uygulama, kamuya açık piyasa verisinden fonlara giren ve çıkan parayı (para akışı), hisselerde olağandışı işlem hacmini (hacim radarı) ve kriptoda alıcı baskısını gösterir. Portföyündeki varlıklar için haftalık varlık notları ve aylık rapor, yapay zekâ ile otomatik hazırlanır (ayrıntı: Gizlilik Politikası §5.3). Notların tamamı ve aylık rapor Premium üyelere açık olabilir; ücretsiz katmanda notun ilk cümlesi gösterilir.

---

## 2A. Premium Abonelik

Bu bölüm, Premium uygulamada satışa sunulduğunda geçerlidir.

**Kapsam.** Portföy takibi ücretsizdir. Premium, ücretsiz katmanda sınırlı olan ya da yalnızca abonelere açık olan özellikleri (ör. ek teknik göstergeler, varlık notlarının ve aylık raporun tamamı, ekstrenin yapay zekâyla okunması) içerir. Hangi özelliğin Premium olduğu satın alma ekranında, satın almadan önce gösterilir. Ücretsiz katmanda Premium özelliklerin bir kısmı sınırlı biçimde görünebilir (ör. notun ilk cümlesi).

**Fiyat ve ödeme.** Abonelik aylık ya da yıllık dönemlidir. Fiyat, satın alma ekranında App Store ya da Google Play'in gösterdiği tutardır (vergiler dahil). Ödemeyi Şirket değil, cihazınızın mağazası (Apple ya da Google) tahsil eder; kart bilgileriniz Şirket'e ulaşmaz.

**Otomatik yenileme.** Abonelik, dönem bitmeden iptal edilmezse (Apple'da dönem bitmeden en az 24 saat önce) aynı süre ve o anki fiyatla kendiliğinden yenilenir. Fiyat artarsa mağaza sizi önceden bilgilendirir ve gerekirse onayınızı ister.

**Ücretsiz deneme.** Mağazada deneme tanımlıysa süresi satın alma ekranında yazar; tanımlı değilse deneme vaat edilmez. Deneme bitmeden iptal etmezseniz deneme sonunda ilk dönem ücreti alınır. Deneme hakkı mağazanın kurallarına göre hesap başına bir kez kullanılabilir.

**İptal.** Aboneliği istediğiniz zaman mağazadan iptal edebilirsiniz (iPhone: Ayarlar › Apple Kimliği › Abonelikler; Android: Google Play › Ödemeler ve abonelikler › Abonelikler). İptal, ödenmiş dönemin sonunda geçerli olur; Premium o güne kadar açık kalır. Uygulamayı silmek ya da hesabınızı silmek aboneliği iptal **etmez**; önce mağazadan iptal edin.

**İade ve cayma hakkı.** İade talepleri mağazanın kendi süreciyle değerlendirilir (Apple: reportaproblem.apple.com; Google: Google Play'deki sipariş geçmişi). Mesafeli Sözleşmeler Yönetmeliği Madde 15(1)(ğ) uyarınca, elektronik ortamda anında ifa edilen hizmetlerde ve tüketiciye anında teslim edilen gayrimaddi mallarda, ifaya onayınızla başlandığında cayma hakkı kullanılamaz; satın alma ekranında aboneliği başlatmanız bu onay sayılır. TKHK'dan doğan devredilemez haklarınız saklıdır (bkz. Madde 12).

**Hakkın tanınması.** Satın alma tamamlandığında mağaza işlemi abonelik altyapı sağlayıcımız RevenueCat üzerinden doğrulanır ve Premium hesabınıza bağlanır. Aynı hesapla girdiğiniz başka cihazda da açılır; cihaz değiştirdiyseniz satın alma ekranındaki "Satın alımı geri yükle" ile yeniden bağlayabilirsiniz.

**Hediye Premium.** Şirket, belirli kullanıcılara (ör. belirli bir tarihten önce kayıt olanlara) bir defaya mahsus, ücretsiz ve otomatik yenilenmeyen süreli Premium tanıyabilir. Süre bitince ödeme alınmaz; Premium kendiliğinden kapanır.

**Değişiklik.** Premium kapsamı değişirse içinde bulunulan dönem için ödediğiniz özellikler dönem sonuna kadar korunur. Fiyat değişikliği yalnızca sonraki dönemlere uygulanır.

---

## 3. ÖNEMLİ UYARI — Yatırım Tavsiyesi Reddi

**sandık BİR YATIRIM DANIŞMANI, ARACI KURUM VEYA PORTFÖY YÖNETİM ŞİRKETİ DEĞİLDİR.**

- Şirket, Sermaye Piyasası Kurulu (SPK) tarafından lisanslı bir kurum değildir.
- Uygulamada gösterilen fiyatlar, performans rakamları, sinyal ve grafikler **yalnızca bilgilendirme** amaçlıdır.
- Hiçbir içerik **yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık** niteliği taşımaz.
- Piyasa hareketi ölçümleri (para akışı, hacim radarı, alıcı baskısı) ve **yapay zekâ ile hazırlanan varlık notları** geçmiş piyasa verisini anlatır, geleceği öngörmez. Notlar otomatik üretilir ve bir insan tarafından tek tek kontrol edilmez; sayılar kaynak veriyle otomatik karşılaştırılsa da hata içerebilir. Bir notu yatırım kararının tek dayanağı yapmayınız.
- Verilerin doğruluğu, güncelliği ve eksiksizliği için garanti vermiyoruz; üçüncü taraf piyasa verisi sağlayıcılarının verileri olduğu gibi sunulur.
- Yatırım kararlarınızı **SPK lisanslı bir aracı kurum veya yatırım danışmanına danışarak** veriniz.
- Uygulamada görüntülenen verilere dayanarak verdiğiniz yatırım kararlarından doğan **hiçbir kâr/zarardan Şirket sorumlu tutulamaz**.

Bu uyarının tam metni kayıt sırasında (Apple veya Google ile ilk girişte açılan onay ekranında da) size gösterilir; metni sonuna kadar okuduktan sonra en altta onaylarsınız. Onayın kaydı yasal kanıt olarak saklanır.

---

## 4. Hesap

### 4.1 Hesap Açma
- 18 yaşından büyük olmalısınız.
- Geçerli bir e-posta adresi sağlamalı ya da Apple veya Google hesabınızla giriş yapmalısınız.
- Benzersiz bir kullanıcı adı seçmelisiniz; kullanıcı adınız ortağınıza ve bildirimlerde görünür, uygunsuz ifade içeremez.
- Doğru ve güncel bilgi vermelisiniz.

### 4.2 Hesap Güvenliği
- Şifrenizi kimseyle paylaşmayın.
- Şifrenizin güvenliğinden siz sorumlusunuz.
- Hesabınız aynı anda yalnızca bir cihazda açık kalır. Yeni bir cihazda giriş yaptığınızda e-posta adresinize gelen kod istenir ve önceki cihazdaki oturum kapanır. Kayıtlı cihazlarınızı Ayarlar'dan görebilir ve silebilirsiniz.
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

Uygulama; Supabase (sunucu, veritabanı ve kimlik doğrulama), Google Firebase (bildirim, hata raporu, kullanım istatistiği, uzaktan ayar), Apple (iOS bildirimleri ve kilit ekranı canlı etkinliği), Apple ile Giriş ve Google ile Giriş (seçerseniz), Google'ın e-posta altyapısı (doğrulama kodları), Anthropic (varlık notlarının yapay zekâ ile yazımı; kişisel veri gönderilmez), RevenueCat (Premium abonelik doğrulaması), App Store ve Google Play (Premium ödemesi) ve kamuya açık piyasa verisi sağlayıcıları (borsalar, bankalar, fon platformları, resmî kurumlar ile kur ve fiyat veri servisleri) gibi üçüncü taraf servisleri kullanır. Bu servislerin kesintileri, gecikmeleri veya hataları nedeniyle oluşacak sorunlardan **Şirket sorumlu değildir**.

Piyasa verisi kaynaklarının sağladığı bilgiler dahil olmak üzere üçüncü taraf veri sağlayıcılarının kendi kullanım koşulları geçerlidir. Veri çekiminin geçici olarak engellenmesi durumunda, alternatif kaynaklar veya manuel veri girişi seçenekleri sunulabilir.

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
- İstediğiniz zaman hesabınızı silebilirsiniz (Profil → Ayarlar → Hesabımı Sil). Uygulamadan yapılan silme anında gerçekleşir: hesabınız ve girdiğiniz veriler canlı veritabanından hemen silinir; yasal saklama süresi olan kayıtlar istisnadır (bkz. Gizlilik Politikası §7).
- E-postayla iletilen silme talepleri 30 gün içinde işleme alınır.
- Verilerinizin bir kopyasını istediğiniz zaman alabilirsiniz (Profil → Ayarlar → Verilerimi İndir, JSON dosyası).

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
- **Yetkili mahkeme:** Bu Koşullardan doğan uyuşmazlıklarda Türkiye Cumhuriyeti mahkemeleri ve icra daireleri yetkilidir.

Tüketici işlemlerinde 6502 sayılı Tüketicinin Korunması Hakkında Kanun uyarınca, parasal sınırlar dahilinde tüketicinin yerleşim yerindeki tüketici hakem heyetleri, bu sınırların üzerinde tüketicinin yerleşim yerindeki tüketici mahkemeleri yetkilidir.

AB üyesi tüketiciler için Roma I Tüzüğü uyarınca yerleşim yeri ülkesinin zorunlu tüketici koruma hükümleri saklıdır.

---

## 18. Koşullarda Değişiklik

Bu Koşulları ve diğer yasal belgeleri değiştirdiğimizde:
- Yeni metin yeni bir sürüm numarasıyla yayımlanır; web sitesindeki ve uygulamadaki metin her zaman aynıdır.
- Esaslı değişiklikler ("Onay sürümü" de yeni sürüme çekilir) uygulama içinde bildirilir: bir sonraki açılışta güncel belgeler ve değişikliklerin özeti gösterilir. Kullanım Koşulları için kabulünüz onay kutusuyla, Açık Rıza Metni için rızanız metnin sonunda yeniden istenir; Gizlilik Politikası ve KVKK Aydınlatma Metni'nin güncel hâliyle bilgilendirildiğinizi aynı kutuda belirtirsiniz.
- Hak ve yükümlülüklerinizi ya da kişisel veri işleyişini değiştirmeyen düzeltmelerde yalnızca "Sürüm" değişir; yeniden onay istenmez.
- Esaslı bir değişikliği onaylamadan uygulamayı kullanmaya devam edemezsiniz; değişikliği kabul etmiyorsanız hesabınızı silebilirsiniz (Profil → Ayarlar → Hesabımı Sil).
- Hangi sürümü ne zaman kabul ettiğiniz ya da hangi sürümün size ne zaman sunulduğu kayıt altında tutulur.

---

## 19. İletişim

`Yasin Çıralı`
`İstanbul, Türkiye`
E-posta: `sandikapp.destek@gmail.com`
Web: `https://yasincirali.github.io/sandikapp`

---

*Bu Koşullar Türkçe ve İngilizce olarak sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*''',
  'legal/tr/PRIVACY_POLICY.md': r'''# Gizlilik Politikası — sandık

**Yürürlük tarihi:** 8 Ekim 2026
**Son güncelleme:** 8 Ekim 2026
**Sürüm:** 1.8
**Onay sürümü:** 1.8

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
| Varlık notlarına geri bildiriminiz (isteğe bağlı): notun varlığı ve dönemi, "işe yaradı / yaramadı" oyu, "yanlış sayı var" işareti, en fazla 500 karakterlik açıklama | Notların kalitesini ölçmek, hatalı notları bulup düzeltmek (bkz. §5.3) |
| Premium hakkı: kaynağı (hediye, mağaza aboneliği ya da destek), başlangıç ve bitiş zamanı, mağaza ve ürün adı, yenilemenin kapatılıp kapatılmadığı | Premium içeriğe erişimin sunucuda doğrulanması. Ödeme ve kart bilgisi bize ulaşmaz; tahsilatı Apple ya da Google yapar |

**Ekstre içe aktarma:** İçe aktardığınız banka veya aracı kurum ekstresi (PDF, Excel, CSV) yalnızca cihazınızda okunur; dosya sunucuya gönderilmez ve saklanmaz. Yalnızca sizin onayladığınız varlık kayıtları kaydedilir. Uygulama ekstrenin sütunlarından emin olamazsa ve siz "Yapay zekâyla eşle"ye basarsanız, tablonun anonim iskeleti (bkz. §5.4) sunucumuz üzerinden yapay zekâya gönderilir; dosyanın kendisi yine gönderilmez.

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
| Yasal metin onay ve bilgilendirme kayıtları: kabul edilen ya da size sunulan metin ve sürümü, zamanı, alındığı ekran, platform, uygulama sürümü, dil, size gösterilen sunucu ülkesi, belgeyi açıp açmadığınız ve metnin sonuna kadar okunup okunmadığı; yatırım uyarısında ayrıca cihaz modeli | Hangi metni hangi sürümüyle ne zaman kabul ettiğinizin ya da size sunulduğunun kanıtı | KVKK 5(2)(e) — bir hakkın tesisi, kullanılması veya korunması; yatırım uyarısı için KVKK 5(2)(a) |

Gizlilik Politikası ve KVKK Aydınlatma Metni bilgilendirme amaçlıdır ve kabulünüze bağlı değildir: kayıtta ve onay ekranında bağlantı olarak sunulur; kayıt, metnin size sunulduğunu ve onay kutusunda bilgilendirildiğinizi belirttiğinizi gösterir.

### 3.5 Otomatik Toplanan Veriler
| Veri | Amaç |
|---|---|
| Hata raporları (Firebase Crashlytics): çökme ve hata kaydı, cihaz modeli, OS ve uygulama sürümü, Crashlytics'in rastgele kurulum kimliği | Çökme teşhisi; e-posta, ad ve portföy değeri gönderilmez |
| Kullanım istatistikleri (Firebase Analytics): hesap numaranız (rastgele kullanıcı kimliği), görüntülenen ekranlar, özellik kullanım olayları (ör. varlık ekleme ve türü, bildirim açma, sinyal görüntüleme ve sembolü), kaba aralıklar (ör. varlık sayısı aralığı), cihaz ve uygulama bilgisi, Google'ın IP adresinden çıkardığı yaklaşık konum (ülke/şehir) | Ürünün nasıl kullanıldığını anlamak ve iyileştirmek; tutar, miktar ve e-posta gönderilmez, reklam kimliği toplanmaz |
| Uzaktan ayarlar (Firebase Remote Config): Firebase'in rastgele kurulum kimliği | Özelliklerin uzaktan açılıp kapatılması |
| Kurulum adımları (kayıt hunisi): uygulamanın ürettiği rastgele kurulum numarası, adım (ilk açılış, kayıt ekranı, kod doğrulama vb.), platform, uygulama sürümü, kayıt hatasının kodu; giriş yapınca hesabınıza bağlanır | Kayıt sürecindeki sorunların tespiti |
| Yapısal hata kayıtları | Yalnızca **hata** durumunda; istek bilgisi ve hata mesajı, hassas alanlar (e-posta, şifre, token, IP) maskelenerek |

### 3.6 Abonelik Verileri (yalnızca Premium satın alırsanız)
| Veri | Amaç | Hukuki dayanak |
|---|---|---|
| Hesap numaranız (rastgele kullanıcı kimliği), mağaza işlem kaydı, ürün (aylık ya da yıllık), mağaza (App Store ya da Google Play), başlangıç ve bitiş tarihleri, iptal durumu, test satın alımı olup olmadığı | Satın almayı mağazayla doğrulamak, Premium'u hesabınıza bağlamak, yenileme, iptal ve iadeyi uygulamak | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası |

Kart numarası, fatura adresi ve ödeme yöntemi bize **ulaşmaz**: ödemeyi cihazınızın mağazası (Apple ya da Google) tahsil eder ve bu bilgileri kendi gizlilik politikasıyla işler.

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
11. Premium: satın aldığınız aboneliği doğrulamak ve Premium içeriğe erişim hakkınızı tanımak
12. Varlık notlarına verdiğiniz geri bildirimle notların doğruluğunu ölçmek ve iyileştirmek

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
| Abonelik doğrulama (yalnızca Premium satın alırsanız) | RevenueCat, Inc. | Hesap numaranız (rastgele kullanıcı kimliği), mağaza işlem kaydı ve makbuzu, cihaz ve uygulama sürümü, IP adresi | Satın almayı mağazayla doğrulamak ve Premium hakkını sunucumuza bildirmek (bkz. §3.6) | ABD |
| Fiyat ve piyasa verisi | Kamuya açık piyasa verisi sağlayıcıları: borsalar, bankalar, fon platformları, resmî kurumlar (ör. TCMB) ile kur ve fiyat veri servisleri | Kişisel veri gönderilmez; yalnızca varlığın sembolü, fon kodu ya da ISIN'i sorulur. Cihazdan giden isteklerde sağlayıcı, her internet isteğinde olduğu gibi cihazın IP adresini görür; bazı kaynaklara istekler yalnızca sunucumuzdan gider | Fiyat ve fiyat geçmişi çekme | Küresel |
| Varlık notlarının yazımı (yapay zekâ) | Anthropic PBC | Kişisel veri gönderilmez; yalnızca varlığın sembolü ve piyasa ölçümleri (fiyat, işlem hacmi, fon büyüklüğü, para akışı ve yatırımcı sayısı) | Haftalık varlık notu ve aylık rapor metni (bkz. §5.3) | ABD |
| Ekstre sütun eşleme (yapay zekâ; yalnızca siz isterseniz) | Anthropic PBC | Ekstredeki tabloların anonim iskeleti: sütun başlıkları ve genel finans kelimeleri; ad, numara, tutar ve tarihler maskeli | Hangi sütunun sembol, adet, fiyat olduğunu bulmak (bkz. §5.4) | ABD |

**Bu sağlayıcılar yalnızca veri işleyen (data processor) sıfatıyla, talimatlarımız doğrultusunda hareket eder. Veri sorumlusu sıfatı tarafımızda kalır.** Premium ödemesini tahsil eden Apple ve Google, ödeme bilgileriniz için kendi başına veri sorumlusudur.

Piyasa verisi sağlayıcıları kişisel veri almadığı için tek tek sayılmaz; yeni bir fiyat kaynağı eklemek bu politikayı değiştirmez. Kişisel veri alan yeni bir sağlayıcı ise ancak bu tabloya eklenerek kullanılır.

### 5.1 Diğer Kullanıcılarla Anonim Paylaşım (Zirvedeki Portföyler)

Zirvedeki Portföyler isteğe bağlıdır ve yalnızca uygulama içinde açık rıza veren kullanıcıları kapsar. Rıza verdiğinizde, portföyünüz 5 günden, hesabınız 7 günden eskiyse ve portföyünüzde en az 2 farklı varlık bulunuyorsa dönemsel getiriniz (haftalık, aylık, altı aylık, yıllık) ve varlık türü paylarınız (ör. "altın %56, fon %28") günde iki kez sunucuda hesaplanır ve anonim bir karşılaştırma havuzunda tutulur. Havuzda en az 8 portföy varsa, en çok kazanan en fazla 4 portföyün yalnızca sırası, getiri yüzdesi, tür payları ve fon türündeki yatırımların kamuya açık TEFAS fon kodu ile portföy içindeki payı (payı %1'in altındaki ya da kodsuz fonlar toplu olarak) havuza katılan diğer kullanıcılara gösterilir; fon adları resmi TEFAS listesinden gelir. Karşılığında siz de katılan kullanıcıların hangi varlık türlerini hangi oranlarda tuttuğunu ve getirilerini aynı anonim biçimde görürsünüz; bu karşılaştırma hizmeti yalnızca katılanlara açıktır. Ad, e-posta, kullanıcı adı, tutar, miktar, hisse ve diğer varlıkların adı veya sembolü ile varlıklarınıza verdiğiniz ad ve notlar hiçbir koşulda paylaşılmaz; gösterilen bilgi kimliğinizi ortaya koyacak bir veri içermez. Rıza vermezseniz getiriniz bu amaçla hesaplanmaz ve saklanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanızı istediğiniz an Zirvedeki Portföyler ekranından geri alabilirsiniz; geri aldığınızda havuzdaki ölçümleriniz anında silinir. Rızanın verildiği tarih ve size gösterilen metnin sürümü, rızanın ispatı için kayıt altında tutulur. Hesabınızı sildiğinizde bu kayıtlar ve havuzdaki ölçümleriniz de silinir.

### 5.2 Ortağınızla ve Yarış'ta Paylaşım

Ortaklık kurduğunuz kullanıcı, kullanıcı adınızı, portföyünüzdeki varlıkları, miktarları ve performansı görür. Yarış'ta diğer katılımcılara kimliğiniz ve tutarlarınız gösterilmez; size yalnızca kendi yüzdelik diliminiz gösterilir, ortağınızla getirilerinizi karşılaştırabilirsiniz.

### 5.3 Yapay Zekâ ile Hazırlanan Varlık Notları

Varlık sayfalarındaki haftalık varlık notları ve aylık rapor, sunucumuzda Anthropic'in yapay zekâ modeli (Claude) ile yazılır. Not kullanıcı başına değil **varlık başına** bir kez yazılır: aynı varlığı tutan herkes aynı notu okur. Notunuzu açtığınızda ya da okuduğunuzda yapay zekâya bir istek gitmez; not veritabanından okunur.

Modele yalnızca varlığın sembolü ve kamuya açık piyasa ölçümleri gönderilir (fiyat değişimi, işlem hacmi, fon büyüklüğü, para akışı ve yatırımcı sayısı). Adınız, e-postanız, hesap numaranız, kullanıcı adınız, tuttuğunuz miktar ve tutar ya da bir varlığı kimlerin tuttuğu gönderilmez. Hangi varlıklara not yazılacağı, kullanıcıların portföylerinde tutulan varlıkların toplu listesinden (en çok tutulandan başlayarak) seçilir; bu seçim de modele gitmez.

Notlar otomatik üretilir ve yayımlanmadan önce otomatik olarak denetlenir: metindeki her sayı kaynak veriyle karşılaştırılır, al/sat/hedef fiyat dili içeren not yayımlanmaz. Notları bir insan tek tek okumaz; hata içerebilirler. Bir notta "yanlış sayı var" işaretlerseniz ya da açıklama yazarsanız bu geri bildirim hesabınızla birlikte saklanır ve yalnızca notların düzeltilmesi için kullanılır; başka kullanıcılara gösterilmez.

### 5.4 Ekstre Sütunlarının Yapay Zekâ ile Eşlenmesi

Ekstre dosyası her zaman cihazınızda okunur. Uygulama, tanımadığı bir düzende hangi sütunun sembol, adet ya da fiyat olduğundan emin olamazsa size "Yapay zekâyla eşle" seçeneğini gösterir. Bu seçeneğe **siz basmadıkça** hiçbir şey gönderilmez. Bu seçenek Premium içeriktir.

Basarsanız cihazınız tablonun anonim bir iskeletini çıkarır ve sunucumuz üzerinden Anthropic'in yapay zekâ modeline (Claude) gönderir. İskelette tablonun düzeni, sütun başlıkları ve genel finans kelimeleri ("Pay Adedi", "Birim Fiyat", "PORTFÖY") bulunur; ad, müşteri ve hesap numarası, T.C. kimlik numarası, adres, tutar ve tarihler maskelenir (her harf "A", her rakam "9" olur). Sunucumuz maskelenmemiş rakam içeren bir iskeleti modele göndermeden reddeder. Model yalnızca hangi sütunun ne olduğunu söyler; değerler yine cihazınızda dosyadan okunur ve eklemeden önce size gösterilir.

İskelet ve modelin yanıtı saklanmaz. Kötüye kullanımı ve maliyeti sınırlamak için yalnızca isteğin zamanı, kullanılan model ve maliyeti hesabınızla birlikte 40 gün tutulur.

---

## 6. Yurt Dışına Veri Aktarımı

Supabase veritabanı {SUPABASE_ULKEDE}, Firebase ABD'de barındırıldığı için verileriniz Türkiye dışına aktarılır. Uygulama içindeki metin, bağlı olduğunuz sunucunun ülkesini gösterir. Apple ve Google'ın bildirim, giriş, e-posta ve mağaza ödeme hizmetleri de küresel altyapıda çalışır. Premium satın alırsanız abonelik kaydınız RevenueCat (ABD) üzerinden doğrulanır. KVKK Madde 9 ve GDPR Madde 44-49 uyarınca:

- **AB üyesi kullanıcılar için:** Standart Sözleşme Maddeleri (SCC) ve sağlayıcıların GDPR uyumluluk taahhütleri çerçevesinde aktarım yapılır.
- **Türk kullanıcılar için:** KVKK Madde 9(1) kapsamında **açık rıza** alınmaktadır. Açık rızanızı, kayıt sırasında (Apple veya Google ile ilk girişte onay ekranında) sonuna kadar okuyup metnin sonunda onayladığınız "Açık Rıza Metni" ile verirsiniz; bu rıza başka bir beyanla birlikte alınmaz.

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase ve RevenueCat: ABD), KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde olmadığından, yurt dışı aktarımı **açık rızanıza** dayanmaktadır.

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
| Varlık notlarına geri bildirimler | Hesap silinene kadar |
| Premium hakkı ve abonelik kayıtları | Hesap silinene kadar; hesabı silince hemen. RevenueCat'teki işlem kaydı RevenueCat'in saklama süresince, ödeme ve fatura kayıtları Apple ya da Google'da kendi sürelerince kalır |
| Ekstre sütun eşleme istek kayıtları (yalnızca zaman, model ve maliyet; iskelet ve yanıt saklanmaz) | 40 gün |
| Yasal metin onay kayıtları (Kullanım Koşulları, Gizlilik Politikası, KVKK Aydınlatma Metni, Açık Rıza Metni, yatırım uyarısı) | Hesap silindikten sonra **3 yıl** (TBK Madde 146 zamanaşımı) |
| Push token | Çıkış yapıldığında silinir; uygulama silinirse bir sonraki gönderimde geçersiz bulunup silinir |
| Bildirim kayıtları (uygulama içi bildirimler, fiyat alarmı bildirimleri) | 90 gün |
| Sinyal bildirimleri | Siz silene ya da hesap silinene kadar |
| Bildirim gönderim günlükleri (aynı bildirimin tekrar gönderilmemesi için) | Türüne göre 30 gün ile 18 ay arası |
| Yapısal hata kayıtları (db_logs, yalnızca hatalar) | 30 gün |
| Kayıt hunisi adımları | 400 gün |
| Hata raporları (Crashlytics) | 90 gün |
| Kullanım istatistikleri (Firebase Analytics) | Firebase'deki saklama ayarı kadar, en fazla 14 ay |
| Anonim hesap silme kaydı (hesap kimliğinin tek yönlü özeti, e-posta alan adı, silme zamanı ve nedeni) | Silmeden sonra **3 yıl** (TBK Madde 146 zamanaşımı); süresi dolanlar her gün otomatik silinir |
| Oturum açma güvenlik kaydı (IP, cihaz/tarayıcı; Supabase Auth güvenlik kaydı) | 90 gün; eskileri her gün otomatik silinir |

Hesabınızı uygulamadan sildiğinizde hesabınız ve girdiğiniz bütün veriler canlı veritabanından **hemen** silinir. İstisnalar: yasal metin onay kayıtları (3 yıl), yapısal hata kayıtları ve kayıt hunisi adımları (hesapla bağı kaldırılarak kendi sürelerinin sonuna kadar), Firebase'deki hata raporları ve kullanım istatistikleri (kendi sürelerinin sonuna kadar), oturum açma güvenlik kaydı (90 gün) ve hesap kimliğinizin tek yönlü özeti ile e-posta alan adınızdan oluşan anonim silme kaydı (3 yıl).

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

**sandık** bir portföy takip aracıdır. SPK (Sermaye Piyasası Kurulu) lisanslı bir yatırım danışmanı veya aracı kurum DEĞİLDİR. Uygulamada gösterilen fiyat, performans, sinyal, grafikler, piyasa hareketi ölçümleri (para akışı, hacim radarı, alıcı baskısı) ve yapay zekâ ile hazırlanan varlık notları bilgilendirme amaçlıdır ve yatırım tavsiyesi niteliği taşımaz. Yatırım kararlarınızı SPK lisanslı bir danışmana danışarak veriniz.

Bu uyarının tam metni kayıt sırasında (Apple veya Google ile ilk girişte açılan onay ekranında da) size gösterilir; metni sonuna kadar okuduktan sonra en altta onaylarsınız. Onayın kaydı yasal kanıt olarak saklanır.

---

## 13. Politikada Değişiklikler

Bu politikada değişiklik yaptığımızda:
- Yeni metin yeni bir sürüm numarasıyla yayımlanır; web sitesindeki ve uygulamadaki metin her zaman aynıdır
- "Son güncelleme" tarihi yenilenir
- Esaslı değişikliklerde (yeni bir kişisel veri, kişisel veri alan yeni bir üçüncü taraf, yeni bir amaç ya da saklama süresi) "Onay sürümü" de yeni sürüme çekilir; bir sonraki açılışta güncel metin ve değişikliklerin özeti gösterilir ve devam etmeden önce güncel metinle bilgilendirildiğinizi onay kutusunda belirtmeniz istenir
- Kişisel veri işleyişini değiştirmeyen düzeltmelerde (yazım, açıklama, kişisel veri almayan bir piyasa verisi kaynağı) yalnızca "Sürüm" ve "Son güncelleme" değişir; yeniden onay istenmez
- Yeni bir veri işleme, kişisel veri alan bir üçüncü taraf ya da saklama süresi ancak bu metin güncellenerek eklenir

---

## 14. İletişim

Veri korumayla ilgili tüm soru, talep ve şikayetler için:

- **E-posta:** `sandikapp.destek@gmail.com`
- **Adres:** `İstanbul, Türkiye`
- **Veri Koruma Sorumlusu (DPO):** Atanmamıştır. Veri koruma iletişimi: `sandikapp.destek@gmail.com`

---

*Bu politika Türkçe ve İngilizce dillerinde sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*''',
  'legal/tr/KVKK_AYDINLATMA_METNI.md': r'''# KVKK Aydınlatma Metni — sandık

**Yürürlük tarihi:** 8 Ekim 2026
**Son güncelleme:** 8 Ekim 2026
**Sürüm:** 1.8
**Onay sürümü:** 1.8

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
- Varlık notlarına geri bildirim (isteğe bağlı): oy, "yanlış sayı var" işareti, en fazla 500 karakterlik açıklama
- Premium hakkı: kaynağı (hediye, mağaza aboneliği ya da destek), başlangıç ve bitiş zamanı, mağaza ve ürün adı (ödeme ve kart bilgisi işlenmez)
- Abonelik verisi (yalnızca Premium satın alırsanız): mağaza işlem kaydı, ürün (aylık ya da yıllık), başlangıç ve bitiş tarihleri, iptal durumu, test satın alımı olup olmadığı

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
| Premium aboneliğin doğrulanması ve Premium içeriğe erişimin tanınması | 2.3 |
| Varlık notlarının doğruluğunun ölçülmesi ve iyileştirilmesi | 2.3 |
| Ortaklık özelliği (kullanıcılar arası paylaşım) | 2.1, 2.3 |
| Push bildirim ve kilit ekranı canlı etkinliği | 2.2, 2.3 |
| Yasal yükümlülüklerin yerine getirilmesi ve onayların kanıtlanması (yasal metin onayları, mahkeme/savcılık talepleri) | 2.5, 2.4 |
| Hata teşhisi ve uygulama güvenliği (tek aktif cihaz, yeni cihazda e-posta kodu) | 2.4 |
| Kötüye kullanım, sahtekarlık ve siber saldırı tespiti | 2.4 |
| Ürünün iyileştirilmesi ve kayıt sürecindeki sorunların tespiti | 2.6 |

---

## 4. Kişisel Verilerin Toplanma Yöntemi ve Hukuki Sebebi

### 4.1 Toplanma Yöntemi
- **Doğrudan kullanıcıdan:** Kayıt formu, Apple/Google ile giriş, varlık ekleme ve ekstre içe aktarma (ekstre dosyası yalnızca cihazda okunur, sunucuya gönderilmez; "Yapay zekâyla eşle"yi seçerseniz yalnızca tablonun anonim iskeleti gönderilir), profil ve bildirim ayarları
- **Otomatik:** Oturum açma anında IP/cihaz bilgisi, push token kaydı, kayıtlı cihaz bilgisi, hata kayıtları ve hata raporları, kullanım istatistikleri, kayıt hunisi adımları

### 4.2 Hukuki Sebep (KVKK Madde 5 ve 6)

| Veri | Hukuki sebep |
|---|---|
| E-posta, şifre, kullanıcı adı | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası için zorunlu |
| Portföy verileri | KVKK 5(2)(c) — sözleşmenin ifası |
| Yarış ölçümleri (getiri %, tür payı %) | KVKK 5(2)(c) — isteğe bağlı özelliğin ifası (katılırsanız) |
| Zirve havuzu ölçümleri (getiri %, tür payı %) | KVKK 5(1) — açık rıza (uygulama içinde, isteğe bağlı; her an geri alınabilir) |
| Push token | KVKK 5(2)(c) — bildirim izni verdiğinizde istediğiniz bildirimlerin teslimi |
| Premium hakkı ve abonelik verisi | KVKK 5(2)(c) — sözleşmenin kurulması ve ifası |
| Varlık notlarına geri bildirim | KVKK 5(2)(f) — meşru menfaat (notların doğruluğu); yalnızca siz gönderirseniz |
| IP, cihaz bilgisi, kayıtlı cihazlar, hata kayıtları | KVKK 5(2)(f) — meşru menfaat (güvenlik ve hata teşhisi) |
| Kullanım istatistikleri ve kayıt hunisi | KVKK 5(2)(f) — meşru menfaat (ürünün iyileştirilmesi) |
| Yasal metin onay kayıtları | KVKK 5(2)(e) — bir hakkın tesisi, kullanılması veya korunması; yatırım uyarısı için KVKK 5(2)(a) |
| Yurt dışı aktarımı (Supabase: {SUPABASE_ULKE}; Firebase ve RevenueCat: ABD) | KVKK 5(1) ve 9(1) — açık rıza |

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
| RevenueCat, Inc. (yalnızca Premium satın alırsanız) | ABD | Hesap numaranız (rastgele kullanıcı kimliği), mağaza işlem kaydı ve makbuzu, cihaz ve uygulama sürümü, IP adresi | Satın almanın mağazayla doğrulanması ve Premium hakkının sunucumuza bildirilmesi | KVKK 9(1) — açık rıza |

Premium ödemesini Apple ya da Google tahsil eder; kart ve ödeme bilgileriniz bize ulaşmaz, bunları mağaza kendi başına veri sorumlusu olarak işler.

Kamuya açık piyasa verisi sağlayıcılarına (borsalar, bankalar, fon platformları, resmî kurumlar ile kur ve fiyat veri servisleri) kişisel veri aktarılmaz; yalnızca varlığın sembolü, fon kodu ya da ISIN'i sorulur. Cihazdan giden isteklerde sağlayıcı, her internet isteğinde olduğu gibi cihazın IP adresini görür; bazı kaynaklara istekler yalnızca sunucumuzdan gider. Bu sağlayıcılar kişisel veri almadığı için tek tek sayılmaz; yeni bir fiyat kaynağı eklemek bu metni değiştirmez.

Varlık notlarını ve aylık raporu yazan yapay zekâ sağlayıcısına (Anthropic PBC, ABD) kişisel veri aktarılmaz: sunucumuz yalnızca varlığın sembolünü ve kamuya açık piyasa ölçümlerini (fiyat, işlem hacmi, fon büyüklüğü, para akışı, yatırımcı sayısı) gönderir; kimin hangi varlığı tuttuğu, miktar ve tutar gönderilmez. Notu okumanız yapay zekâya istek göndermez.

Ekstre içe aktarmada "Yapay zekâyla eşle"yi seçerseniz aynı sağlayıcıya ekstredeki tabloların anonim iskeleti gönderilir: sütun başlıkları ve genel finans kelimeleri kalır; ad, numara, tutar ve tarihler maskelenir. Bu iskelet kişisel veri içermez ve saklanmaz.

Aktarım yapılan ülkeler (Supabase: {SUPABASE_ULKE}; Firebase ve RevenueCat: ABD), Kişisel Verileri Koruma Kurulu'nun (KVK Kurulu) ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmamaktadır**. Bu nedenle yurt dışı aktarımı KVKK Madde 9(1) kapsamında **açık rızanıza** dayanmaktadır.

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
| Varlık notlarına geri bildirimler | Hesap silinene kadar | KVKK 5(2)(f) meşru menfaat |
| Ekstre sütun eşleme istek kayıtları (zaman, model, maliyet) | 40 gün | KVKK 5(2)(f) meşru menfaat (kötüye kullanım ve maliyet sınırı) |
| Premium hakkı ve abonelik kayıtları | Hesap silinene kadar; hesabı silince hemen. RevenueCat'teki işlem kaydı RevenueCat'in saklama süresince, ödeme ve fatura kayıtları Apple ya da Google'da kendi sürelerince kalır | Sözleşme süresi |
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
- Esaslı değişikliklerde (yeni bir kişisel veri, kişisel veri alan yeni bir alıcı, yeni bir amaç ya da saklama süresi) "Onay sürümü" de yeni sürüme çekilir; bir sonraki açılışta güncel metin ve değişikliklerin özeti gösterilir ve devam etmeden önce güncel metinle bilgilendirildiğinizi onay kutusunda belirtmeniz istenir
- Kişisel veri işleyişini değiştirmeyen düzeltmelerde (yazım, açıklama, kişisel veri almayan bir piyasa verisi kaynağı) yalnızca "Sürüm" değişir; yeniden onay istenmez
- Önceki sürümlerin tam metni ve hangi sürümün size ne zaman sunulduğu kayıt altında tutulur; talep ederseniz e-postayla gönderilir

---

*Bu Aydınlatma Metni kayıt sırasında (Apple veya Google ile ilk girişte açılan onay ekranında da) size bağlantı olarak sunulur; dokunduğunuzda tam metni açılır. Aydınlatma bilgilendirme amaçlıdır ve onayınıza bağlı değildir: onay kutusunda bu metinle bilgilendirildiğinizi belirtirsiniz ve metnin size sunulduğu kayıt altına alınır. Yurt dışı aktarım için açık rızanız bundan ayrı olarak Açık Rıza Metni ile alınır.*

---

**`Yasin Çıralı`**
**`Türkiye`**
**`sandikapp.destek@gmail.com`**''',
  'legal/tr/ACIK_RIZA_METNI.md': r'''# Açık Rıza Metni — sandık

**Yürürlük tarihi:** 8 Ekim 2026
**Sürüm:** 1.5

> Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") Madde 5(1) ve 9(1) uyarınca **açık rızanızı** almak için hazırlanmıştır. Bu metin kayıt sırasında (ya da Apple veya Google ile ilk girişte açılan onay ekranında) size tam olarak gösterilir; sonuna kadar okuduktan sonra açık rızanızı metnin sonundaki düğmeyle verirsiniz. Rıza yalnız bu düğmeyle verilir: kayıt ekranındaki onay kutusu Kullanım Koşulları'nın kabulü içindir ve açık rıza içermez. Bu şekilde verdiğiniz rıza aşağıdaki A bölümünü kapsar. B, C ve D bölümleri uygulamanın bu konulardaki işleyişini açıklar; ayrı bir onay istenmez. E bölümündeki rıza uygulama içinde ayrıca istenir.

---

## 1. Açık Rıza Veriyorum

`Yasin Çıralı` ("Şirket") tarafından sunulan **sandık** mobil uygulamasını kullanmak amacıyla:

### A) Yurt Dışına Veri Aktarımı

KVKK Madde 9(1) uyarınca aşağıdaki kişisel verilerimin sunucuları **{SUPABASE_ULKEDE}** bulunan **Supabase Inc.**'e, **Amerika Birleşik Devletleri'nde (ABD)** ve küresel altyapıda çalışan **Google LLC (Firebase: bildirim, hata raporu, kullanım istatistiği, uzaktan ayar; Gmail e-posta altyapısı)** ile **Apple Inc. (iOS bildirimleri ve kilit ekranı canlı etkinliği)** servislerine; Premium satın alırsam ayrıca abonelik doğrulaması için **ABD'deki RevenueCat, Inc.**'e;

- E-posta adresim
- Kullanıcı adım (görünen adım)
- Şifremin hash hâli
- Portföy varlık kayıtlarım (sembol, tür, miktar, alış fiyatı, tarih, not) ile vadeli mevduat ve BES sözleşme bilgilerim
- Performans anlık görüntü geçmişim
- Ortaklık bağlantı kayıtlarım
- Push bildirim token'ım ve bildirimlerin içeriği
- Oturum açma anındaki IP adresim, cihaz modelim, OS sürümüm ve kayıtlı cihazlarım
- Hata raporlarım ve uygulama kullanım istatistiklerim (tutar, miktar ve e-posta içermeden)
- Premium satın alırsam abonelik ve mağaza işlem kayıtlarım (kart ve ödeme bilgisi hariç)
- Yasal metin onay ve bilgilendirme kayıtlarım (kabul ettiğim ya da bana sunulan metin ve sürümü, zaman, platform, uygulama sürümü, dil)

aktarılmasına; bu ülkelerin KVK Kurulu'nun ilan ettiği "yeterli korumaya sahip ülkeler" listesinde **bulunmadığını** bildiğimi beyan ederek **AÇIK RIZA VERİYORUM**.

Bu rıza kayıt için zorunludur; metin sonuna kadar okunduktan sonra metnin sonundaki düğmeyle verilir (kayıt ekranında ya da Apple veya Google ile ilk girişte açılan onay ekranında).

---

### B) Push Bildirimleri

Bildirim izni bu metinle değil, **işletim sisteminin izin penceresiyle** verilir; uygulama bu pencereyi bildirimin işe yarayacağı bir anda (ör. ilk varlığınızı ekledikten sonra) gösterir. İzin verirseniz cihaz bildirim token'ınız sunucuya kaydedilir ve bildirimler Firebase Cloud Messaging (iPhone'da ayrıca Apple Push Notification service) üzerinden iletilir:

- Fiyat alarmları ve teknik analiz sinyalleri (açtıysanız)
- Günlük brifing, haftalık ve aylık özet
- Ortaklık daveti ve ortak etkinliği bildirimleri
- Temettü ve takvim hatırlatmaları

İzni istediğiniz zaman cihaz ayarlarından kapatabilirsiniz; bildirim türlerini uygulamada Ayarlar → Bildirimler'den yönetebilirsiniz.

---

### C) Hata Raporları ve Kullanım İstatistikleri

Uygulamada teknik bir çökme ya da hata yaşandığında hata kaydı, cihaz modeli, OS sürümü ve uygulama sürümü **Firebase Crashlytics** üzerinden; uygulamanın nasıl kullanıldığına dair olaylar (görüntülenen ekranlar, kullanılan özellikler) **Firebase Analytics** üzerinden Google'a gönderilir. Bu kayıtlar e-posta, parola, tutar ve miktar içermez; rastgele kurulum kimliği ve hesap numaranız (rastgele kullanıcı kimliği) ile ilişkilendirilir. Bu verilerin yurt dışına aktarımı yukarıdaki A bölümündeki açık rızanız kapsamındadır. Uygulamada bunlar için ayrı bir kapatma seçeneği yoktur.

---

### D) Pazarlama İletişimi

Uygulama size **pazarlama e-postası veya reklam iletisi göndermez**. Size gönderilen e-postalar yalnızca hesap e-postalarıdır (kayıt, giriş ve yeni cihaz doğrulama kodları, şifre sıfırlama). İleride pazarlama iletişimi eklenirse bunun için ayrıca onayınız istenir.

---

### E) Zirvedeki Portföyler (uygulama içinde ayrıca istenir)

Bu rıza kayıt sırasında DEĞİL, Zirvedeki Portföyler ekranını ilk açtığımda ayrı bir kartla istenir. Dönemsel getiri yüzdemin, varlık türü paylarımın ve fonlarda TEFAS fon kodu ile portföy içindeki payının anonim bir karşılaştırma havuzunda işlenmesine ve havuza katılan diğer kullanıcılara kimliğim, tutarlarım ve miktarlarım olmadan gösterilmesine; karşılığında katılımcıların aynı anonim bilgilerini görmeye **AÇIK RIZA VERİYORUM** (ayrıntı: Gizlilik Politikası §5.1, KVKK Aydınlatma Metni §5.3). Rıza vermezsem getirim bu amaçla hesaplanmaz; uygulamanın diğer özellikleri etkilenmez. Rızanın verildiği tarih ve gösterilen metnin sürümü ispat için kaydedilir.

Bu rıza ekrandaki "Katılıyorum" düğmesiyle verilir; isteğe bağlıdır.

---

## 2. Açık Rızamın Geri Alınması

Vermiş olduğum açık rızayı, KVKK Madde 7 ve 11 uyarınca **istediğim zaman geri alabileceğimi** biliyorum:

- **Zirvedeki Portföyler rızası:** Performans → Zirvedeki Portföyler → "Zirvedeki Portföyler'den ayrıl" (havuzdaki ölçümler anında silinir)
- **Yurt dışı aktarım rızası:** Açık rızamın geri çekilmesi, hizmetin sunulamaması anlamına gelir; bu durumda hesabımı silmem gerekir (Profil → Ayarlar → Hesabımı Sil).
- **Bildirim izni:** Cihaz ayarlarından kapatılır (B bölümü).

Rızamı geri çektiğim tarihten önceki işleme faaliyetleri hukuka uygun sayılmaya devam eder.

---

## 3. Açık Rızanın Geri Alınmasının Sonuçları

| Geri çekilen rıza ya da izin | Sonuç |
|---|---|
| Yurt dışı aktarım (A) | Hizmet sunulamaz; hesabınızı silerek rızanızı geri çekersiniz |
| Bildirim izni (B) | Bildirim alamazsınız; ortaklık davetlerini ve bildirimleri uygulama içinden kontrol edersiniz |
| Zirvedeki Portföyler (E) | Havuzdaki ölçümleriniz silinir; zirve listesini göremezsiniz, diğer özellikler etkilenmez |

---

## 4. Beyan

- Bu Açık Rıza Metni'ni okuduğumu,
- Kişisel verilerimin nasıl işleneceğini, hangi amaçlarla kullanılacağını, kimlere aktarılacağını ve haklarımı **KVKK Aydınlatma Metni**'nden ayrıntılı olarak öğrendiğimi,
- Verdiğim açık rızanın **özgür iradem ile, belirli ve bilgilendirilmiş** şekilde verildiğini,
- 18 yaşından büyük olduğumu ve bu rızayı verme ehliyetinin bulunduğunu

beyan ve kabul ederim.

---

**Tarih:** Onay anında otomatik kaydedilir
**Sürüm:** 1.5
**Platform:** Android / iOS, uygulama sürümü ve dil onay anında otomatik kaydedilir

---

*Açık rıza onayınız, hesabınız silinene kadar Şirket tarafından kanıt olarak saklanır. Sildiğiniz hesabın açık rıza kayıtları, TBK Madde 146 zamanaşımı süresi olan **3 yıl** boyunca saklanır; Zirvedeki Portföyler rızasının kaydı hesapla birlikte silinir.*''',
};
