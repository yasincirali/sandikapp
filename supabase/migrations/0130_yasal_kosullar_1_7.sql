-- 0130 — Yasal metin: Kullanım Koşulları 1.7 (2026-10-10)
--
-- ## Neden
-- Olgun Premium seti (dal feat/premium-olgun): teknik sinyaller paywall
-- açıkken bütünüyle Premium; yıllık kâr/temettü/masraf raporu, PDF/Excel
-- dışa aktarma, temettü tahmini ve kalem kalem masraf dökümü eklendi.
-- Koşullar §1 sinyalleri "(Premium)" diye, §2A kapsam örnekleri yeni
-- listeyle güncellendi. Kişisel veri işleyişi değişmedi; yeni alıcı yok
-- (PDF/Excel cihazda üretilir, paylaşımı kullanıcı yapar). Bu yüzden
-- ESASLI DEĞİL: yalnız "Sürüm" 1.6 → 1.7; "Onay sürümü" 1.6 kalır,
-- kimseye yeniden onay sorulmaz (CLAUDE.md "Yasal metin tek kaynak").
--
-- ## Eski istemciler
-- Yalnız EKLER: tek metin satırı. Fonksiyon, tablo, RLS ve GRANT'a
-- DOKUNULMAZ. Onay sürümü değişmediği için eski ve yeni istemcide kapı
-- açılmaz.
--
-- ## Dağıtım sırası
-- İKİ sunucuya (Frankfurt → Tokyo) → `python tool/sema_esitlik.py`.
--
-- ## Metin ekleme
-- INSERT `tool/yasal_metin_uret_test.dart` çıktısıdır; gövdeye elle
-- dokunma (hash check'i tutmaz).

-- ── 1) Metin (tool/yasal_metin_uret_test.dart çıktısı)

-- kosullar/1.7/tr  (Kullanım Koşulları)
insert into public.yasal_metinler
  (tur, surum, dil, baslik, yururluk_tarihi, govde_hash, govde)
values ('kosullar', '1.7', 'tr', 'Kullanım Koşulları', date '2026-10-08',
  '705aa9aa32ab34c276c661d99254aaea5fbdcc6e8bd40ff354d2861079b07425',
  replace($yasal$# Kullanım Koşulları — sandık

**Yürürlük tarihi:** 8 Ekim 2026
**Son güncelleme:** 10 Ekim 2026
**Sürüm:** 1.7
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

Uygulama; portföy değerini, dağılımını, performansını ve isteğe bağlı olarak teknik analiz sinyallerini (Premium), fiyat alarmlarını ve dönemsel özetleri gösterir. Varlıklarınızı elle, toplu olarak ya da banka/aracı kurum ekstresinden içe aktararak girebilirsiniz. Çoklu kullanıcı ortaklığı özelliğiyle iki kullanıcı portföylerini paylaşabilir.

**Zirvedeki Portföyler (isteğe bağlı):** Uygulama içinde açık rıza verirseniz dönemsel getiriniz ve varlık türü paylarınız anonim bir karşılaştırma havuzunda değerlendirilir (portföy 5 günden eski, en az 2 farklı varlık); en çok kazanan portföylerin yalnızca sırası, getirisi, tür payları ve fonların TEFAS kodu ile payları, kimlik ve tutar olmadan diğer katılımcılara gösterilir; karşılığında siz de katılımcıların aynı anonim bilgilerini görürsünüz (ayrıntı: Gizlilik Politikası §5.1). İstediğiniz an ayrılabilirsiniz; katılmamak başka hiçbir özelliği etkilemez.

**Yarış (isteğe bağlı):** Yarış'a katılırsanız dönemsel getiriniz ve varlık türü paylarınız günlük olarak sunucuda hesaplanır; katılımcılar arasındaki yeriniz size yüzdelik dilim olarak gösterilir, ortağınızla getirinizi karşılaştırabilirsiniz. Diğer katılımcılara kimliğiniz ve tutarlarınız gösterilmez. Yarış'tan istediğiniz an ayrılabilirsiniz.

**Piyasa hareketi ve varlık notları:** Uygulama, kamuya açık piyasa verisinden fonlara giren ve çıkan parayı (para akışı), hisselerde olağandışı işlem hacmini (hacim radarı) ve kriptoda alıcı baskısını gösterir. Portföyündeki varlıklar için haftalık varlık notları ve aylık rapor, yapay zekâ ile otomatik hazırlanır (ayrıntı: Gizlilik Politikası §5.3). Notların tamamı ve aylık rapor Premium üyelere açık olabilir; ücretsiz katmanda notun ilk cümlesi gösterilir.

---

## 2A. Premium Abonelik

Bu bölüm, Premium uygulamada satışa sunulduğunda geçerlidir.

**Kapsam.** Portföy takibi ücretsizdir. Premium, ücretsiz katmanda sınırlı olan ya da yalnızca abonelere açık olan özellikleri (ör. teknik analiz sinyalleri ve bildirimleri, yıllık kâr, temettü ve masraf raporu, PDF ve Excel dışa aktarma, temettü tahmini, kalem kalem masraf dökümü, varlık notlarının ve aylık raporun tamamı, ekstrenin yapay zekâyla okunması) içerir. Hangi özelliğin Premium olduğu satın alma ekranında, satın almadan önce gösterilir. Ücretsiz katmanda Premium özelliklerin bir kısmı sınırlı biçimde görünebilir (ör. notun ilk cümlesi).

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

*Bu Koşullar Türkçe ve İngilizce olarak sunulmaktadır. Yorum farklılığı durumunda Türkçe versiyon esas alınır.*$yasal$, chr(13), ''))
on conflict (tur, surum, dil) do nothing;

-- ── 2) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_class
                  where oid = 'public.yasal_metinler'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0130: yasal_metinler RLS (enable + force) kapali';
  end if;
  if has_table_privilege('authenticated', 'public.yasal_metinler', 'INSERT') then
    raise exception '0130: yasal_metinler istemciden yazilabilir';
  end if;
  if not exists (select 1 from public.yasal_metinler
                  where tur = 'kosullar' and surum = '1.7' and dil = 'tr') then
    raise exception '0130: kosullar/1.7/tr metni yok';
  end if;
  if exists (select 1 from public.yasal_metinler
              where tur = 'kosullar' and surum = '1.7'
                and govde_hash <> encode(sha256(convert_to(govde, 'UTF8')), 'hex')) then
    raise exception '0130: govde_hash tutmuyor';
  end if;
  raise notice '0130 tamam: Kosullar 1.7 (onay surumu 1.6).';
end $$;
