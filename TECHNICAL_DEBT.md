# sandık — Teknik Borç Defteri

Ertelenmiş **kod** kararları. Kullanıcının elden yapacağı işler
`YAPMAN_GEREKENLER.md`'de; burası yalnızca kod tabanına dair borç.

Her madde: neden ertelendi, ertelemenin maliyeti ne, ne zaman ele alınmalı.

**Son güncelleme:** 2026-09-20 (GÜNLÜK değişim kartı ile kilit ekranı arasındaki arındırma ayrışması)

---

## 🟡 AÇIK — GÜNLÜK değişim kartı HAM, kilit ekranı ARINDIRILMIŞ: alım yapılan günde iki rakam ayrışıyor

**Nerede.** `lib/screens/portfolio_performance/kartlar.dart` →
`_buildPeriodChangeCard` (ana rakam `grossChange`) ile
`lib/services/daily_summary.dart` → `DailySummary.from` (bugünkü net akış
düşülür).

**Durum.** Canlı Etkinlik, ana ekran widget'ı, ana ekrandaki "Bugün" kartı ve
Performans → **Özet** sekmesi aynı hesaptan (`DailySummary`) besleniyor:
bugünkü alım/satım tutarı çıkarılır, geriye yalnızca piyasa hareketi kalır.
Performans → **Grafik** sekmesinin üst kartı ise 2026-08-31 kullanıcı
kararıyla HAM ("birikim") değişimi gösteriyor; akışı yalnızca alt not
satırında ayırıyor.

Bugün 170.000 TL'lik alım yapan ve piyasada +900 TL kazanan kullanıcı:

| Yüzey | Gösterilen |
|---|---|
| Kilit ekranı / widget / "Bugün" kartı / Özet | **+₺900** |
| Performans → Grafik üst kartı | **+₺170.900** (not satırı: 170.000'i alım) |

**Neden ertelendi.** İki kullanıcı kararı çelişiyor: 2026-08-31 ("birikim
büyümesini görmek istiyorum, alım dahil") ve `daily_summary.dart`
"Değişmezler" ("üç yüzey aynı rakamı göstermek ZORUNDA"). Hangisinin GÜNLÜK
dönemde kazanacağı bir üslup kararı, kod kararı değil — kendiliğinden
çevrilmedi.

**Maliyet.** Yalnızca **alım/satım yapılan günlerde** görünür; diğer
günlerde `netInflow ≈ 0` olduğu için iki rakam zaten eşit. Ayrıştığı günde
kullanıcı kilit ekranından gelip 190 kat büyük bir sayı görüyor ve hangisine
güveneceğini bilemiyor.

**Seçenekler.** (a) GÜNLÜK dönemde kartın ana rakamı arındırılmışa
çevrilir, birikim rakamı alt satıra iner — diğer dönemler 2026-08-31
kararında kalır; (b) kilit ekranı da hama çevrilir (önerilmez: "bugün
kazandım" yanılgısı v2'de tam olarak bu yüzden düzeltilmişti); (c) kart
GÜNLÜK'te iki rakamı da eşit ağırlıkta gösterir.

**Ne zaman.** Kullanıcı hangi seçeneği istediğini söylediğinde; kod
değişikliği tek metotla sınırlı.

---

## ✅ KAPANDI — Kalan `unawaited(...)` çağrıları hatayı zone handler'a sızdırıyordu

**Kapanış (2026-09-20, `feat/buyume-turu`).** 40 çıplak `unawaited(...)`
`CrashReporter.arkaPlan(..., reason:)`'a taşındı (`arkaPlan` artık
`Future<Object?>` alıyor; sonuçlu işler de bırakılabiliyor). Geriye
kalanlar bilinçli: Analytics (`_log` kendi yakalar), `.catchError(` taşıyan,
`SystemNavigator`/`slidable`/`showAppSuccess` (UI). Kural artık
ratchet: `test/arka_plan_hata_yutma_test.dart` `lib/` içinde çıplak
`unawaited` görürse kırılır. `catch`siz buton handler'ı yüzü
`buton_handler_sahipsiz_test` ile ayrıca kilitli (2026-09-19).

**Ne.** `unawaited()` yalnızca `unawaited_futures` lint'ini susturur; hatayı
YUTMAZ. Await edilmeyen bir future hata ile biterse hata `main.dart`'taki
`runZonedGuarded` handler'ına düşer ve Crashlytics'e ÇÖKME olarak gider —
uygulama çalışmaya devam etse bile. Üretimdeki örneği buydu: "Fatal
Exception: FlutterError → `DbLogger.log` → `SupabaseService.updateAsset`"
(2026-09-19), gerçekte 15 saniyelik timeout'a düşmüş bir fiyat yazımı.

**Ne yapıldı.** Çökmenin kaynağı (`refreshPrices` fiyat yazımı) düzeltildi;
ağa dokunan ateşle-unut çağrıları (`refreshPrices` tetikleyicisi, liderlik
snapshot upload'ları, ortak varlık tazeleme) `CrashReporter.arkaPlan(...)`
sarmalayıcısına alındı; global handler'lar ağ hatasını artık `fatal: false`
kaydediyor (`CrashReporter.agHatasiMi`).

**Neden açık.** Geriye ~60 `unawaited(...)` kaldı: çoğu Analytics/Retention
(Firebase SDK kendi içinde yutar), tercih yazımı, widget/Live Activity
senkronu. Hepsini bir turda taşımak bu düzeltmenin yüzeyini gereksiz
genişletirdi ve her birinin doğru `reason` etiketi ayrı karardır.

**Aynı ailenin ikinci yüzü: `catch`siz async buton handler'ı.**
`onPressed: _birSey` bir `Future` döndürür ve kimse beklemez — `unawaited`
yazmasa da sahipsizdir. `add_asset_screen._save` böyleydi (2026-09-19'da
kapandı): ağ koparsa Crashlytics ÇÖKME kaydediyor, kullanıcı ise kaydın
olmadığını hiç öğrenmiyordu. Ekranlarda bu desenin tam taraması YAPILMADI;
kırılgan olanları (ağ/DB yazan handler'lar) elden geçirmek ayrı bir tur.

**Maliyet.** Bu çağrılardan biri AĞ DIŞI bir hata fırlatırsa (ör. platform
kanalı eksik, null cast) hâlâ fatal çökme olarak raporlanır. Gürültü riski;
`catch`siz handler'da ayrıca kullanıcı sessiz başarısızlık görür.

**Ne zaman.** Crashlytics'te arka plan işlerinden gelen ağ dışı fatal
görülürse, ya da bir sadeleştirme turunda toptan
(`test/arka_plan_hatasi_fatal_degil_test.dart` taramasını Supabase
yazmalarından tüm servis çağrılarına genişleterek).

---

## 🟡 AÇIK — Dönem özeti push'unun istemcide kapatma anahtarı yok

**Ne.** Haftalık (0052) ve aylık (0067) özet push'u `profiles.weekly_summary_push`
sütununu okuyor ama Ayarlar › Bildirimler'de bu sütunu yazan bir anahtar
YOK; kullanıcı yalnızca sistem kanalından (`summary_channel`, Android) ya
da sessiz saatlerle susturabiliyor. iOS'ta kanal kavramı olmadığı için
tek yol bildirimleri toptan kapatmak.

**Neden açık.** Anahtar ucuz (`_SettingsTile` + `SupabaseService`
`update profiles`), ama `daily_brief` tercihi de aynı durumda; ikisi tek
"Proaktif bildirimler" grubu olarak tasarlanmalı (brifing / dönem özeti /
takvim) — ayrı ayrı üç anahtar Ayarlar'ı şişirir.

**Ne zaman.** Aylık push'un ilk iki gönderiminden sonra (Ekim–Kasım 2026);
`push_opened` oranı %3'ün altına düşen tipe kapatma anahtarı şart olur.

**Ek (2026-09-20, günlük giriş turu).** Aynı sınıfa iki tür daha girdi:
`watchlist_move` (kullanıcı seçimli, alarm kanalı) ve `inflation_day`
(ayda bir). Brifing için "Brifing saati" seçici eklendi ama o da kapatma
anahtarı DEĞİL. "Proaktif bildirimler" grubu artık beş türü kapsar: brifing
(sabah/akşam), haftalık, aylık, TÜFE günü, takip hareketi. Grup tasarımı
aynı tur.

---

## 🟡 AÇIK — Takip listesi hareketi fonları (TEFAS) kapsamıyor

**Ne.** `watchlist_moves.ts` günlük değişimi canlı kotasyondan okuyor;
TEFAS tek NAV döndürür, dünkü NAV ayrı istektir. Fon izleyen kullanıcı bu
push'u hiç almaz.

**Ne zaman.** `observe-tefas-nav` gözlem tablosu (0063) dünkü NAV'ı zaten
biriktiriyor; iki günlük fark oradan hesaplanabilir. Fon hareketi hisseye
göre küçük (%5 eşiğini nadiren geçer), eşik fon için ayrı (%2) olmalı.
İlk dört haftanın `push_opened` verisiyle birlikte.

---

## 🟡 AÇIK — Universal Links / App Links yok; paylaşılan bağlantı web sayfasına iner

**Ne.** Paylaşım kartı ve ortak daveti artık `…/sandikapp/indir/` bağlantısı
taşıyor (2026-09-20). Uygulama kuruluysa bile bağlantı tarayıcıda açılır;
Universal Link olsa doğrudan uygulama açılır ve `kod=` ile ortak kodu
kendiliğinden girilirdi.

**Neden açık.** AASA dosyası alan adının KÖKÜNDE olmalı
(`https://<domain>/.well-known/apple-app-site-association`); site
`yasincirali.github.io/sandikapp/` alt yolunda — kök başka bir repo.
Özel alan adı (ör. `sandik.app`) ya da `yasincirali.github.io` kök
reposu gerekir; ikisi de kullanıcı kararı (`YAPMAN_GEREKENLER.md`).
Entitlement/manifest değişikliği alan adı olmadan yapılmadı: Associated
Domains yeteneği App ID'de açık değilse fastlane match imzalamayı kırar.

**Ne zaman.** Alan adı alınınca: AASA + `assetlinks.json` (`docs/.well-known/`),
`Runner.entitlements` `applinks:`, `AndroidManifest` `autoVerify` intent
filter, `DeepLinkService`'e `indir?kod=` yolu. Yarım gün.

---

## ✅ KAPANDI — Ölçek hafızası OTURUM İÇİYDİ; soğuk açılışta birincil kaynak düşükse ölçek bilinmiyordu

**Nasıl kapandı (2026-09-17, aynı gün).** Kullanıcı: "Bazen doğru gösteriyordu
ancak bazen zıplamalar oluyordu, ihtimalleri de bitirmen gerek." İki bellek
de `shared_preferences`'a kalıcılaştırıldı:
· `OlcekHafizasi` oranları (`olcek_hafizasi_v1`) — `ogren` diske yazar,
  `yukle` ilk kullanımda okur; bu oturumda öğrenilen oran diskteki eskiyi ezer.
· `PriceService` son birincil fiyatları (`son_birincil_fiyat_v1`, yalnızca
  truncgil kaynaklı, TTL 6 saat) — ilk yedek geçişinde oran buradan öğrenilir.
`fetchQuotes` ağa çıkmadan önce ikisini de bekler. Ayrıca `_extractFx`'teki
uydurma `USD×1,1`/`×1,28` çapraz kuru kaldırıldı; EUR/GBP yoksa anahtar
verilmez, provider son bilinen kuru korur. Test:
`test/olcek_hafizasi_kalicilik_test.dart`. Kalan tek boşluk: ilk kurulumda
(diskte hiçbir kayıt yokken) truncgil tümüyle ulaşılamazsa yedek ham kalır —
karşılaştırılacak önceki değer de olmadığı için "zıplama" görünmez.

**Aşağısı kapanış öncesi kayıt.**

**Ne çözüldü (TestFlight bildirimi, 2026-09-17).** *"Çok kısa zaman
içerisinde yüksek sıçramalar ve düşüşler... canlı etkinliklerden fark
ettim, bir eksi de bir artı da gözüküyordu."*

Sebep fiyat hareketi değil KAYNAK DEĞİŞİMİydi: canlı altın birincil
kaynaktan (truncgil, yurt içi kotasyon) gelir; o kaynak bir tur cevap
vermezse yedek yol uluslararası spot/vadeli çevriminden sayı üretiyordu ve
iki ölçek arasında kalıcı ~%1-2 makas var. 45 saniyelik kotasyon
önbelleğiyle birlikte fiyat dakikalar içinde ileri geri zıplıyor; portföy
toplamı, grafiğin son noktası ve Live Activity'nin "bugünkü değişim"i aynı
anda işaret değiştiriyordu. Aynı sınıf makas kurda da var (truncgil `Alış`
↔ er-api mid).

`OlcekHafizasi` yedeğin sayısını birincilin ölçeğine taşıyor. Oran ek ağ
maliyeti olmadan öğreniliyor: grafik yolları zaten her çizimde canlı ÷ seri
oranını hesaplıyor (`altinKalibrasyonHaritasi`, `kurSerisiniHizala`). Oran
spot ve vadeli için AYRI tutuluyor (ikisi aynı ölçek değil) ve sınır dışı
bir oran (ör. atlanmış ağırlık çarpanı → 7,2 kat) öğrenilmiyor — kalibrasyon
bir ölçek hatasını örtmemeli.

**Neden hâlâ AÇIK.** Hafıza oturum içi. Uygulama soğuk açılırken truncgil
düşükse ve bu oturumda hiç birincil fiyat görülmediyse oran bilinmez; yedek
HAM kullanılır (uydurma çarpan yok, ama ölçek farkı görünür). Pratikte ilk
grafik çizimi saniyeler içinde oranı öğreniyor ve ilk geçişte oturumda
görülmüş son birincil fiyattan da öğrenilebiliyor — yine de kalıcılaştırma
(`shared_preferences`) bu boşluğu tamamen kapatır.

**Ne zaman ele alınmalı.** Kullanıcı "açılışta bir an farklı fiyat gördüm"
derse ya da `fiyat_yedek_kaynak` non-fatal'ı üretimde sık görülürse.

**Teşhis.** Yedek kaynak devreye girdiğinde Crashlytics'e
`fiyat_yedek_kaynak` non-fatal'ı düşüyor (hangi kaynak + ölçek hafızası var
mı). `PriceService.sonKaynak(sembol)` son fiyatı kimin verdiğini söylüyor.

**İlgili.** `test/olcek_hafizasi_test.dart`, `lib/services/fiyat_kaynagi.dart`.

---

## ✅ KAPANDI — Grafik çekimleri üç ayrı kapıdan geçiyordu (timeout/tekilleştirme/negatif önbellek yok)

**Ne.** Dört grafik yolu üç ayrı yerel closure ile çekim yapıyordu
(`getHistorySafe`, `getHistorySafeFor`, `_fetchSafe`). Üçü de aynı işi
yapıyor görünüyordu ama ayrışmışlardı ve her ayrışmanın ölçülebilir bir
maliyeti vardı:

1. **Timeout yalnızca birinde vardı.** 2026-09-13'te konan 8 saniyelik üst
   sınır (`_grafikCekimSuresi`) yalnızca `_fetchSafe`'e uygulanmıştı; gün içi
   ve günlük yollarda tek koruma alt katmandaki 15 saniyeydi. "Uzun süre
   bekleyince geldi, kimse bu kadar beklemez" şikâyeti o yollarda hâlâ
   geçerliydi — üstelik o tarihte yazılan test `.timeout(...)` metnini
   dosyada bulduğu için YEŞİL görünüyordu.
2. **Uçuşan istek tekilleştirmesi hiçbirinde yoktu.** Takip listesinde 10
   satır aynı anda `USDTRY=X` isterse 10 ayrı HTTP çağrısı gidiyordu.
3. **Boş yanıt hatırlanmıyordu.** Veri vermeyen sembol her tazelemede
   yeniden isteniyor ve her seferinde timeout'a kadar bekletiyordu; altın
   kaynağının "bazen spot, bazen vadeli" savrulmasının yakıtı da buydu.

**Çözüm.** Tek kapı: `HistoryService.seriCek` — önbellek (range'e göre TTL)
→ negatif önbellek (60 sn) → uçuşan istek tekilleştirme → timeout → ölçüm.
Tier yolu da ham noktaları aynı kapıdan alıyor, yani performans ekranı,
karşılaştırma ve takip listesi aynı sembol+range+interval için tek istek
paylaşıyor. Kapı `seriCekici` ile enjekte edilebilir; davranış ağa çıkmadan
ölçülüyor (`test/seri_cekim_kapisi_test.dart`, `fake_async`).

---

## 🟡 AÇIK — "Bugün" kartı: takvimin kişisel yarısı ve tur kısaltma yapılmadı

**Ne yapıldı (2026-09-20, `feat/gunluk-ilgi`).** Ana ekrana her gün değişen
"Bugün" kartı (`services/bugun_service.dart`, `widgets/bugun_karti.dart`):
günün hareketi / sonraki açılış, dönüşümlü içgörü (artıdaki varlık oranı,
hedefe kalan, yaklaşan TÜİK-tatil-ay sonu), ayın ilk 3 günü aylık özet girişi;
portföy hedefi (`portfolioGoalProvider`, Ayarlar › Görünüm ve karttan).
TÜFE kartı etiketleri sade dile ("Senin getirin / Enflasyon (TÜFE) / Aradaki fark").

**Bilerek yapılmayan / ertelenen:**
1. **Kişisel takvim** — temettü ödeme tarihleri (KAP), fon kesinti günleri.
   Yeni bir veri kaynağı (KAP API/scrape) ve sunucu tarafı tablo ister; ulusal
   takvim (TÜİK, BIST tatili, ay sonu) `BistTakvimi` ile bedavaya geldi,
   kişisel olan gelmedi. En yüksek geri getirme değeri burada — ilk izleme
   turunda Bugün kartının `todayEventCpi` satırına dokunma/görüntülenme
   oranı ölçülünce karar verilir.
2. ✅ **Tanıtım turu kısaltıldı (2026-09-20).** İlk açılış 19 → 5 adım
   (`_kisaAdimlar`: karşılama, toplam, Bugün, +, ekstre yapıştır); tam tur
   Ayarlar'dan. "İlgili ekranda ilk girişte tek ipucu" kısmı YAPILMADI —
   kısa turun kurulum→ilk varlık dönüşümü ölçülmeden ikinci katman gereksiz.
3. **Aylık özet ekranı yok** — giriş Performans › Özet › 1A'ya gidiyor.
   Yıllık `RecapScreen`'in aylık sürümü (karakter sayfası hariç) ucuz ama
   ayrı bir yüzey; önce girişin tıklanıp tıklanmadığı ölçülsün. Aylık
   özet PUSH'u ise var (2026-09-20, `weekly-summary` `period=month`, 0067).
4. ✅ **Kart içi ölçüm (2026-09-20).** `today_row_shown` / `today_row_tapped`
   (kind: degisim|kapali|yesil|hedef|hedef_yok|olay_*|aylik, gün başına bir
   gösterim) ve `goal_set` (tutar kovası). Firebase DebugView'da doğrula.

**Ne zaman.** Bugün kartı TestFlight'ta bir hafta kalıp kullanıcı geri
bildirimi alındıktan sonra; ölçüm → 1 → 3 sırasıyla.

---

## 🟡 AÇIK — Fiyat kaynağı sözleşmesi kuruldu; CANLI kotasyon tarafı henüz dışarıda

**Ne yapıldı (2026-09-17, kullanıcı kararı).** *"Tüm varlıklar her yerde tek
kaynaktan ve tutarlı şekilde çekilmelidir."* Sözleşme
`lib/services/fiyat_kaynagi.dart`'ta toplandı: sembol kararı
(`seriSembolleri`), altın merdiveni (`altinGramSerisi`), ölçek hizalaması
(`olcekCarpani`, `kurSerisiniHizala`, `altinKalibrasyonHaritasi`). Dört
grafik yolu + sparkline oradan geçiyor; `fiyat_kaynagi_sozlesmesi_test`
sözleşmenin dışına sızan ham sembolü ve uydurma kur sabitini tarıyor.

**Kapanan üç ayrışma:**
- sparkline altını `GC=F` (ons/USD şekli) çiziyordu → artık gram22k TL,
- grafik yolları kur bulunamayınca `35.0`/`40.0` uyduruyordu → artık canlı
  kur (oturumda görülen son gerçek değer), o da yoksa nokta seriye girmez,
- kur serisi Yahoo mid'di, ekrandaki TL karşılığı truncgil `USD` (Alış) —
  seri artık canlı kura hizalanıyor, yani USD kote bir hissede kâr/zarar
  çipi ile grafiğin son noktası aynı sayıyı veriyor.

**Neden hâlâ AÇIK.** `PriceService` CANLI kotasyon tarafının kendi
merdivenini taşımaya devam ediyor (truncgil → er-api → Yahoo; altın anahtar
tablosu `_truncgilGoldKeys`). Sözleşme dosyası şimdilik yalnızca SERİ
tarafını yönetiyor; testteki sembol taraması bu yüzden `price_service.dart`
için muaf. İki taraf ayrışırsa (ör. truncgil bir sembolü bırakır) yine
sessiz bir sapma oluşur.

**Ne zaman ele alınmalı.** `PriceService`'in kaynak seçimi sözleşmeye
taşınırken; aynı turda sunucu tarafındaki eşi (`_shared/live_prices.ts`
`GOLD_KEYS`) ile parite testi de yazılmalı (bkz. "Dış fiyat API'leri
sessizce değişiyor" maddesi).

**İlgili.** `test/fiyat_kaynagi_sozlesmesi_test.dart`, `CLAUDE.md` →
"Fiyat kaynağı" kuralı.

---

## ✅ KAPANDI — Altın serisinin kaynağı istekten isteğe değişiyordu (ARALIKLI sapma)

**Belirti (kullanıcı, 2026-09-17).** Altın grafiğinin son noktası sahte bir
düşüş çiziyordu; ikinci bildirim kritik ipucuydu: **"Her zaman da olmuyor,
şu anda düzeldi."** Kalıcı bir ölçek farkı bunu açıklamaz — aralıklı bir
şey olmalıydı.

**Kök sebep.** Altın serisi iki AYRI enstrümandan kurulabiliyordu:

| Kaynak | Ne | Seviye |
|---|---|---|
| `XAUTRY=X` | spot altın, doğrudan TRY | referans |
| `GC=F × USDTRY=X` | COMEX **vadeli** sözleşmesi | taşıma maliyeti kadar ÜSTÜNDE (~%1-2) + ikinci bir çevrim hatası |

Merdiven **dört kopyaya ayrılmıştı**: yalnızca gün içi yolu spot'u tercih
ediyordu; günlük, tier ve tek-sembol yolları vadeliyi TEK kaynak sayıyordu.
Üstelik Yahoo `XAUTRY=X` için aralıklı olarak boş liste/404/429 döner ya da
8 saniyelik `_grafikCekimSuresi` sınırını aşar — ve **boş yanıtlar
önbelleğe alınmadığı için her tazelemede zar yeniden atılır.** Aynı grafik
bir açılışta spot, beş dakika sonra vadeli ölçeğinde çiziliyordu. Serinin
son noktası canlı (yurt içi) fiyata sabitlendiğinden fark "ŞİMDİ"
imlecinde sahte bir düşüş oluyordu: bazen var, bazen yok.

**Yanında çıkan ikinci sessiz sapma.** Vadeli çevrimde kur bulunamazsa iki
uzun dönem yolu uydurma sabit kullanıyordu — `35.0` (günlük) ve `40.0`
(tier). `USDTRY=X` düştüğü an altın serisi ~%17'ye varan sapmayla, hiçbir
uyarı vermeden çiziliyordu. Gün içi yolunda bu sabit zaten kaldırılmıştı;
diğer ikisi o dersin dışında kalmıştı (yine kopya sorunu).

**Çözüm.** Merdiven tek yerde: `altinGramSerisi` (spot → vadeli, karışım
yok, uydurma kur yok) ve dört yol da oradan geçiyor. `debugSonAltinKaynagi`
hangi kaynağın kullanıldığını dışarıdan görülebilir yapıyor. Kalıcı makas
için ikinci savunma hattı `altinKalibrasyonu` (aşağıdaki madde).

**İlgili.** `test/altin_seri_kaynagi_test.dart`,
`test/altin_grafik_gecikmesi_test.dart`.

---

## 🟡 AÇIK — Altında gün içi ŞEKİL uluslararası spot'tan, SEVİYE yurt içi kotasyondan

**Ne.** Altın grafiği artık canlı fiyat ölçeğine kalibre ediliyor
(`altinKalibrasyonu`): Yahoo'dan (`XAUTRY=X` / `GC=F`) gelen seri, sembol
başına bir çarpanla truncgil kotasyonunun seviyesine taşınıyor. Yani
çizginin **şekli** uluslararası spot'un, **seviyesi** yurt içi
kotasyonundur.

**Neden böyle (2026-09-17).** Yurt içi gram altının gün içi serisini veren
bir kaynağımız yok; elimizde yalnızca ANLIK kotasyon var. Üç seçenekten:

1. *Hiçbir şey yapmama.* Ölçülen arıza buydu: seri bir ölçekte ilerliyor,
   son nokta canlı değere sabitlendiği için diğerine atlıyordu — kullanıcı
   ekranında %1,7'lik, fiyat hareketi olmayan dik bir düşüş
   (bildirim 2026-09-17, ekran görüntüsüyle).
2. *Son noktayı canlı değerle ezmeyi bırakmak.* Grafiğin ucu ile kâr/zarar
   çipi ve ana ekran toplamı ayrışırdı — bu projede tekrar eden ve her
   seferinde güven kıran hata sınıfı.
3. *Kalibrasyon* (seçilen): oransal olan her şey korunur (gün içi şekil,
   dönem yüzdesi, MA20, RSI), yalnızca seviye hizalanır.

**Maliyeti.** İki kalıntı var:
- Gün içi "AÇILIŞ" değeri yurt içi açılış kotasyonu DEĞİL, bugünkü
  çarpanla ölçeklenmiş uluslararası açılıştır. Günlük yüzde uluslararası
  spot'un yüzdesidir; kuyumcu vitrinindeki yüzdeden birkaç onda bir puan
  ayrışabilir.
- Çarpan serinin son barından türetildiği için Yahoo'nun ~15 dakikalık
  gecikmesi de seviyeye karışır; o gecikme içindeki gerçek hareket
  grafikte küçük bir basamak olarak kalır (uçurum değil).

**Ne zaman ele alınmalı.** Yurt içi gün içi altın serisi veren bir kaynak
bulunursa (truncgil yalnızca anlık veriyor) kalibrasyon tümüyle gereksiz
hale gelir — seri doğrudan doğru ölçekten gelir.

**Ayrıca açık:** Takip listesi (`getSymbolHistory` → `watchlist_provider`)
altın için hâlâ KALİBRESİZ (kaynak merdiveni artık ortak, ölçek
kalibrasyonu değil), yani orada gösterilen gram altın fiyatı portföydekinden
birkaç lira farklı olabilir. Bilerek dokunulmadı: o yol sembol bazlı ve saf
geçmiş verisi; canlı kotasyon bağımlılığı eklemek aynı seriyi kullanan
sinyal motorunu da ağ hatasına açar. Kullanıcı iki ekranda farklı fiyat
bildirirse ilk iş burası.

**Ayrıca açık (2):** Ana ekran kartlarındaki sparkline (`SparklineService`)
altın için hâlâ `GC=F` çiziyor, yani TL değil ONS/USD eğrisi. Şekil 0..1
normalize edildiği için ölçek sorunu yok ama TL'deki hareket (kur etkisi)
görünmüyor. Tek satırlık bir değişiklik (`XAUTRY=X`) ama o sembolün
aralıklı boş dönmesi burada yedeksiz kalır ve sparkline tümden kaybolur —
`seriesFor` tek sembollü. Merdiveni buraya da taşımak gerekiyor.

**Ayrıca açık (3):** Hangi kaynağın kullanıldığı yalnızca
`debugSonAltinKaynagi` ile (test gözlemi) görülüyor; üretimde telemetri
yok. Vadeliye düşüş SESSİZ bir bozulma: kullanıcı "bazen oluyor" demeden
fark edilmiyor. "Dış fiyat API'leri sessizce değişiyor; kanarya yok"
maddesiyle aynı aile — çözümü de aynı yerde (fallback'e düşünce Crashlytics
non-fatal / analytics olayı).

**İlgili.** `HistoryService.altinKalibrasyonu`,
`altinKalibrasyonHaritasi`, `test/altin_grafik_olcek_kalibrasyonu_test.dart`,
`test/altin_agirlik_carpani_parite_test.dart`.

---

## 🟡 AÇIK — Performans kartında İKİ nominal getiri var (dönem ve TÜFE)

**Ne.** `PeriodSummary` artık iki nominal taşıyor: `getiriPct` (dönem
kartının sayısı, takvimden türetilen pencere — "son 1 ay" = 16 Ağustos–16
Eylül) ve `tufeNominalPct` (TÜFE karşılaştırmasının sayısı, son açıklanmış
aya kadar — Temmuz sonu–Ağustos sonu). Aynı ekranda birbirinden farklı iki
yüzde görünebilir.

**Neden böyle (2026-09-16).** Tek sayıya indirmenin iki yolu vardı ve
ikisi de daha kötü:

1. *Dönem kartını TÜFE penceresine çekmek.* "Son 1 ay" etiketi bugüne
   kadar gelmeyen bir aralığı gösterirdi; kullanıcı dünkü alımını
   kartta göremezdi.
2. *TÜFE'yi dönem penceresine çekmek.* Ölçülen arızanın ta kendisi:
   endeks aylık yayımlanıyor, ay ortasında biten bir pencere için TÜFE
   YOK. Eskiden bu yüzden farklı aralıklar çıkarılıyordu (1A'da hiç
   kesişmeyen iki pencere).

Karar: iki soru gerçekten farklı, iki sayı da ekranda ve ikisinin de
aralığı YAZILI (`cpiWindowRange`). Kart üç satırı (nominal − TÜFE = fark)
kendi içinde tutarlı ve elle doğrulanabilir.

**Maliyeti.** Dikkatli bir kullanıcı dönem kartındaki yüzde ile reel
getiri kartındaki nominali karşılaştırıp "neden farklı" diye sorabilir.
Aralık satırı cevabı veriyor ama bir tık dikkat gerektiriyor.

**Ne zaman ele alınmalı.** Kullanıcıdan "iki sayı neden farklı" geri
bildirimi gelirse. Çözüm kartta değil ANLATIDA: reel getiri kartına tek
cümlelik "TÜFE aylık yayımlandığı için karşılaştırma son açıklanan ayda
biter" notu. Kod değişikliği gerekmiyor.

**İlgili.** `RealReturnService.piyasaGetirisi`, `InflationService.pencere`,
`test/inflation_window_alignment_test.dart`.

---

## ✅ KAPANDI — Integration workflow'u her push'ta kırıktı: 0054 Vault'suz yığında patlıyordu

**Ne:** `.github/workflows/integration.yml` en az 2026-09-15'ten beri **her
push'ta** ~47 saniyede kırılıyor; `supabase start` adımında `0054`'ün
kendini-doğrulama bloğu hata basıyor:

```
KURULUM EKSIK: ...  ->  select vault.create_secret('<service_role JWT>', 'cron_gateway_jwt');
```

**Neden:** `0054` gövdesinin sonundaki `do $$` bloğu Vault'ta yedi cron
secret'ı + `cron_gateway_jwt` arıyor ve yoksa `raise exception` ediyor. Bu
denetim CANLI için doğru yazıldı — `0054`'ün kendisi "sessizce uygulanmamış
migration" arızasından doğmuştu ve fail-closed olması bilinçli. Ama taze CI
yığınında (`supabase start`, boş Vault) o secret'lar hiç yok; migration
zinciri orada duruyor ve arkasındaki her şey (duman testi, emülatör
`integration_test/`) hiç koşmuyor.

**Maliyeti:** Integration kapısı şu anda hiçbir şey doğrulamıyor — sürekli
kırmızı olduğu için sinyal değeri sıfır. Asıl amacı olan "yeni migration taze
yığında kırılıyor mu" sorusu cevapsız kalıyor ve gerçek bir migration
regresyonu bu gürültünün içinde fark edilmez. CI (`ci.yml`) ve iOS
workflow'ları sağlam, yani kırılma tek bir workflow'la sınırlı.

**Neden ertelendi:** Bu turda (2026-09-15, seçici + rozet + tema salınımı)
kapsam dışıydı; kırılma bu turun getirdiği bir regresyon değil, en az altı
push öncesinden geliyor. Düzeltmek `0054`'ün doğrulama bloğunu ortama duyarlı
yapmayı gerektiriyor ve o blok tam olarak "ortama göre gevşeme" yüzünden
yazılmıştı — dikkatli bir karar, aceleye gelmez.

**Nasıl kapandı (2026-09-15):** Tohum `0054`'ün İÇİNE, doğrulama bloğunun
hemen öncesine kondu — `seed.sql` DEĞİL. Sebep: `config.toml` seed'i
"after migrations" koşuyor, yani `0054` zaten patlamış oluyor ve tohum hiç
çalışmıyordu. İlk önerilen (a) yolu bu yüzden olduğu gibi uygulanamadı.

Tohum satır satır `where not exists` kapısıyla korunuyor: canlıda yedi
secret da mevcut olduğu için orada HİÇBİR ŞEY yazmaz. Bu kritik, çünkü
`vault.create_secret` üzerine yazmaz, YENİ satır ekler (`0034`'ün bulgusu) —
kapı olmasaydı her `db push` mükerrer kayıt üretir ve `order by created_at
desc` sahte secret'ı seçerdi. Ayrıca `0054` canlıda zaten uygulanmış
olduğundan bu düzenleme oraya hiç taşınmaz, yalnızca bundan sonra kurulan
taze yığınları etkiler.

Gateway JWT placeholder'ı üç parçalı JWT biçiminde: doğrulama bloğu regex
ile biçim denetliyor (hex string yazılırsa arıza sessizce geri dönerdi).
Değerler açıkça `local-stack-only` diyor — gerçek secret gibi görünmemeli.

`supabase/tests/cron_auth_test.ts` beş yeni testle sınırı koruyor: kapının
varlığı, tohumun doğrulamadan önce gelmesi, JWT biçimi, placeholder'ın
ayırt edilebilirliği, yedi secret'ın tamlığı. **Deno 261/261 geçiyor.**

**Doğrulandı (2026-09-15):** `supabase start` ilk koşuda geçti.

## Arkasından çıkan beş katman

Vault kapısı açılınca kapının arkasındaki adımlar İLK KEZ koştu ve her biri
bir sonrakini görünür kıldı. Hepsi workflow yazıldığından beri oradaydı ama
`supabase start` hep önce kırıldığı için hiç görülmemişti:

1. **`\` satır devamı çalışmıyor.** `android-emulator-runner` `script`
   bloğunu satır satır ayrı `sh -c` çağrılarıyla koşuyor; kabuk devam
   satırı hiç birleşmiyor. Flutter argüman olarak bir `\` alıyor, onu test
   yolu sanıyor ve `_shouldRunAsIntegrationTests` "Integration tests and
   unit tests cannot be run in a single invocation" diyordu. Mesaj sebebi
   hiç göstermiyor — beş hipotez (dizin/dosya yazımı, eğik çizgi, fazladan
   `_test.dart`, cihazın görünmemesi, `-d` eksikliği) ölçülerek elendi.
   Komut tek satıra indirildi.
2. **Tür çipi: bekleme + kaydırma.** Ekran açılır açılmaz `tap`
   çağrılıyordu; çipler `HScrollWithFade` içinde ve "Diğer" son sırada.
   `_bekle` + `ensureVisible`.
3. **Tanıtım turu katmanı.** `OnboardingTourHost` Navigator'ı sarıyor
   (kasıtlı) ve tur açıkken dokunmaları yutuyor.
   `OnboardingScreen.turuKapatTestIcin()` eklendi (`@visibleForTesting`).
4. **Semantics etiketi eşleşmiyor.** `find.bySemanticsLabel('Diğer türü')`
   CI'da hiç tutmadı; teşhis ekranın açık, çiplerin yerinde ve dilin Türkçe
   olduğunu gösterdi. Finder metne çevrildi (`find.text('Diğer').first`).
   ⚠️ **Sebep ÇÖZÜLMEDİ, etrafından dolaşıldı** — o etiket erişilebilirlik
   için gerekliyse ayrı bir widget testi yazılmalı.
5. **`SemanticsHandle` dispose.** Akışın tamamı geçtikten sonra yalnızca
   temizlikte düşüyordu: `addTearDown` yetmiyor, çünkü tearDown'lar gövdeden
   SONRA koşuyor ama handle denetimi gövde biter bitmez yapılıyor.

**Sonuç:** Integration yeşil — `supabase start` ✓, başsız duman ✓,
emülatörde `integration_test/` ✓ (`🎉 1 test passed`). Kapı artık gerçekten
bir şey doğruluyor.

## Ders

Hata mesajı sebebi göstermediğinde tahmin turu pahalı. Dönüm noktası
`_bekle`'ye teşhis çıktısı eklemekti (ekrandaki metinler + ModalBarrier
sayısı + semantics etiketleri); o tek değişiklik dört hipotezi birden
eledi. Teşhis satırları BIRAKILDI — bir sonraki kırılmada aynı bilgi
ücretsiz gelir.

## 🟢 BÜYÜK ÖLÇÜDE KAPANDI — Dış fiyat API'leri sessizce değişiyor; kanarya yok

**2026-09-19 — üç öneri de kuruldu (dal `feat/aciliyet-turu-2026-09-19`):**
1. `_shared/kanarya.ts` — `check-price-alerts` alarm varken fiyat map'i boş
   dönerse `console.error` + `db_logs` (`op='kanarya'`, `is_error`) + `push_admins`'e
   push (12 saatte en çok bir kez, `kanaryaBildirilmeliMi`; test `kanarya_test.ts`).
   Yanıta `kanarya` alanı eklendi; `"sent":0` ile ayırt edilir.
2. `.github/workflows/price-canary.yml` — Pazartesi 07:00 UTC gerçek truncgil'e
   `supabase/canary/truncgil_canary_test.ts` (anahtarlar, gram eşdeğeri, ölçek).
   `supabase/tests/` DIŞINDA: CI kapısı dış servise bağımlı olamaz.
3. `test/altin_anahtar_paritesi_test.dart` — `_truncgilGoldKeys` ↔ `GOLD_KEYS`
   kaynak paritesi; `ALTIN_GRAM == YIA` ayrıca kilitli.

**Kalan (bilinçli):** istemci tarafındaki Yahoo `GC=F` yedeğine düşüş hâlâ sessiz
(kullanıcı fark etmez, sayı yalnızca kaynakla tutmaz). Ölçek hafızası bunu
yumuşatıyor; Crashlytics non-fatal "yedek kaynağa düşüldü" olayı ayrı bir tur.

### Karar kaydı (2026-09-15)


**Ne:** `finans.truncgil.com/v4/today.json` 2026-09-15'te üç şeyi birden
değiştirdi — altın anahtarları (`'Gram Altın'`→`'GRA'`), alan adları
(`'Alış'`→`'Buying'`), sayı tipi (string→number). Sonuç: `fetchLivePrices`
boş map döndürdü, `check-price-alerts` **her turda** `"Fiyat alinamadi."`
dedi ve fiyat alarmı özelliği tümüyle öldü. Kod düzeltildi (iki taraf:
edge function + `PriceService`), ama **asıl borç düzeltmenin kendisi değil.**

**Asıl borç:** Bu arıza HTTP 200 ile dönüyordu ve **hiçbir yerde
bağırmıyordu.** Kaç tur boyunca ölü kaldığı bilinmiyor — kimse
`net._http_response`'a bakmadığı sürece görünmezdi. `0054`'ün sessiz
arızasıyla aynı sınıf, bu sefer veri katmanında:

- `fetchLivePrices` kaynak hatasını `catch (_)` ile yutuyor (bilinçli:
  tek sembol tüm turu düşürmesin) — ama **hepsi** başarısız olduğunda da
  aynı sessizlik geçerli.
- `"Fiyat alinamadi."` bir *reason* string'i, bir alarm değil. `sent: 0`
  meşru bir sonuç olduğu için (piyasa kapalı, eşik geçilmemiş) izleme
  tarafında ikisi ayırt edilemiyor.
- İstemcide daha da sinsi: altın Yahoo `GC=F` + ons/gram çevrimi yedeğine
  düşüyordu. **Yedek çalıştığı için belirti yoktu** — yalnızca gösterilen
  sayı kaynakla tutmuyordu.

**Maliyet:** Alarmlar bozulunca kullanıcı bunu bize söyleyemez — "alarm
kurmuştum, gelmedi" ile "henüz hedefe ulaşmadı" onun için aynı görünür.
Güven kaybı sessiz birikir.

**Ne zaman:** Yayın öncesi değil ama ilk izleme turunda. Öneriler
(en ucuzdan pahalıya):

1. `check-price-alerts` alarm sayısı >0 iken fiyat map'i BOŞ dönerse
   `console.error` + Crashlytics non-fatal — "0 alarm var" ile
   "alarm var ama fiyat yok" ayrılır.
2. Sözleşme testi: gerçek API'ye haftalık bir smoke (CI'da `deno test
   --allow-net`, `main` dışı) — anahtar/alan adı değişimini biz fark
   edelim, kullanıcı değil.
3. `_shared/live_prices.ts` ↔ `PriceService` eşitliğini tutan parite
   testi: iki taraftaki `GOLD_KEYS` / `_truncgilGoldKeys` sabitleri
   ayrışırsa test kırılsın (bugün ayrışmaları sessizdi).

**İlgili:** `supabase/tests/price_alert_test.ts` v4 regresyonunu tutuyor
(anahtarlar canlı yanıttan alındı), ama o yalnızca BUGÜNKÜ biçimi korur —
API bir daha değişirse yine sessiz kalır. Kanarya bunun için gerekli.

---

## ✅ KAPANDI — TÜFE serisi Ocak 2026'da bitmişti: yeni baz yılına geçildi

**Ölçüldü 2026-09-14, canlı veriyle.** `inflation_index` artık dolu (29
satır, Eylül 2023 – **Ocak 2026**) ama **Şubat–Ağustos 2026 eksik** ve
kendiliğinden gelmeyecek.

**Sebep:** TÜİK, Ocak 2026'da TÜFE baz yılını `2003=100`'den `2025=100`'e
çevirdi (AB uyumu, ECOICOP v2). Fonksiyonun çektiği `TP.FG.J0` serisi ESKİ
baz — o ayda sona erdi. EVDS 36 aylık pencerede bile Ocak 2026'dan sonrasını
döndürmüyor (`written: 29, latest: 2026-01-01, reason: no_new_data`).

**Bu turda kapatılan iki ayrı arıza (ikisi de birbirini gizliyordu):**

| Arıza | Durum |
|---|---|
| `0054` hiç koşmamıştı → 7 tetikleyici 401 alıyordu | ✅ kapandı |
| Vault'ta 2 cron secret eksikti | ✅ kapandı |
| EVDS adresi `evds2` → `evds3` taşınmıştı (HTML dönüyordu) | ✅ kapandı |
| EVDS parametreleri path-style istiyor, `?query` 404 | ✅ kapandı |
| **Seri kodu eski baz yılına ait** | 🟠 **AÇIK** |

**KAPANDI 2026-09-14.** Yeni seri kodu EVDS3 kataloğundan **okundu**,
tahmin edilmedi — fonksiyonun kendi `catalog` moduyla (anahtar yalnızca
sunucuda olduğu için dışarıdan sorgulanamıyor):

```
kategori 2005  "TÜKETİCİ FİYAT ENDEKSİ (TÜİK)"
  └─ grup bie_tukfiy2025  "Tüketici Fiyat Endeksi (2025=100)"
       └─ TP.TUKFIY2025.GENEL  "Genel Endeks"  01-2005 … 08-2026
```

Tablo temizlenip yeni bazla dolduruldu: **24 satır, Eylül 2024 – Ağustos
2026**, `source = TUIK-TP.TUKFIY2025.GENEL`. Eski satırların yedeği alındı
(kamuya açık istatistik, kullanıcı verisi değil).

**Kabul ölçütü karşılandı** — canlı veriyle doğrulandı:

| Dönem | Hesaplanan | TÜİK |
|---|---|---|
| Aylık (Ağustos 2026) | **%1,84** | %1,84 ✓ |
| Yıllık (Ağu 25 → Ağu 26) | **%31,51** | %31,51 ✓ |
| 6 aylık | %13,08 | — |

Kalıcı korumalar: `EVDS_SERIES` artık gövdeden geçilebiliyor (`series`
parametresi + `dry_run`, deploy gerektirmeden aday kod denenebilir),
`source` etiketi seri kodundan türetiliyor (baz ayrımı kanıtlı),
`parseEvds` seri kodunu parametre alıyor ve üç yeni Deno testi bunu
kilitliyor.

### Bir daha yaşanırsa — bu arıza baz kırılması denetimine TAKILMADI

Öğrenilen ders: TÜİK yeni seriyi **ayrı bir kod altında** yayımladı,
eskisini olduğu yerde bıraktı. Yani endeks düşmedi — `bazKirilmasiVarMi`
hiç tetiklenmedi. Sadece **yeni ay hiç gelmedi**: fonksiyon `no_new_data`
döndü, tablo dolu göründü, kimse fark etmedi.

Belirti: *"tablo dolu ama son satır aylardır aynı"*. Teşhis yolu ve
katalog gezinme komutları `supabase/functions/fetch-inflation/README.md`
→ "Katalog keşfi" bölümünde.

İkinci koruma istemcide: `InflationService.isStale` son satır 2 aydan
eskiyse reel getiriyi hesaplamıyor ve ekran "TÜFE verisi henüz
yüklenmedi" diyor — bayat endeksle yanlış bir yüzde göstermektense hiç
göstermemek.

---

## ✅ KAPANDI — Migration defteri "uygulandı" diyor ama gövde koşmamıştı

**Ölçüldü 2026-09-14, canlı veritabanında.** `supabase migration list`
`0054`'ü uygulanmış gösteriyordu; gerçekte:

| Kontrol | Beklenen | Bulunan |
|---|---|---|
| `cron_headers` fonksiyonu | var | **YOK** |
| `cron_gateway_jwt` fonksiyonu | var | **YOK** |
| `cron_secret_of` fonksiyonu | var | **YOK** |
| 7 tetikleyici deseni | `cron_headers(...)` | hepsi **eski desen** |
| `net._http_response` | 200 | **401 INVALID_JWT_FORMAT** |

Yani `0054`'ün düzelttiği arıza hiç düzelmemiş; üstelik `0054`'ün ASIL
DERSİ (sessiz başarısızlık) bir kez daha tekrarlanmış — bu sefer
migration'ın kendisinde.

**Kök sebep:** defter kaydı gövdeden bağımsız yazılabiliyor
(`supabase migration repair --status applied`). Bir migration SQL Editor'den
elle koşulup yarıda kaldığında ya da repair yanlış kullanıldığında defter
"uygulandı" der ve `db push` bir daha denemez. `0054` kendi içinde
`do $$` doğrulama bloğu taşıyor ama **o blok hiç çalışmadığı için**
patlayamadı da.

**Neden buradaki diğer maddelerden ciddi:** sessizce ölü olan şey yedi cron
işi — TÜFE çekimi, sabah brifingi, haftalık özet, fiyat alarmları, takvim
kancası, sinyal analizi. Hepsi "kurulu ve aktif" görünüyor
(`cron.job.active = true`), hiçbiri iş yapmıyor.

**Yapılacak:** `0054`'ü gerçekten koş (`YAPMAN_GEREKENLER.md` #20). Sonra
**defter yerine ŞEMAYA sor** — kalıcı çözüm bu:

```sql
-- Deftere değil, fonksiyonun gövdesine bak.
select proname, pg_get_functiondef(p.oid) ~ 'cron_headers' as yeni
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and proname like 'trigger_%';
```

**KAPANDI 2026-09-14.** `0054` SQL Editor'dan elle koşuldu ve şemadan
doğrulandı: yedi tetikleyicinin yedisi de `cron_headers` desenine geçti,
üç yardımcı fonksiyon oluştu. İlk denemede `0054`'ün doğrulama bloğu
Vault'ta eksik iki secret'ı (`calendar_nudge_cron_secret`,
`price_alerts_cron_secret`) yakalayıp işlemi geri aldı — yani **kendi
kendini doğrulama tasarımı çalıştı**; o iki kayıt yazıldıktan sonra geçti.

⚠️ `db push --include-all` bu işi YAPMAZ: defterde "uygulanmış" görünen
bir migration'ı yeniden koşmaz. Aynı durumla karşılaşılırsa SQL Editor'dan
elle koşmak ya da `migration repair --status reverted` gerekir.

**Önleme fikri (ayrı bir tur):** CI'a "şema gerçekten beklenen hâlde mi"
denetimi. Migration defteri bir NİYET kaydı; tek gerçek kaynak şemanın
kendisi.

---

## ✅ KAPANDI — Yatırımcı karşılaştırması medyan farkı ve metrik etiketi taşımıyor

**KAPANDI 2026-09-14** (madde 1 ve 2; madde 3 TWR bilinçli tercih olarak
kalıyor). `0061_percentile_median.sql`: `get_percentile_bucket` DROP + CREATE
ile `median_roi_pct` ve `my_roi_pct` sütunlarını da döner (havuz, k_min=8,
Sybil kapısı 0059 ile aynı; medyan 1 ondalığa yuvarlanır). İstemci
`PercentileBucket.medianDiffPts` alanını OPSİYONEL okur — sunucu 0061'den
eskiyse şerit medyansız çizilir. Şerit altına "Getiri sıralaması · medyandan
4,2 puan önde/geride" satırı geldi; metriğin adı artık ekranda.
`percentile_strip_test` 0061 sözleşmesini kilitler. **Deploy sende**
(`YAPMAN_GEREKENLER.md` #22).

`get_percentile_bucket` (migration `0012`) yalnızca `(percentile,
total_participants)` döndürüyor. Özet sekmesindeki benchmark şeridi bu
yüzden "ilk %X'tesin" diyebiliyor ama **medyana ne kadar uzakta olduğunu
söyleyemiyor.**

Eksik olan üç şey:

1. **Medyan farkı.** RPC havuzun medyan ROI'sini dönmüyor. Kullanıcı kendi
   yüzdelik dilimini görüyor ama "medyandan 4,2 puan öndeyim" gibi
   kavraması kolay olan cümleyi göremiyor.
2. **Metriğin adı.** Sıralama getiri bazlı (`LeaderboardService`
   simülasyon-ROI'si) ve portföy BÜYÜKLÜĞÜ sıralaması hiç yok — bu doğru
   tercih. Ama ekran hangisine baktığını YAZMIYOR; kullanıcı "ilk %12"nin
   büyüklük mü getiri mi olduğunu bilmiyor.
3. **Metrik TWR değil.** Simülasyon-ROI dönem içi alım/satımı yok sayıyor
   (gerekçesi `LeaderboardService` sınıf notunda, yarış için bilinçli
   tercih). Gerçek TWR her lot için tarihsel nakit akışı ister; veri modeli
   `addedDate` dışında ara değerleme taşımıyor.

**Neden şimdi yapılmadı:** 1 ve 2 bir migration gerektiriyor (RPC imzası
değişir, `k_min = 20` anonimlik eşiği korunmalı) ve dönüş tipini değiştirmek
istemcinin eski sürümlerini kırar — `fetchPercentile` yeni alanı opsiyonel
okumalı. Bu tur istemci tarafında kapatılabilecek maddelere ayrıldı.

**Maliyeti:** karşılaştırma kartı bugün doğru ama eksik bilgi veriyor;
yanlış bir şey göstermiyor.

**Ne zaman:** medyan farkı, RPC'ye dokunulacak bir sonraki turda. Metriğin
adı (madde 2) migration İSTEMİYOR — şerit metnine "getiri sıralaması"
ibaresi eklenerek bugün kapatılabilir.

---

## 🟡 AÇIK — İngilizce arayüz BETA: dört ada kasıtlı Türkçe, varsayılan dil Türkçe

**Karar tarihi:** 2026-09-14 · 3.20 · **Kapsam genişletildi 2026-09-15**

Sözlük 780+ anahtar; `l10n_coverage_test` 87 ekran/widget dosyasını yalnızca-
azalır tavanlarla bağlıyor ve **47'si sıfır Türkçe literal taşıyor**. Giriş,
kayıt, gezinme, ana ekran, Portföy, Performans (+7 part), Özet kartlarının
tamamı, tekil varlık, Yarış, Takip listesi, Karşılaştırma, Ayarlar, Profil,
Paywall, Yıllık Özet, tüm diyaloglar ve şeritler çevrildi. Kalan 212 literal
41 dosyaya yayılmış küçük etiketler.

**Kasıtlı Türkçe kalan dört ada (tavana hiç alınmadı):**

| Ada | Neden |
|---|---|
| `legal_doc_screen` (261) | Yasal metinlerin kendisi; çevirisi hukuk işi, mühendislik değil. |
| `asset_categories` (218) | Alt kategori etiketleri `sub_category` sütununda **VERİ** olarak saklanıyor (`_subCategory == g.label` karşılaştırmaları dahil). Çevirmek kayıtlı satırları bozar; gösterimi ayırmak için `AssetType.labelOf` deseninde ikinci bir eşleme gerekir. |
| `push_diagnostics_screen` (112) | Yalnız admin'e görünen teşhis aracı. |
| `onboarding_screen` (72) | Tanıtım turu; tek seferlik, ayrı bir tur. |

**Varsayılan dil neden hâlâ Türkçe:** yukarıdaki dört ada duruyorken sistem
diline bağlamak, İngilizce cihazlı kullanıcıya ilk açılışta Türkçe bir
tanıtım turu gösterirdi. İngilizce, Ayarlar › Görünüm'den bilinçli seçim.

**Ertelemenin maliyeti:** İngilizce seçen kullanıcı tanıtım turunda, yasal
belgelerde ve altın/fon alt kategori adlarında Türkçe görür. Mağaza
sayfasında "tam İngilizce arayüz" vaadi henüz verilmemeli.

**Ele alınma zamanı:** EN pazarı hedeflenirse sırayla onboarding →
alt kategori gösterim eşlemesi → yasal metinler (hukuk onayıyla). Hepsi
bitince `LocaleNotifier` varsayılanı `system` olur ve `languageNote` kalkar.

---

## ✅ KAPANDI — Yatırımcı seviyesine göre görünüm yok

**KAPANDI 2026-09-14.** Sunucuda alan açmadan, zorunlu onboarding eklemeden:
Ayarlar › Görünüm'de OPSİYONEL "Yatırımcı seviyesi" (Başlangıç / Orta /
İleri; `PrefKeys.investorLevel`, kişiye özel, varsayılan **Orta = bugünkü
görünüm**). Karar tablosu tek yerde (`seviyeGorunurlugu`,
`models/yatirimci_seviyesi.dart`): Başlangıç sağlık/XIRR/yüzdelik kartlarını
GİZLER; İleri, Orta'nın üstüne `IleriMetrikKarti` EKLER — risk-ayarlı getiri
(getiri ÷ yıllık oynaklık, risksiz oransız Sharpe; TL risksiz oranı
uygulamada tutulmadığı için tanım açıkça yazılı), zamanlama etkisi (XIRR −
piyasa getirisi) ve toparlanma (en büyük düşüşten zirveye dönüş günü).
Üçü de zaten hesaplanan girdilerden türetilir; kart yeni veri çekmez.
Gereksinimdeki "attribution" ve "takip hatası" YOK: ikisi de benchmark
serisi ister (BIST100/TÜFE'ye göre izleme hatası), karşılaştırma ekranı
ayrı bir tur. `yatirimci_seviyesi_test` (12).

Ürün gereksinimi başlangıç / orta / ileri seviye için farklı metrik kümesi
öngörüyordu (ileri seviyede attribution, takip hatası, risk-ayarlı
performans).

**Yapılmadı çünkü** kullanıcı profilinde deneyim seviyesi alanı YOK
(`user_model.dart`, `preferences_provider`) ve gereksinimin kendisi "yoksa
yeni zorunlu onboarding ekleme" diyor. Seviye sormadan seviyeye göre
gizlemek, uydurulmuş bir sınıflandırma olurdu.

Bugünkü karşılığı: kartlar **verisi olduğunda** görünüyor. Yeni kullanıcıda
sağlık ve XIRR kartları zaten çizilmiyor (yeterli geçmiş yok), bir yıllık
kullanıcıda kendiliğinden beliriyor. Kademeli açılma seviye sorusu sormadan
sağlanıyor.

**Ne zaman:** Profil'e opsiyonel bir tercih eklenirse. Zorunlu onboarding
adımı olarak ASLA.

---

## ✅ KAPANDI — TÜFE grafiğe endeks çizgisi olarak binmiyor

**KAPANDI 2026-09-14.** "Aylık basamak kabul edilebilirse stepped line + etiket"
çözümü uygulandı, ama performans ekranının TL eksenine değil KARŞILAŞTIRMA
ekranına: orada her seri zaten yüzdeye normalize. `TufeSeries.ticker`
(`TUFE:INDEX`) bir kıyas çipi olarak eklendi ("Portföyüm" + "TÜFE" = sorunun
görsel cevabı); `PercentComparisonChart.steppedKeys` ile basamaklı çizilir,
etiketi "TÜFE (aylık)". Ara gün üretilmez; son açıklanan ay bugüne kadar
sabit taşınır — basamağın sözü tam olarak bu. 1H'de iki noktadan az kalır
ve satır "yeterli veri yok" der; aylık göstergeyi haftalık pencerede
çizmek zaten anlamsız.

Reel getiri artık kart olarak tam (bileşik reel getiri + nominal + kümülatif
TÜFE + puan farkı, `_ReelGetiriKarti`). Ama Grafik sekmesinde portföy
eğrisinin üzerine TÜFE endeksi ÇİZİLMİYOR.

**Neden ertelendi:** iki seri farklı ölçekte (portföy TL, TÜFE endeks) ve
aynı eksene basmak gereksinimin kendi yasakladığı şey. Doğru yol
`percent_comparison_chart`'ın normalize-100 modu — o bileşen var ama
TÜFE'nin AYLIK çözünürlüğü portföyün günlük/5dk serisiyle aynı eksende
basamaklı bir merdiven çizerdi. Ara değerleri interpolasyonla doldurmak,
TÜİK'in açıklamadığı bir sayı üretmek olur.

**Maliyeti:** karşılaştırma sayı olarak tam, görsel olarak yok.

**Ne zaman:** aylık basamağın kabul edilebilir olduğuna karar verilirse
(`stepped line` olarak çizip etiketinde "aylık yayımlanır" demek dürüst bir
çözüm olabilir).

---

## ✅ KAPANDI — Cron çağrıları API gateway'de 401 alıyordu (SESSİZ)

**Bulunma tarihi:** 2026-09-14 · **Kapanış:** aynı gün ·
`0054_cron_auth_header.sql`

Borç kaydı olarak hiç açılmamıştı — **bilinmiyordu**. Haftalık özetin
canlı doğrulaması sırasında ortaya çıktı.

**Belirti:** `daily_brief_log` Mayıs 2026'dan beri BOŞTU. Sabah brifingi
hiç gönderilmemişti. `calendar_nudge_log` ve `weekly_summary_log` de boş.

**Sebep:** Supabase API gateway, isteği edge function'a iletmeden ÖNCE
`Authorization` header'ını JWT olarak ayrıştırıyor. Yedi tetikleyicinin
hepsi oraya rastgele hex bir cron secret koyuyordu
(`0017`'den beri süregelen desen), gateway bunu JWT sanıp isteği fonksiyona
**hiç ulaştırmadan** reddediyordu:

```
401 {"code":"UNAUTHORIZED_INVALID_JWT_FORMAT","message":"Invalid JWT"}
```

**Neden dört ay fark edilmedi** — her gösterge yeşildi:

| Nereye bakılırsa | Ne görünürdü |
|---|---|
| `cron.job` | iş kurulu, zamanlama doğru ✓ |
| `cron.job_run_details` | koşu başarılı ✓ (pg_net isteği kuyruğa aldı) |
| Edge function logları | **boş** — fonksiyon hiç çalışmadı |
| `net._http_response` | 401 — **tek görünür yer** |

`live-activity-refresh`'in çalışmasının tek sebebi Vault'undaki değerin
rastgele bir string değil, 219 karakterlik gerçek bir service_role JWT'si
olmasıydı. Yani tek çalışan iş, yanlışlıkla doğru header'ı taşıyordu.

**Çözüm:** `Authorization` gateway'e (service_role JWT), cron secret'ı
`x-cron-secret` header'ına. İki katman korundu. Fonksiyon tarafında
`_shared/cron_auth.ts`, SQL tarafında `public.cron_headers(secret_adi)` —
header deseni bir daha değişirse dokunulacak tek yer.

Reddedilen iki alternatif: `verify_jwt = false` (gateway katmanı tamamen
kalkardı) ve Vault'a cron secret'ı OLARAK service_role JWT yazmak
(fonksiyon başına izolasyon kaybolurdu — tek sızıntı tüm DB'yi açar).

**Yanında kapanan:** `daily_brief`, `calendar_nudge`, `price_alerts` ve
`live_activity` tetikleyicileri `timeout_milliseconds` bayrağını hiç
almamıştı — `0040`'ın belgelediği 5 saniye tuzağına açıktılar. Dördüne de
verildi.

**Regresyon kapısı:** `supabase/tests/cron_auth_test.ts` (41 test). Eski
desenin geri sızmasını ve yeni desenin eksiksizliğini iki yönlü
doğruluyor. Belge: `supabase/functions/_shared/CRON_AUTH.md`.

**Kurulum bağımlılığı:** `cron_gateway_jwt` Vault kaydı GEREKLİ — migration
onu yazamaz (service_role key'i SQL içinden okuyamaz ve repoya girmemeli).
Yoksa `0054` açık hatayla durur; sessiz düşmemesi kasıtlı.

---

## ✅ KAPANDI — google_fonts bağımlılığı yalnızca TextStyle üreticisi olarak duruyor

**Karar tarihi:** 2026-09-13 · Değerlendirme raporu §2/Faz 1.9 · **Kapandı 2026-09-14:**
bağımlılık kaldırıldı; `kSandikFontFamily` + `sandikFont(...)` (`lib/theme/sandik.dart`),
tema `apply(fontFamily:)` ile bağlandı, `bundled_font_test` paketin geri gelmediğini ve
aile adının tek kaynaktan geldiğini kilitliyor.

DM Sans 6 ağırlıkla `assets/fonts/` altında gömülü ve `main.dart:118`
`allowRuntimeFetching = false` diyor. `google_fonts` paketi hiçbir şey
indirmiyor; yalnızca `GoogleFonts.dmSans(...)` (35 çağrı) ve
`dmSansTextTheme` ile `fontFamily: 'DM Sans'` yazmanın uzun yolu.
Aile adının paketin ürettiğiyle birebir eşleşme zorunluluğu (pubspec
yorumu) kırılgan bir bağ.

**Neden ertelendi:** 35 çağrı yerinin mekanik değişimi kolay ama
`bundled_font_test.dart` google_fonts API'sine bağlı; analyzer/test
koşulmadan yapılan bir bağımlılık kaldırma CI'ı kırma riski taşıyor.
**Maliyet:** bir bağımlılık + asset-manifest makinesi + runtime-fetch
tuzağı. **Ne zaman:** CI (`ci.yml`) yeşil görüldükten sonraki ilk tur;
`GoogleFonts.dmSans(` → `TextStyle(fontFamily: 'DM Sans', ` ve
`dmSansTextTheme(x)` → `x.apply(fontFamily: 'DM Sans')`, test yeniden
yazılır.

---

## ✅ KAPANDI — analysis_options.yaml dokunulmamış şablon, flutter_lints 4.x

**Karar tarihi:** 2026-09-13 · **Kapandı 2026-09-14:** `flutter_lints` 6.0, `strict-casts` /
`strict-inference` / `strict-raw-types`, `unawaited_futures` (42 ateşle-unut çağrısı
`unawaited(...)` ile niyetlendirildi), `prefer_final_locals`, `empty_catches`. Analyzer 0 sorun.
**Açık kalan tek kural:** `avoid_dynamic_calls` — 127 site, çoğu Supabase JSON satırı
(`row['x']`); tipli DTO'lar gelene kadar kapalı (gerekçesi `analysis_options.yaml`'da).

`include: package:flutter_lints/flutter.yaml` + boş `rules:`. Güncel
6.x iki majör ileride; `strict-casts`, `unawaited_futures`,
`avoid_dynamic_calls` kapalı. Kod tabanında yalnızca 3 `// ignore:`
var — muhtemelen sıkılaştırmayı sorunsuz kaldırır ama 62k satırda
hangi kuralın kaç yerde patlayacağı analyzer koşmadan bilinemez.
**Ne zaman:** CI yeşil olduktan sonra, tek commit'te; `unawaited_futures`
tek başına servis katmanındaki ateşle-unut çağrıları yüzeye çıkarır.

---

## 🟢 BÜYÜK ÖLÇÜDE KAPANDI — leaderboard_screen'de 5 bağımsız canlı tick timer'ı

**Karar tarihi:** 2026-09-13 · **2026-09-14:** Yarış kalıyor kararıyla beş `Timer.periodic`
`ForegroundPoller`'a geçti: arka planda dururlar, öne gelince hemen bir tur atarlar, yavaş
ağda turlar üst üste binmez. **Kalan:** beş widget hâlâ birbirinden habersiz (TTL önbelleği
ağı sınırlıyor); tek `Notifier`'a toplama ayrı bir tur.

`_liveTick` 15/15/30/45 sn (ekran) + 30 sn (hero kart) — her biri kendi
`setState(() => _future = ...)` döngüsünü kuruyor. `LeaderboardService`
TTL önbelleği ağ maliyetini sınırlıyor ama beş widget birbirinden habersiz
yeniden hesaplıyor ve hiçbiri arka planda durmuyor.
**Neden ertelendi:** Yarış özelliğinin kendisi Faz 3.12 kararına bağlı
(DAU ≥ 2×k_min ve Sybil çözümü olmadan kapalı). Kapatılacak bir ekranın
timer mimarisini yeniden kurmak boşa efor.
**Ne zaman:** Yarış açılma kararıyla birlikte; `ForegroundPoller`
(`lib/utils/polling.dart`) hazır, tek `Notifier` ile beş future tek
yerden tazelenir.

---

## ✅ KAPANDI — Özet sekmesinde 6A yüzdelik dilimi bağlı değil

**Kapanış:** 2026-09-13 · Migration `0051_percentile_180d.sql` + ekran
tarafı bağlandı (`_OzetYanVeri._yukleDilim`).

Borç kaydı işi "RPC'ye `period_days` parametresi eklenmeli" diye
tanımlıyordu; **gerçek engel daha aşağıdaydı.** Üç yer birden kapalıydı
ve biri açılıp öteki kalsa özellik SESSİZCE çalışmazdı:

| Yer | Engel |
|---|---|
| `user_roi_snapshots` | `CHECK (period_days IN (7,30,365))` — 180 satırı hiç yazılamıyordu |
| `get_percentile_bucket` | allowlist `NOT IN (7,30,365)` → boş dönüyordu |
| `get_top_gainers_allocation` | aynı allowlist; ayrışsa Yarış listesi 180'de boş kalırdı |

**Parametre EKLENMEDİ, kova eklendi.** `get_percentile_bucket`'a yeni bir
argüman vermek imzayı değiştirir ve `CREATE OR REPLACE` eski
1-argümanlı fonksiyonu kendi GRANT'leriyle ayakta bırakır (overload,
replace değil). Allowlist'i genişletmek aynı sonucu imza değiştirmeden
veriyor.

**"180 kovası hiç dolmaz" endişesi ölçüldü ve yanlış çıktı.** `k_min`
8'e indirilmişti çünkü taban 20 aktif/gün eşiğine ulaşmıyor (bkz.
`0031`); 180 kovasının en seyrek kalacağı düşünülmüştü. Ama
`donemGetirisiPct` seriyi `simulate: true` ile üretiyor — bugünkü net
pozisyon dönemin tamamına yayılıyor, yani kullanıcının 180 gündür varlık
TUTMASI gerekmiyor, yalnızca sembollerinin 180 günlük fiyat geçmişi
gerekiyor. Kova 30 günlükle neredeyse aynı kümeden besleniyor.
`k_min = 8` ve `n_max = floor(k_min/2) = 4` değişmezine dokunulmadı.

`percentile_strip_test` içindeki yeni grup üç şeyi kilitliyor: iki RPC
allowlist'inin ayrışmaması, k_min/n_max çiftinin korunması ve istemcinin
6A gün sayısının (`SummaryPeriod.altiAy.days`) sunucu kovasıyla aynı
kalması. Allowlist sessiz bir kapı — testsiz bıraksak drift fark
edilmezdi.

**Migration koşuldu** (2026-09-13) ve canlıda üç yerin de açık olduğu
uzak veritabanına sorguyla doğrulandı; 180 insert'inin CHECK + RLS +
throttle trigger'ını geçtiği `rollback`'li denemeyle görüldü.

Şerit hâlâ görünmüyor çünkü havuzda tek kullanıcı var (k=8 eşiği) —
doğru davranış, ayrıntı `YAPMAN_GEREKENLER.md`'de.

---

## ✅ KAPANDI — Özet 1Y bloğunda paylaş butonu bağlı değil

**Kapanış:** 2026-09-13 · `RecapService.composeShareText` ortak
çekirdeği + `PeriodSummaryService.shareText` delegasyonu.

Borç kaydı `shareText(period, pct, etiket)` imzasını öneriyordu; uygulanan
biçim **skaler parametreli** bir çekirdek:
`composeShareText({baslik, karakter, degisimPct, degisimEtiketi,
enflasyonPuan, takipGunu})`.

**Ortak arayüz/taban sınıf UYDURULMADI.** İki veri şekli örtüşmüyor:
`RecapData.character` zorunlu ve `trackedDays` var; `PeriodSummary`'de
karakter ayrı bir parametre (ekranda öyle geliyor) ve takip günü kavramı
hiç yok. Yalnızca bu metin için yapay bir hiyerarşi kurmak ikisini de
karmaşıklaştırırdı.

**TUTAR İÇERMEME kuralı artık YAPISAL:** imza TRY taşıyan hiçbir alan
kabul etmiyor, dolayısıyla çağıran taraf yanlışlıkla tutar geçemiyor.
Aynı sebeple dönem başlığında TARİH ARALIĞI yok — yıl içeren dört haneli
sayılar paylaşılan metinde tutar gibi okunuyor ve `recap_service_test`'in
"dört haneli sayı tutar demektir" iddiası tam olarak bunu kovalıyor.

Mevcut recap paylaşım testleri dokunulmadan geçti (refactor davranış
koruyor); `period_summary_test` içine aynı kuralı ikinci çağıran için
kilitleyen 8 test eklendi.

---

## 🟢 BÜYÜK ÖLÇÜDE KAPANDI — Net miktarı 0'a düşmüş varlık ham listede yaşamaya devam ediyor

**Kapanış:** 2026-09-12 · `aktifLotlar(...)` ortak yardımcısı eklendi
(`lib/models/position.dart`) ve doğrulanmış sızıntılar ona bağlandı:

| Yer | Belirti |
|---|---|
| `price_alerts_screen` | Satılmış hisse hâlâ alarm adayıydı (borç kaydında "doğrulanmadı" notu vardı — DOĞRULANDI) |
| `add_watchlist_screen` | Satılmış hisse "zaten portföyünde" diye takip listesine EKLENEMİYORDU |
| `asset_detail_screen` | Satılmış varlık karşılaştırma listesinde çıkıyordu |

**Yöntem — `deletedAt` DEĞİL, okuma tarafı.** Kullanıcı önce soft-delete
istedi; borç kaydındaki uyarı gösterildikten sonra okuma tarafı seçildi.
Kapanmışlık DB'ye YAZILMIYOR, `aggregatePositions` üzerinden okuma anında
türetiliyor. Alım lot'una `deletedAt` basmak `isActive`'i false yapar ve
satıştan önceki dönem grafikten + periyot hesaplarından kaybolurdu.

`aktifLotlar_test.dart` bu değişmezi ayrıca kilitliyor: kapanmış
pozisyonun lot'ları silinmez ve `deletedAt` null kalır. Sabotajla
doğrulandı — `deletedAt` ile çözmeye çalışan sürüm testi kırıyor.

**Kalan:** sistematik denetim yapılmadı. `.assets` gezen 28 çağrı
yerinin tamamı tek tek incelenmedi; yalnızca "bugünkü mülkiyet" soran
üç sızıntı düzeltildi. Geçmiş soran yerler (hareket listesi,
`HistoryService`, dönem hesapları) ham defteri kullanmaya DEVAM
ETMELİ — oralarda ham liste doğru olandır.

---

## (eski kayıt) Net miktarı 0'a düşmüş varlık ham listede yaşamaya devam ediyor

**Karar tarihi:** 2026-09-11 · Kullanıcı bildirimi (TestFlight)

Bir pozisyonun miktarı 0'a indiğinde satırları portföyde **aktif** kalır.
İki yoldan oluşur:
- tamamı satıldığında alım lot'u olduğu gibi durur, yanına `sell` satırı
  yazılır (`QuickAdjustDialog` → `addSellTransaction`) — net 0, satır iki;
- nakit temettü `quantity: 0` bir satır olarak yazılır
  (`PortfolioNotifier.addDividend`) — pozisyon kapandıktan sonra bile durur.

İkisi de `isActive` (ne mezar taşı ne yumuşak silinmiş), yani **ham lot
listesini gezen her yer** bunları "varlık var" sayar.

**Bilinen semptom (düzeltildi):** performans ekranında tür çipi, kullanıcı
o türden hiçbir şey tutmazken "Grafik verisi yok" diyordu — ham satır
vardı, çizilebilir varlık yoktu. `5cba894` ayrımı net pozisyona taşıdı.

**Muhtemel diğer sızıntı:** `price_alerts_screen.dart:50` alarm adaylarını
ham aktif `isBuy` lot'larından üretiyor — tamamen satılmış bir hisse hâlâ
aday olarak çıkıyor olmalı (doğrulanmadı).

**Neden şimdi çözülmedi — ve "sil" göründüğü kadar basit değil:**
Kullanıcının önerisi satırı silmek ya da soft-delete etmek. Ama bu satırlar
GEÇMİŞİN kendisi: `HistoryService` her gün için "o gün geçerli net miktarı"
alım/satım tarihlerinden kurar. Alım lot'u silinirse pozisyonun satıştan
ÖNCEKİ dönemi grafikten ve tüm periyot hesaplarından kaybolur — satılmış
varlık hiç olmamış gibi görünür. `deletedAt` damgası da aynı sonucu verir:
`isActive` false olur ve `keep`/`aggregatePositions` onu her yerden eler.
Yani "sil" seçeneği, kapanmış pozisyonun geçmiş performansını yok etmeyi
göze almak demektir — bu bir ürün kararı, teknik bir temizlik değil.

Üçüncü ve muhtemelen doğru yol: satırı silmemek, **okuma tarafını
düzeltmek**. "Kullanıcı bundan tutuyor mu?" sorusunun tek doğru cevabı
`aggregatePositions` (satılıp bitmişi `totalQty <= 0` ile, alım satırı
olmayanı `buyLots.isEmpty` ile düşürür). Ham listeyi gezen yerler tek tek
bu kaynağa çevrilmeli. Alternatif olarak `Position`'a `isClosed` gibi
açık bir kavram eklenip UI onu sorabilir.

**Ertelemenin maliyeti:** kapanmış pozisyonlar, ham listeyi gezen
ekranlarda hayalet olarak görünmeye devam eder. Her biri ayrı ayrı
keşfedilip düzeltiliyor (bugün performans ekranı) — sistematik bir
denetim yapılmadı.

**Ele alınma zamanı:** ham lot listesini gezen çağrı yerlerinin denetimi
yapıldığında. `grep -rn "\.assets\b" lib/screens lib/widgets` ile başla;
her birinde soru "geçmiş mi soruluyor, bugünkü mülkiyet mi?" — geçmişse
ham liste doğru, mülkiyetse `aggregatePositions` şart.

---

## ✅ KAPANDI — Grafik tipi seçicide Candle (mum) YOK

**KAPANDI 2026-09-14.** OHLC çekilmiyor, TÜRETİLİYOR: `utils/mum_turetici.dart`
seriyi takvime hizalı kovalara böler (gün içi 5 dk'lık noktalardan 30 dk'lık
mum, 1Y günlük kapanışlardan haftalık mum; kova `mumKovasiSec` ile ~40 mum
ve ≥2 nokta hedefine log-en-yakın aday). Çizim çubuk tipiyle aynı yolla:
her mum iki `LineChartBarData` (ince fitil + kalın gövde), fl_chart 0.68'de
mum çizimi olmadığı için. Doji yuvarlak uçlu nokta. Fitiller ÖRNEKLENMİŞ
noktaların uçlarıdır — menü etiketi bu yüzden "Mum", "OHLC" değil.
`mum_turetici_test` (12) + `grafik_tipi_test` (beş tip).

**Karar tarihi:** 2026-09-12 · Kullanıcı kararı

Kullanıcı TradingView'deki beş tipi istedi (Line / Candle / Baseline /
Mountain / Bar). Dördü eklendi, **Candle eklenmedi**.

**Neden:** mum grafiği OHLC ister (açılış / en yüksek / en düşük /
kapanış). Portföy serisi her zaman dilimi için **TEK değer** tutuyor
(`Map<int, double>` — o andaki toplam portföy değeri); OHLC veri
katmanında hiç üretilmiyor. Menüye koyup tıklanınca Line çizmek
kullanıcıyı yanıltırdı.

Kullanıcıya soruldu, "şimdilik atla" seçildi.

**Ertelemenin maliyeti:** tanıdık bir grafik tipi eksik. Kullanıcı
başka uygulamalarda gördüğü mumu burada bulamıyor.

**Ele alınma zamanı:** gün içi 5 dakikalık noktalardan günlük OHLC
türetilebilir (`getPortfolioHistoryHourlyBreakdown` zaten o çözünürlükte
veri çekiyor). Ayrı bir seri ve ayrı bir model alanı gerekir; yalnızca
GÜNLÜK sekmesinde anlamlı olur çünkü diğer dönemlerde gün içi nokta yok.

---

## 🟠 AÇIK — Altın gecikmesi YAPISAL olarak düzeltildi ama ÖLÇÜLMEDİ

**Karar tarihi:** 2026-09-13 · Kullanıcı bildirimi

Altın grafiği çok geç geliyordu ("uzun süre bekleyince geldi, kimse bu
kadar uzun beklemez"). Üç sebep kaynakta bulundu ve düzeltildi
(`e066af5`): iki isteğin sıralı olması, timeout bulunmaması, boş serinin
"veri var" sayılması.

**Ölçülemeyen:** gerçek gecikme süresi. Test ortamında ağ yok
(`GC=F`, `USDTRY=X` hepsi 0 nokta döndü), emülatörde oturum açık
değildi. Kanıt **yapısal**: iki isteğin sıralı olduğu ve timeout'un
bulunmadığı kaynakta doğrulandı, ama "30 saniyeden 8 saniyeye indi"
iddiası gerçek ağda ölçülmedi.

**Ertelemenin maliyeti:** düzeltmenin işe yaradığı varsayılıyor. Gerçek
darboğaz başka bir yerdeyse (örn. Yahoo'nun `XAUTRY=X` için yavaş
yanıtı) bu değişiklikler onu çözmez ve sorun sürer.

**Ele alınma zamanı:** gerçek cihazda oturum açıkken `adb logcat` ile
`getSymbolHistory` sürelerini ölç. Alternatif: geçici bir teşhis logu
ekleyip her sembolün çekim süresini yazdır.

**2026-09-14 — teşhis eklendi, ölçüm bekliyor.** `HistoryService._fetchSafe`
her çekimi kronometreler: debug'da konsola, 3 sn'yi aşan ya da zaman aşımına
düşenler Firebase'e `slow_history_fetch` (symbol, ms, points, timed_out).
Tüm çekimleri loglamak olay hacmini boşuna şişirirdi; soru "hâlâ yavaş mı,
hangi sembolde". İlk TestFlight/Play sürümünden sonra Analytics'te olay
görünmüyorsa sorun çözülmüş demektir; görünüyorsa sembol adı darboğazı
söyler (`GC=F` mi, `USDTRY=X` mi).

---

## ✅ KAPANDI — Varlık performansında GÜNLÜK sekmesinde karşılaştırma kapalı

**KAPANDI 2026-09-14.** `_karsilastirmaSerisi`: gün içinde karşılaştırma
varlığı ana varlıkla AYNI servisten (`getPortfolioHistoryHourlyBreakdown`)
çekilir; mevcut compare-bar kodu zaten her seriyi kendi ilk noktasına göre
×100 normalize ediyordu ve X'i gün kesri olarak hesaplıyordu — gün içi için
de aynı cebir geçerli. Sözleşme: "açılıştan bu yana % değişim", her seri
kendi açılışından (diğer periyotlarla aynı). Tek tuzak çizilen GÜN farkı
(hisse Cuma seansı, döviz bugün): o durumda seri boş döner ve uyarı
snack'i çıkar — yanlış güne ait çizgi çizilmez.

**Karar tarihi:** 2026-09-10 · Hata turu

`AssetDetailScreen`'e GÜNLÜK (gün içi) sekmesi eklendi. Karşılaştırma
şeridi (`_CompareStrip`) o sekmede **gizleniyor**: karşılaştırma serisi
`getPortfolioHistory(days)` ile çekiliyor ve gün içi sekmesi `days: 0`
taşıyor — o çağrı boş bir pencere isterdi. Sekme değiştirilirken seçili
karşılaştırma varlığı da temizleniyor.

**Neden şimdi çözülmedi:** doğru çözüm, ikinci varlığın gün içi serisini
`getPortfolioHistoryHourlyBreakdown` ile çekip iki seriyi ORTAK bir 5
dakikalık ızgaraya oturtmak ve yüzdeye normalize etmek. İki serinin
slotları örtüşmediğinde (biri BIST, öteki TEFAS fonu) hangi noktanın
hangisiyle eşleştiği ayrı bir karar. Yarım yapılmış hâli, kullanıcının
bakıp yanlış okuyacağı bir çizgi üretirdi.

**Ertelemenin maliyeti:** gün içinde iki varlık karşılaştırılamıyor.
Diğer dört periyotta karşılaştırma çalışmaya devam ediyor.

**Ele alınma zamanı:** `comparison_screen`'deki yüzde normalizasyonu gün
içi ızgaraya genelleştirildiğinde — iki ekran aynı cebri paylaşabilir.

---

## ✅ KAPANDI — Fonun gün içi NAV basamağı SABİT bir saate çapalı

**KAPANDI 2026-09-14 (gözlemle).** Damgayı TEFAS'tan beklemek yerine
kendimiz üretiyoruz: `observe-tefas-nav` edge function'ı iş günleri TR
06:00–21:30 arası yarım saatte bir, portföylerdeki her fon kodu için TEFAS'ın
son NAV satırını çekiyor ve daha önce görülmemiş bir (kod, NAV tarihi)
çiftini `tefas_nav_gozlem`'e `ilk_gorulme = now()` ile yazıyor (0063; satır
bir kez yazılır, `onceki_kontrol` bir önceki turun zamanı → yayın anı
[onceki_kontrol, ilk_gorulme] aralığında). İstemci `HistoryService.
fonBasamakAni`: NAV tarihi çizilen günse ve ilk görülme o güne düşüyorsa
basamak `ilk_gorulme` slotuna; her başka durumda **eski davranış aynen**
(`tefasNavYayinSaati` = 10:00). Bugün tarihli NAV'ı görülen kod o gün bir
daha sorulmaz (maliyet). Testler: `gun_ici_fon_degisimi_test` (çapa
öncelik/koruma kuralları), `supabase/tests/tefas_nav_test.ts` (tarih
biçimleri, TR gün sınırı, yeniden sorma kuralı).

**Kalan yaklaşıklık (bilinçli):** gözlem cron sıklığı kadar kaba (30 dk) ve
günün ilk turunda (06:00) görülen tarih yalnızca ÜST sınır verir. Daha ince
çözünürlük daha sık tur = daha çok TEFAS isteği; 30 dk grafikte 6 slot,
kullanıcı için fark yok. "İkinci yaklaşıklık" (NAV'ın kendi gününe atfı)
aynen duruyor: kullanıcı kararı, TEFAS'ın kendi "günlük getiri"siyle uyumlu.
Sunucu ayağı 2026-09-19'da canlıda doğrulandı: ilk tur 13 fon, 13 gözlem (`YAPMAN` #24 kapandı).

**Karar tarihi:** 2026-09-10 · Hata turu

TEFAS gün içi NAV yayınlamıyor; bir fonun fiyatı günde bir kez değişiyor.
Gün içi seride fon artık bir BASAMAK çiziyor: gün önceki NAV ile açılıyor,
seansın ilk gerçek fiyat verisinden sonra güncel NAV'a atlıyor
(`HistoryService.gunIciFonBirimFiyati`). Böylece fonun günlük değişimi
grafikte ve tür dökümünde görünür oluyor.

**Neden bu konum:** NAV'ın FİİLEN yayımlandığı saat bilinmiyor — TEFAS
yanıtı yalnızca NAV'ın TARİHİNİ taşıyor, yayın anını değil. Çapa bu yüzden
sabit bir saat: `tefasNavYayinSaati = 10` (piyasa açılışı).

**İlk deneme başarısız oldu ve sebebi kayda değer (2026-09-10):** basamak
önce "seansın ilk gerçek fiyat verisi"ne çapalanmıştı. O veri yalnızca
hisse/altın/emtia/döviz dallarında üretiliyor; portföyde ya da **tür
filtresinde** fondan başka varlık yoksa çapa HİÇ oluşmuyordu. Fon gün boyu
önceki NAV'da kalıyor, son slotu canlı toplamla ezen hizalama tek noktalık
dik bir uçurum bırakıyordu — üstelik "ŞİMDİ" imlecine yapışık, dakikalar
geçtikçe sağa kayan bir uçurum. Ders: bir çapa, kendisinden bağımsız
varlıkların verisine bağlı olmamalı.

**Ertelemenin maliyeti:** basamak gerçek yayın anından birkaç saat sapabilir.
Değişimin kendisi, yönü ve büyüklüğü doğru; yalnızca gün içindeki YERİ
yaklaşık.

**Bilinen ikinci yaklaşıklık:** TEFAS'ın en son NAV'ı çoğu gün BİR ÖNCEKİ iş
gününe aittir (fonun T günü NAV'ı T akşamı/T+1 sabahı yayımlanır). Yani
"bugünkü" fon değişimi olarak gösterilen fark, aslında o NAV'ın kendi
gününe ait olabilir. Kullanıcı bunu bilerek istedi (TEFAS'ın kendi sitesi de
aynı farkı "günlük getiri" diye gösteriyor) — ama tarih bazlı doğru
atıf yapılacaksa iş burada başlar.

**Ele alınma zamanı (o günkü not):** TEFAS yanıtından yayın zaman damgası
çıkarılabilirse (ya da güvenilir bir yayın saati doğrulanırsa) basamak oraya
taşınır. → Damga çıkarılamadı; gözlemle üretildi (yukarıdaki kapanış notu).

---

## ✅ KAPANDI — iOS bildirim izni ölçülemiyor

**KAPANDI 2026-09-14.** `IOSFlutterLocalNotificationsPlugin.checkPermissions()`
imzası kurulu pakette (18.0.1) doğrulandı; `NotificationService.init()`
sonunda `_iosIzinDurumunuOlc` sistem ayarını OKUR ve yalnızca durum
DEĞİŞİNCE (`PrefKeys.iosPushPermissionLast`) `recordPushPermission(
promptContext: 'ios_check')` yazar. Her açılışta yazmak "izin verdi" sayısını
açılış sayısına çevirirdi. Kullanıcı Ayarlar'dan kapatırsa da görünür —
istem değil okuma olduğu için.

**Karar tarihi:** 2026-09-06 · Sprint 0 (tutunma ölçümü)

`NotificationService.requestPermission` artık izin sonucunu
`RetentionTracker.recordPushPermission` ile kaydediyor — **ama yalnızca
Android'de.** iOS'ta izin `init()` içindeki `requestAlertPermission: true`
ile daha önce isteniyor; bu metot orada ikinci bir çağrı yapmıyor ve
sonucu bilmiyor.

**Neden şimdi çözülmedi:** `flutter_local_notifications` v18'de
`IOSFlutterLocalNotificationsPlugin.checkPermissions()` var, ancak bu
oturumda Flutter kurulu olmadığı için API imzası derlenerek
doğrulanamadı. Doğrulanmamış bir çağrı yazıp "ölçüyoruz" demek,
ölçmemekten kötü olurdu.

**Ertelemenin maliyeti:** push opt-in oranı yalnızca Android için biliniyor.
iOS payı büyükse (TestFlight/App Store dağıtımı var) izin funnel'ı yarım
görünür ve §1'deki "push izni oranı" sorusu iOS'ta hâlâ cevapsız.

**Ele alınma zamanı:** Flutter erişimi olan ilk turda — `checkPermissions()`
imzası doğrulanıp uygulama açılışında bir kez okunsun; sonuç
`recordPushPermission(promptContext: 'ios_check')` ile yazılsın.

---

## ✅ KAPANDI — Takvim kancasında gönderim defteri yok

**Kapanış:** 2026-09-14 · `calendar_nudge_log` tablosu
(`0053_fetch_inflation.sql`) + `calendar-nudge` defteri okuyup yazıyor.

Defter borç kaydının önerdiği şekilde: kullanıcı bazlı DEĞİL, `occasion` +
`period`. Kanca herkese aynı rakamı gönderiyor, dolayısıyla "bu ay
gönderildi mi" tek satırlık bir soru.

Anahtar GÖNDERİM GÜNÜ değil, endeksin AİT OLDUĞU ay: ayın 3'ünde ve
4'ünde koşan iki tur aynı ayı anlatıyor.

Ayın 4'ündeki ikinci tur böylece AÇILDI. Defter yalnızca `sent > 0` iken
yazılıyor — hepsi başarısız olduysa ikinci tur yeniden denemeli.

**⚠️ Dağıtım sırası bağımlı:** migration ikinci turu açıyor ama
`calendar-nudge` defteri okumayan eski sürümde kalırsa çift bildirim
gider. `supabase functions deploy calendar-nudge` migration'la BİRLİKTE
yapılmalı; `YAPMAN_GEREKENLER.md`'de 5. adım olarak işaretli ve
`fetch_inflation_test.ts` fonksiyonun defteri gerçekten okuduğunu
kaynak metninden denetliyor.

---

## ✅ KAPANDI — TÜFE endeksi elle dolduruluyor

**Kapanış:** 2026-09-14 · `fetch-inflation` edge function + aylık cron
(`0053_fetch_inflation.sql`).

Borç kaydı "EVDS anahtarı alındığında" diyordu. Anahtar HÂLÂ YOK; çözüm
anahtarsız da güvenli olacak şekilde kuruldu: `EVDS_API_KEY` tanımsızsa
fonksiyon `no_api_key` döner ve **hiçbir şey yazmaz**. Yarım bir
entegrasyonla tabloyu bozmak, elle girişten kötü olurdu — erteleme
gerekçesi buydu ve o gerekçe artık geçerli değil çünkü yazma yolu
anahtarsız hiç açılmıyor. Ayrıştırma mantığı gerçek EVDS yanıt şekliyle
(fixture) testli.

**Borç kaydının önerdiği CRON SAATİ YANLIŞTI.** `0 8 3 * *` (TR 11:00)
deniyordu; `calendar-nudge` ayın 3'ünde TR 10:15'te koşuyor ve tabloda bu
ayın satırını arıyor. Çekim ondan SONRA koşarsa nudge hep bayat veriyle
karşılaşır ve o ayın kancası kaçar — otomatikleştirmenin asıl kazancı
kaybolurdu. Doğru sıra: TÜİK 10:00 açıklar → **10:05 çekim** → 10:15
bildirim. Migration bu sırayı kendi kendine doğruluyor ve ikisi aynı
saate kurulursa yüksek sesle patlıyor.

**Ek olarak yakalanan risk — baz yılı değişimi.** TÜİK baz yılını
değiştirdiğinde endeks SIFIRLANIR (2003=100 → 2025=100) ve eski
satırlarla yeni satırlar karşılaştırılamaz: bölme "−%95 enflasyon" gibi
anlamsız bir sonuç verir. Fonksiyon ardışık aylarda %15'ten fazla düşüş
görürse yazmayı REDDEDİYOR (`base_year_break`, HTTP 409). Bu durumda
insan müdahalesi gerekiyor — yeni seri adı ve eski satırların ne olacağı
ürün kararı.

Revizyonlar bedava geldi: yazma `period` üzerinden upsert, TÜİK
açıklanmış bir ayı düzeltirse bir sonraki tur onu güncelliyor.

---

## ✅ KAPANDI — Push yardımcıları iki fonksiyonda kopya

**Karar tarihi:** 2026-09-06 · Sprint 1 · **Kapandı 2026-09-14:** Deno kuruldu, `deno check`
+ 222 test yeşilken `analyze-signals` ve `send-partner-invite-push` `_shared/fcm.ts`'e geçti
(`priority`/`badge` seçenekleri, silme kuralı birleşimi); beş fonksiyondaki `collapseTokens`/
`dedupeTokensByDevice` kopyaları `_shared/push_tokens.ts`'te tek kaynak (`push_tokens_test`,
`fcm_send_test`). Kalan yerel kopya yok.

`daily-brief` yazılırken JWT imzalama ve FCM gönderimi
`supabase/functions/_shared/fcm.ts`'e çıkarıldı. Ama `analyze-signals` hâlâ
**kendi kopyasını** kullanıyor: `createAccessToken`, `sendPush`, `shortLabel`
ve `dedupeTokensByDevice` (daily-brief'teki karşılığı `collapseTokens`).

**Neden şimdi birleştirilmedi:** `analyze-signals` çalışan ve dağıtılmış
1021 satırlık bir fonksiyon; bu oturumda Deno yoktu, yani taşımanın
doğruluğu koşularak gösterilemezdi. Sinyal bildirimleri kullanıcının aldığı
ana bildirim — onu körlemesine düzenlemek kabul edilebilir bir risk değil.

**Ertelemenin maliyeti:** iki kopya zamanla ayrışır. Somut senaryo: FCM
gönderim gövdesine bir alan eklenir (ör. `apns-collapse-id`), yalnızca
birine yazılır ve iki bildirim tipi farklı davranır.

**Ele alınma zamanı:** `analyze-signals`'a bir sonraki dokunuşta, `deno test
supabase/tests/` yeşilken. `_shared/fcm.ts` API'si hazır bekliyor.

---

## ✅ KAPANDI — Birim etiketi iki yerde, ikisi AYRIŞMIŞ

**Kapanış:** 2026-09-12 · Etiket mantığı `birimEtiketi(...)` saf
fonksiyonuna çıkarıldı (`lib/models/asset.dart`). `Asset.unitLabel` ve
`bulk_add_asset_screen._unitLabel()` artık ikisi de onu çağırıyor;
yerel kopya silindi.

Öngörüldüğü gibi `BulkCartItem`'ı değiştirmek gerekmedi — gereken üç
alan (`type`, `unitType`, `currency`) zaten vardı; eski kopya yalnızca
`unitType`'a bakıp `type`'ı hiç sormadığı için ayrışıyordu.

Test: `birim_etiketi_tekil_kaynak_test.dart` (14 test) — 10 tür/birim
kombinasyonunda sepet ile kayıtlı varlığın AYNI etiketi verdiğini
doğruluyor, ayrıca yerel `switch`'in geri gelmesini yasaklıyor.
Sabotajla doğrulandı.

---

## (eski kayıt) Birim etiketi iki yerde, ikisi AYRIŞMIŞ

**Karar tarihi:** 2026-09-10

`Asset.unitLabel` (lib/models/asset.dart) ile
`_AssetRow._unitLabel()` (lib/screens/bulk_add_asset_screen.dart) aynı
soruyu iki farklı şekilde yanıtlıyor:

| Girdi | `Asset.unitLabel` | `_unitLabel()` |
|---|---|---|
| hisse / fon | `lot` | `adet` |
| döviz | `$` / `€` | `adet` |

**Neden şimdi birleştirilmedi:** toplu ekleme ekranı `Asset` değil
`BulkCartItem` tutuyor — ortak getter doğrudan çağrılamıyor. Birleştirmek
ya `BulkCartItem`'a tür alanı eklemeyi ya da etiket mantığını üçüncü bir
saf fonksiyona çıkarmayı gerektiriyor. Bu turun isteği "performans
ekranında doğru birim" idi; kapsamı kendiliğinden genişletmedim.

**Ertelemenin maliyeti:** kullanıcı aynı hisseyi toplu ekleme ekranında
"10 adet", performans ekranında "10 lot" olarak görüyor. Görünür ama
zararsız bir tutarsızlık — yanlış hesap üretmiyor.

**Ele alınma zamanı:** toplu ekleme ekranına bir sonraki dokunuşta.
Etiket mantığı `(AssetType, String unitType) -> String` saf fonksiyonuna
çıkarılıp ikisi de ona bağlanmalı; `miktar_birimi_test.dart` kuralı
zaten kilitliyor.

---

## ✅ KAPANDI — `analyze-signals` silinmiş lot'lar için bildirim atıyordu

**Kapanış:** 2026-09-06 · Sprint 1

`assets` sorgusunda `deleted_at IS NULL` filtresi yoktu. Silme 0027'den beri
fiziksel değil damgalı olduğu için, kullanıcı bir lot'u sildikten sonra da
onun için teknik sinyal bildirimi almaya devam ediyordu.

Tek satırla kapandı (`.is('deleted_at', null)`). Aynı filtre `daily-brief`'te
baştan var.

---

## ✅ KAPANDI — iOS ana ekran widget'ı yazıldı

**Kapanış:** 2026-09-06 · Sprint 1

`ios/SandikWidget/SandikHomeWidget.swift` eklendi, `SandikWidgetBundle`'a
kaydedildi ve `project.pbxproj`'a dört giriş açıldı (PBXBuildFile,
PBXFileReference, grup, Sources fazı — id'ler `...0062`/`...0063`).

Çözülen asıl sorun veri yoluydu: sparkline PNG'si
`getApplicationSupportDirectory()` altına yazılıyor, yani uygulamanın KENDİ
kabına — uzantı ayrı sandbox'ta ve o yolu okuyamaz. iOS'a artık görsel değil
ham seri gönderiliyor (`sandik_spark_series`, paylaşımlı UserDefaults) ve
eğri `SandikSparkline` ile uzantıda çiziliyor.

**Kalan risk:** Swift ve pbxproj bu oturumda DERLENMEDİ (Xcode yok).
Bkz. aşağıdaki madde.

---

## ✅ KAPANDI — Swift widget ve pbxproj derlenerek doğrulanmadı

**KAPANDI 2026-09-14.** `ios-testflight.yml` her main push'unda `flutter build
ios --release` koşuyor ve `Embed Foundation Extensions` adımı
`SandikWidgetExtension.appex`'i Runner'a gömüyor; uygulama TestFlight'ta.
Yani pbxproj girişleri ve `SandikHomeWidget.swift` gerçek Xcode build'inden
geçti. Ayrı bir `xcodebuild` CI adımı (yol haritası 3.18) gereksiz — aynı
işi yayın hattı zaten yapıyor.

**Karar tarihi:** 2026-09-06 · Sprint 1

`SandikHomeWidget.swift` (257 satır) ve `project.pbxproj`'daki dört giriş
elle yazıldı; bu ortamda Xcode olmadığı için derlenmedi.

**Riski:** pbxproj bozuksa **tüm iOS build'i** kırılır — Kotlin tarafındaki
tek satırlık riskten daha büyük. Girişler mevcut `SandikSparkline.swift`
deseninin birebir kopyası ve id'ler çakışmıyor (en yüksek kullanılan
`...0061`), ama doğrulama ilk build'e kalıyor.

**Ele alınma zamanı:** ilk `ios-testflight.yml` turunda. Android tarafı
2026-09-07'de derlenerek doğrulandı ama bu iOS için hiçbir şey söylemez —
`project.pbxproj` yalnızca Xcode build'inde okunuyor.

Kırılırsa dört girişi de geri almak yeterli: widget dosyası hedefe dahil
olmaz ve uygulama derlenir, yalnızca iOS ana ekran widget'ı görünmez.

---

## ✅ KAPANDI — `HomeWidgetLaunchIntent` doğrulandı

**Kapanış:** 2026-09-07

Android APK derlendi ve her iki emülatörde çalıştı (bkz. 8d47d8f). Kotlin
derlenmeden APK üretilemeyeceği için `HomeWidgetLaunchIntent.getActivity`
imzası ve `es.antonborri.home_widget` paket yolu doğrulanmış oldu.

**Kalan iş bu maddede değil:** widget dokunuşunun analytics'e `app_launch
source=widget` olarak DÜŞTÜĞÜ ayrıca gözlenmeli — derlenmesi çalıştığını
kanıtlamaz. Emülatör test listesinde 15. madde.

---

## ✅ KAPANDI — `seyreltSpots` çağıransız duruyor

**KAPANDI 2026-09-14.** "Bir sonraki grafik temizliğinde hâlâ çağıranı yoksa"
koşulu doldu: `series_downsample.dart` ve beş testi silindi. Kural (kova
başına min+max, zarfı bozmadan) burada kayıtlı kalıyor; tier'sız ham bir
seri çizmek gerekirse yeniden yazılırken naif her-n'inci-nokta tuzağına
düşülmesin. `grafik_tasma_ve_yogunluk_test` ve `gunluk_eksen_parite_test`
çağrının geri gelmediğini denetlemeye devam ediyor.

**Karar tarihi:** 2026-09-04 · **Karar:** kullanıcı

`lib/utils/series_downsample.dart` içindeki `seyreltSpots` artık üretimde
hiçbir yerden çağrılmıyor. Tek çağıranı `percent_comparison_chart` idi;
kullanıcı çizim sıklığının performans ekranıyla **birebir** olmasını
isteyince kaldırıldı — performans ekranı çizgiyi hiç seyreltmez, sıklığı
yalnızca `ResolutionTier` belirler.

**Neden silinmedi:** kural (kova başına min+max koruyarak seyreltme, dış
zarfı bozmadan) doğru ve beş testle korunuyor. Tier'sız ham bir seri
çizmek gerekirse (örn. ileride bir CSV/içe aktarma grafiği) cevabı budur;
silinip yeniden yazılması, aynı tuzağa (naif her-n'inci-nokta seyreltme,
sıçramayı gizler) yeniden düşme riski taşır.

**Ertelemenin maliyeti:** ~60 satır ölü kod + 5 test. Çalışma zamanına
sıfır etki.

**Ele alınma zamanı:** bir sonraki grafik temizliğinde hâlâ çağıranı
yoksa testleriyle birlikte silinsin.

---

## 🟢 BÜYÜK ÖLÇÜDE KAPANDI — Live Activity: resmî tatil takvimi

**2026-09-14:** `services/bist_calendar.dart` (`BistTakvimi`) —
`DailySummary.isMarketOpen` (kilit ekranı + widget ortak katmanı) artık
sabit tarihli ulusal tatilleri her yıl, dinî bayramları YALNIZCA ilan
edilmiş yıllar için (şimdilik 2026) kapalı sayar; arife ve 28 Ekim 12:30'da
kapanır. Kaydın "yanlış liste listesizlikten kötü" uyarısına sadık:
kapsanmayan yılda dinî bayram bilinmez ve o gün AÇIK sayılır (eski
davranış), uydurulmaz. `bist_calendar_test` 2026 tarihlerini ve
kapsam-dışı yıl davranışını kilitler.

**Kalan (bakım):** her Aralık ayında bir sonraki yılın Resmî Gazete
takvimini `_diniTamGun` / `_diniYarimGun`'a girip `sonKapsananYil`'i
artır. Sunucu (push sinyalleri) hâlâ takvimi bilmez — "işlem günü"
tablosu gelirse iki taraf da oradan beslenir.

**Karar tarihi:** 2026-08-13

`LiveActivityService.isMarketOpen` yalnızca **hafta sonunu** eler; resmî
tatiller bilinmez. Tatil gününde seans açılır ve kilit ekranı gün boyu
sabit rakam gösterir.

**Neden ertelendi:** Doğru bir tatil listesi takvim verisi ister (dinî
bayramlar hicri takvime göre kayar, yarım günler var). **Yanlış** bir
liste, listesizlikten daha kötüdür: seansı gerçek işlem gününde kapatır
ve kullanıcı veriyi hiç göremez.

**Ertelemenin maliyeti:** Düşük ve kozmetik. Tatilde fiyat değişmediği
için banner zaten sabit durur, akşam 18:10'da kendiliğinden kapanır.
Yanlış veri gösterilmez — yalnızca gereksiz bir yüzey açılır.

**Ele alınma zamanı:** Sunucu tarafına bir "işlem günü" tablosu
girdiğinde (push sinyalleri de aynı takvimden faydalanır). O zamana
kadar `isMarketOpen` bu haliyle doğru davranır.

---

## ⏸️ ERTELENDİ — Live Activity: sunucu tarafı portföy hesabı

**Karar tarihi:** 2026-08-14 · **Karar:** kullanıcı

Push döngüsü portföy özetini **istemcinin yazdığı** `summary` alanından
okur (`live_activity_sessions.summary`). Sunucu portföy değerini kendisi
HESAPLAMAZ.

**Neden böyle:** portföy değeri lot toplama + döviz çevrimi + altın
dönüşümü ister ve bunların tamamı `HistoryService` içinde yaşıyor.
Sunucuda ikinci bir implementasyon kurmak iki kopyanın ayrışması demekti —
kullanıcı uygulamada bir rakam, kilit ekranında başka bir rakam görürdü.
Bu sınıf hata bu projede zaten yaşandı: ons→gram formülünün beş kopyası
vardı ve `ALTIN_RESAT` bir kopyada atlanmıştı (2026-08-14'te düzeltildi).

**Ertelemenin maliyeti:** Kullanıcı gün boyu uygulamayı hiç açmazsa kilit
ekranı son bilinen özeti gösterir. Yanlış veri değil, BAYAT veri —
`staleDate` sistem tarafından işaretlenir ve kullanıcı güncel sanmaz.
Pratikte kullanıcı gün içinde uygulamayı en az bir kez açıyor.

**Ele alınma zamanı:** Kullanıcılar "kilit ekranı geride kalıyor" derse.
Gerekenler: `intraday_prices` tablosu, 5 dk'lık fiyat çekme cron'u ve
`portfolio_daily_summary` RPC'si (lot agg + FX + sparkline). Yapılırsa
`HistoryService` ile ayrışmaması için ortak bir test kümesi şart.

---

## ⏸️ ERTELENDİ — Dev ekranları parçala

**Karar tarihi:** 2026-08-03 · **Karar:** kullanıcı, başka bir zamana bırakıldı

Beş ekran dosyası toplam **10.744 satır** — kod tabanının %31'i:

| Dosya | Satır |
|---|---|
| `lib/screens/add_asset_screen.dart` | 2.627 |
| `lib/screens/asset_detail_screen.dart` | 2.553 |
| `lib/screens/portfolio_performance_screen.dart` | 2.209 |
| `lib/screens/portfolio_screen.dart` | 1.690 |
| `lib/screens/leaderboard_screen.dart` | 1.665 |

**Ertelemenin maliyeti — teorik değil, ölçüldü:**
2026-08-03'te ortak kâr/zarar hatası **üç ekrana birden** yayılmıştı, çünkü
ortak filtreleme mantığı (`_view` == '' / null / uuid ayrımı) bu dosyalara
kopyalanmıştı. Tek bir hata üç ayrı yerde düzeltildi. Aynı kopyalama
`portfolio_performance_screen` ile `portfolio_screen` arasında hâlâ duruyor.

**Ele alınma zamanı:** Tek seferlik büyük bir refactor olarak DEĞİL — o
riskli ve test kapsamı buna yetmiyor. Bu ekranlardan birine iş düştükçe,
o dokunuşta ortak parçayı çıkar:
- Ortak/partner sekmesi + `ownerLots` kurulumu (3 ekranda tekrar ediyor)
- Tür filtresi chip satırı
- Periyot seçici + simülasyon toggle

**Ön koşul:** Widget testi olmadan bu ekranları bölmek riskli. Aşağıdaki
"widget test kapsamı" maddesi bundan önce gelmeli.

---

## 🟠 AÇIK — Widget test kapsamı (kısmen kapandı)

**2026-08-04 durumu:** 162 testin 46'sı gerçek widget testi:
- `transaction_row_overflow_test.dart` — `TransactionRow` (11 senaryo)
- `asset_card_overflow_test.dart` — `PortfolioScreen` (8 senaryo)
- `leaderboard_overflow_test.dart` — `LeaderboardScreen`, opt-in açık/kapalı
  iki hâl (8 senaryo)
- `asset_detail_screen_overflow_test.dart` — `AssetDetailScreen` (8 senaryo)
- `home_screen_overflow_test.dart` — `HomeScreen`, boş/dolu portföy
  (11 senaryo)

Hepsi çok genişlikli tarama yapıyor (320–430pt).

**Bulunan gerçek hatalar:** bu testler yazılırken **beş** taşma ortaya çıktı,
hiçbiri gözle görülmüyordu:
| Yer | Taşma | Sebep |
|---|---|---|
| `TransactionRow` satış satırı | 19px yatay | "Çıkarıldı" etiketi "Eklendi"den uzun, 116pt kolona sığmıyor |
| `asset_detail_screen` TOPLAM MİKTAR | 105px yatay | etiket + değer ikisi de sınırsız |
| `asset_detail_screen` TEKNİK ANALİZ başlığı | — | başlık + sayaç ayar bağlantısını itiyor |
| `asset_detail_screen` grafik lejantı | 15px yatay | uzun ticker rozetleri |
| `asset_detail_screen` DEĞİŞİM kartı | 54px @320pt | etiket tam genişliği alıyor, değer taşıyor |

Bu yaklaşımın değeri ölçüldü: gerçek widget'a bağlanan test, ilk çalıştırmada
**daha önce bilinmeyen bir taşmayı** ortaya çıkardı (satış satırında 19px
yatay — "Çıkarıldı" etiketi "Eklendi"den uzun ve 116pt'lik kolona sığmıyordu).
Yapısal kopya bunu yakalayamazdı çünkü kopyada etiket sabitti.

**Ekran-seviyesi test kalıbı (yeni):** `_AssetCard` gibi private ve çok
yardımcılı widget'lar için ayrı dosyaya çıkarmayı BEKLEMEYE gerek yok.
Ekranı `ProviderScope` override'larıyla pump et; iç yapı değil dış davranış
doğrulanır, ekran ileride parçalanınca test yine geçer. Örnek:
`asset_card_overflow_test.dart`.

**Sırada:** ~~`add_asset_screen` (form alanları)~~, ~~`portfolio_performance_screen`~~.
**2026-09-14 (2. tur):** `settings_screens_overflow_test` (hub + 4 alt ekran ×
3 genişlik + 1,6× metin) ve `alarm_widgets_overflow_test` (`AlarmSeridi` 7
alarm/uzun ad, `AlarmKurSheet` seçicili/sabit/1,6×) eklendi — aynı gün gelen
Ayarlar hub'ı ve alarm yüzeyleri artık kapsamda.
`tester.takeException()` yeterli, golden test gerekmiyor.

**2026-09-14:** `add_asset_screen_overflow_test.dart` eklendi — 5 genişlik ×
boş form, düzenleme, sepet, ön seçim, altı türün her biri, 320×560. İlk
koşuda **altıncı gerçek taşma** çıktı: `_totalHero` toplam maliyet kartında
sol kolon ve tutar ikisi de sabit genişlikteydi; kesirli fon miktarı × NAV
çarpımı 320pt'te 309px sağa taşıyordu. Sol taraf `Expanded` + ellipsis,
tutar `FittedBox(scaleDown)` oldu. `portfolio_performance_screen` için
`performance_screen_overflow_test` zaten vardı (ad 2.9 öncesinden kalma).
Yapısal kopya bu taşmayı da yakalayamazdı — gerçek widget'a bağlanan test
kalıbının değeri bir kez daha ölçüldü.

### ✅ `home_screen` widget testi — önce geri alındı, sonra kazanıldı (2026-08-04)

İlk denemede ekran testte izole edilemedi; üç sebep vardı ve üçü de kapandı:
- `signalProvider` → Supabase — `SignalNotifier` override'ıyla çözüldü
- `DbLogger._persistAsync` → her çağrıda bekleyen future kuruyordu; artık
  `DbLogger.silentInTests` ile susturuluyor (varsayılan `false`, üretim yolu
  değişmedi)
- `google_fonts` → DM Sans ağdan çekiliyordu; asset olarak gömüldü

`home_screen_overflow_test.dart` geri getirildi: 11 senaryo, boş ve dolu
portföy hâlleri, 320–430pt tarama. **Sabotajla doğrulandı** — başlıktaki
`Flexible`+`FittedBox` koruması kaldırılınca test her genişlikte düşüyor
(430pt'de 17px, 320pt'de 115px).

**Ders:** "ekran testte izole edilemiyor" çoğu zaman ekranın değil,
bağımlılıkların sorunudur. Testi silmeden önce her bağımlılığı tek tek
sustur.

---

## ✅ KARAR — Sertifika pinning YAPILMIYOR (L3 / yol haritası 3.19)

**Karar tarihi:** 2026-09-14 · **Karar:** yapılmıyor — kullanıcı onayladı (2026-09-14)

Denetim L3 "pinning yok" dedi. Pre-mortem yapıldı, sonuç: bu uygulamada
maliyeti faydasından büyük.

**Neden yapılmıyor:**
1. **Kesinti riski geri dönüşsüz.** Uç nokta `*.supabase.co`; sertifika ve
   ara CA zinciri Supabase/Cloudflare tarafından yönetilir ve haber
   verilmeden döner. Pin eşleşmediği an her istemci %100 kör olur ve tek
   çıkış yolu mağaza güncellemesidir (Play inceleme + kullanıcıların
   güncellemesi = günler). Yedek pin/uzaktan pin güncelleme mekanizması
   kurmak, korumanın kendisinden büyük bir altyapı.
2. **Tehdit modeli örtüşmüyor.** Pinning'in savuşturduğu şey cihaza
   kullanıcı/kurum CA'sı yüklenmiş bir MITM. Android 7+ release build'de
   kullanıcı CA'ları zaten reddedilir (varsayılan network security config);
   iOS'ta kurum profili gerekir. Kalan senaryo (kök CA ele geçirilmiş ya da
   cihaz root'lu) bir kişisel portföy uygulamasının savunma hattı değil.
3. **Veri zaten JWT + RLS arkasında.** MITM olsa bile anon key kamuya açık;
   erişim kullanıcı oturumuna bağlı, sunucu RLS zorluyor (0056 FORCE RLS).

**Ne yapılıyor onun yerine:** hiçbir şey eklenmiyor; mevcut TLS + RLS
yeterli. Kararı değiştiren şey: kurumsal/MDM dağıtımı ya da bir bulgu
(gerçek MITM raporu). O gün pin'ler uzaktan güncellenebilir olmalı
(Remote Config'te SPKI listesi + yedek pin) — sabit gömülü pin ASLA.

---

## ✅ KAPANDI — `signal_state` hâlâ lot başına anahtarlı

**KAPANDI 2026-09-14.** Şema DEĞİŞMEDEN kapatıldı: `asset_id` sütunu adını
koruyor, içeriği artık `pos:<tür>|<TICKER>` (`positionKeyOf`, analyze-signals).
Migration `0062` eski satırları `assets` üzerinden bu anahtara taşır (aynı
pozisyonun lot'larından en son bildirilen kazanır), lot anahtarlı artıkları
siler ve kalan varsa kendini patlatır. Sütunu yeniden adlandırmamanın sebebi
deploy penceresi: `touch_signal_state(p_asset_id)` imzası aynı kaldığı için
migration ile function deploy'u arasında hiçbir tur kırılmaz. 15 Deno testi
(birim + wiring: `lastSignalOf.get(asset.id)` geri gelirse test düşer).
**Deploy sende** (`YAPMAN_GEREKENLER.md` #23).

**Karar tarihi:** 2026-08-31

Aynı üründen birden çok alım yapan kullanıcı, o varlık için alım sayısı
kadar **kopya push** alıyordu. Sebep veri modeliydi: `assets` bir lot
tablosu, `signal_state` PK'sı `(user_id, asset_id)`. İki lot = iki bağımsız
de-dup satırı; ikisi de diğerinden habersiz "bunu göndermedim" diyordu.
Fiyat serisi ortak olduğu için ikisi de aynı sinyali üretiyordu.

**Yapılan düzeltme:** Analiz döngüsü artık lot değil **pozisyon** üzerinde
dönüyor — `collapseLotsToPositions` lot'ları `user_id|type|symbol` ile
tek temsilciye (en küçük `id`) indirger. Migration GEREKMEDİ: temsilcinin
`asset_id`'si `signal_state` anahtarı olarak kullanılmaya devam ediyor,
şema değişmedi.

**Kalan borç:** Şema hâlâ lot başına anahtarlı. Temsilci lot **silinirse**
(yumuşak silme sonrası aktif lot listesinden düşerse) o pozisyon yeni bir
temsilciye geçer ve de-dup hafızası sıfırlanır — kullanıcı o varlık için
bir kez fazladan bildirim alabilir. Tek seferlik ve zararsız; sessizlikten
iyidir (aynı gerekçe `notified_at === null` dalında da geçerli).

**Ele alınma zamanı:** `signal_state`'i pozisyon anahtarıyla yeniden
anahtarlamak gerekirse — yani kullanıcılar "varlık silince tekrar bildirim
geldi" derse. O zaman PK `(user_id, position_key)` olur ve mevcut satırların
taşınması gerekir.

**Test notu:** `supabase/tests/lot_collapse_test.ts`. Birim testleri
fonksiyonu doğrular ama **çağrıldığını doğrulamaz** — sabotajla ölçüldü:
döngü `aktifAssets`'e geri alındığında 8 testin 8'i de geçti. Bu yüzden
dosyada ayrıca kaynak metni denetleyen bir "wiring" testi var.

---

## ✅ KAPANDI — Paralel oturum incelemesi (2026-09-14)

İki bağımsız oturum aynı gün aynı dosyalara dokundu (baz para birimi,
Ayarlar hub'ı, alarmlar, derin bağlantı, paylaşım kartı). Metinsel çakışma
rebase'de çözüldü ama ANLAMSAL entegrasyon incelenmemişti; `82363ae..HEAD`
aralığı gözden geçirildi ve altı hata bulundu (hepsi düzeltildi, testlendi):

| Bulgu | Etki |
|---|---|
| `analyze-signals` de-dup haritası `asset_id` ile anahtarlı | 0062'den beri o sütun POZİSYON anahtarı ve kullanıcılar arası ORTAK: bir kullanıcının durumu ötekinin push'unu susturuyordu |
| Karşılaştırmada TÜFE 1A'da düz %0 | 30 günlük pencereye tek endeks noktası düşüyor; "enflasyon sıfır" okunuyordu |
| Gün içi karşılaştırmada seans günü kapısı | İki future birlikte başlıyor; karşılaştırma önce dönerse kapı boş/eski değer okuyor |
| Derin bağlantı çift push | `getInitialLink` + akış: eklenti aynı bağlantıyı iki kez veriyor |
| iOS izin damgası kayıttan önce | Kayıt düşerse olay kalıcı kayboluyor |
| Gizli bakiye maskesi `gr••••` | Gram altında sembol sonek |

**Ders:** paralel oturumlar aynı gün aynı alana dokunduğunda, çakışmasız
birleşme "doğru birleşti" demek değil. İkisi de yeşil testle geldi; hatalar
tam olarak ikisinin BİRLEŞME noktalarındaydı (0062 şema değişikliği ×
fonksiyonun bellek içi haritası, yeni TÜFE serisi × mevcut pencere kuralı).

---

## 🟡 AÇIK — Riverpod ile setState karışımı

Ekranlarda **147 `setState`** çağrısı. Yerel arayüz durumu (açık/kapalı
panel, seçili sekme) için doğru kullanım; veri durumu için Riverpod varken
ikili yönetim gereksiz rebuild ve kafa karışıklığı üretiyor.

2026-09-14: en büyük örnek kapandı — `add_asset_screen` form durumu
(37 `setState`, 17 alan) `AddAssetFormNotifier`'a taşındı; metin
controller'ları ekranda kaldı, controller kaynaklı yeniden çizim tek
`ListenableBuilder`. Kalan `setState`'ler ağırlıkla yerel arayüz durumu.

**Ele alınma zamanı:** Ekran parçalama işiyle birlikte, ayrı bir tur olarak
değil.

---

## 🟡 AÇIK — Baz para birimi yalnızca gösterim katmanı

2026-09-14 (Faz 3.2): USD/EUR/gram altın seçildiğinde TRY tutarı **bugünkü**
kurla bölünür (`utils/money_format.dart`). Bu "bugünkü dolarla kaç para"
sorusunu yanıtlar; "dolar bazlı gerçek getiri" (alış günü kuruyla maliyet,
bugünkü kurla değer) DEĞİLDİR — getiri yüzdeleri hâlâ TRY bazlıdır.

**Neden böyle:** lot başına alış günü kuru (`purchaseFxRate`) yalnızca döviz
cinsi varlıklarda dolu; TRY varlıklar için tarihli USDTRY serisi gerekir ve
seri motoru (`HistoryService`) bu çevrimi bilmiyor. Kur bazlı getiri ayrı bir
hesap ve ayrı bir tur.

**2026-09-14 (ikinci/üçüncü tur):** kapsam bir SÖZLEŞMEYE bağlandı —
portföy **DEĞERLERİ** baz birimde, kote **FİYATLAR** ₺ (kendi biriminde).
`money_format_scope_test` iki kümeyi kaynakta ayrı tutar. Değer kümesine
`asset_detail_screen`in PnL toplamı ve dönem değişimi ile `transaction_row`
eklendi; hareket tutarı da bugünkü kurla çevrilir (maliyet zaten öyleydi,
aynı sınıf sayının listede ₺ kalması tutarsızdı) — ama "o gün kaç dolardı"
sorusunun cevabı DEĞİLDİR.

**Kalan ₺ sabit yüzeyler — hepsi bilinçli:**
- **Kote fiyatlar:** tekil varlık grafiğinin ekseni/ipucu/çapası ve birim
  fiyatı, takip listesi (`currencySymbolFor`, AAPL için `$`), alarm hedefi,
  form girdisi. Bir hissenin TL fiyatını dolara çevirmek borsadaki sayıyla
  çelişir.
- **Bildirim ve özet metinleri** (`daily_summary`, `recap_service`,
  `milestone_service`, `period_summary_service` cümleleri): metni sunucu ya da
  arka plan üretiyor, kullanıcının tercihi orada okunmuyor.
- **`home_widget_service` / `live_activity_service`**: işletim sistemi yüzeyi;
  sözleşme `shared_preferences` üzerinden ve kur bilgisi taşımıyor.

**Ele alınma zamanı:** kullanıcı geri bildirimi "dolar getirim yanlış" derse.

---

## 🟡 AÇIK — Yarım kalan özellikler

İkisi de aynı kararı bekliyor: **ya tamamla ya sil.**

- ~~`deposits_enabled: false`~~ — vadeli mevduat 2026-09-14 tamamen kaldırıldı (0058).
  Faiz/vade hesabı ayrı bir domain; yarım hâlde durması karmaşıklık borcu.
- `paywall_enabled: false` — premium altyapısı (PremiumGate, paywall ekranı,
  Remote Config flag'leri) hazır ama `pubspec.yaml`'da IAP paketi YOK. Flag
  açılsa satın alma çalışmaz. Ayrıntı: `MONETIZATION_ROADMAP.md`.
- ~~`lib/screens/asset_detail_screen.dart` — ölü kod~~ — o dosya ESKİ
  `PerformanceScreen` döneminin ölü ikiziydi; Faz 1.1'de (2026-09-13) silindi.
  Bugünkü `asset_detail_screen.dart` canlı tekil varlık ekranıdır (2.9
  yeniden adlandırması). Aşağıdaki not tarihçe olarak duruyor
  (bulundu 2026-08-10).
  Hiçbir yerden `push` edilmiyor; sınıfa yapılan tek referans kendi tanımı,
  testi de yok. Varlık satırı bunun yerine `AssetDetailScreen`'e gidiyor.

  Neden hemen silinmedi: dosya `AssetDetailScreen`'e geçiş yapan bir alt
  bölüm içeriyor (satır 274), yani bir zamanlar akışın parçasıymış. Silmek
  ürün kararıdır — bu ekranın geri gelmesi planlanıyorsa yaşamalı.

  Erteleme maliyeti: analyze/test bu dosyayı taramaya devam eder, refactor'lar
  onu da günceller (nitekim kontrast ve dokunma hedefi düzeltmelerinde
  **kullanıcının hiç göremeyeceği** kod da düzeltildi).

---

## 🟡 AÇIK — Light mode: kalan cilalar

**Aşama 1–3 tamamlandı (2026-08-09).** Light mode çalışıyor:
`SandikPalette` `ThemeExtension`'ı, iki tema, `themeMode` provider'a bağlı,
~1.150 çağrı noktası `context.c.*`'a taşındı. Testler:
`light_mode_contrast_test.dart` (değerler), `light_mode_render_test.dart`
(paletin ekrana ulaşması).

**Kalanlar — hiçbiri light mode'u bloke etmiyor:**

1. ~~**`glassDecoration` / `glassBox` moda duyarlı değil.**~~ **KAPANDI
   2026-09-14:** ikisinin de üretimde çağıranı yoktu; silindi. Hâlâ beyaz tint +
   koyu gölge varsayıyor. Light modda cam yüzeyler (hero kart, bazı sheet'ler)
   olması gerekenden soluk görünür. `context.elevatedCard()` yazıldı ama
   glass helper'ları henüz ona taşınmadı.
2. **`legal_doc_screen.dart` kendi paletini taşıyor** (~29 sabit renk).
   Hukuki belge render'ı kasten sabit kontrastlı; light modda da koyu kalır.
   Bilinçli, ama tutarsız görünüyor — ürün kararı.
3. ~~**`asset_type.dart` kategori renkleri tek ton.**~~ **KAPANDI 2026-09-14:**
   `AssetType.onSurface(context)` light'ta açıklığı 0,28'e kısılmış tonu
   verir (hue korunur); 8 ikon/metin sitesi buna geçti, dolgular ham renkte
   kaldı. `asset_type_light_contrast_test` her türü ≥ 4,5:1'e bağlar. Rapordaki ölçüme göre
   yedisi de light zeminde AA altında (en kötüsü altın 1.52:1). Rozet
   *dolgusu* olarak sorun değil (arkada %15 alfa var), ama ikon/metin
   olarak kullanıldıkları yerde light varyantı gerekiyor.
4. ~~**`fl_chart` grid/tooltip renkleri** elle verilmiş~~ — 2026-09-14'te
   sayıldı: üç grafikte de grid `context.c.overlay/hairline`, tooltip
   `surface2`; elle verilen kalmamış. Yalnızca görsel doğrulama eksik; grafik ekranları
   light modda test edilmedi.
5. **Varsayılan mod hâlâ `ThemeMode.dark`.** `system` yapmak ürün kararı —
   marka "dark-first" olduğu için değiştirilmedi.

**Doğrulama notu:** emülatör Flutter'ı render edemiyor (bkz. yukarıdaki
emülatör maddesi). Light mode gerçek cihazda **kısmen** doğrulandı —
kullanıcı 2026-08-09'da Profil ve Ana Sayfa ekran görüntüsü gönderdi ve
iki hata çıktı (aşağıda). Diğer ekranlar (grafik, yarış, auth, mevduat)
**hâlâ gözle görülmedi**.

### Ekran görüntüsünden çıkan düzeltmeler (2026-08-09)

| Hata | Kök sebep | Düzeltme |
|---|---|---|
| Profil başlığı görünmüyordu | `CupertinoColors.white` sabiti — migrasyon `Colors.white`'ı yakaladı ama `CupertinoColors`'ı taramadı | `context.c.text90` |
| Bölüm etiketleri soluk (`ORTAKLIK İŞLEMLERİ`, `VARLIK DAĞILIMI`) | `text36` = 3.79:1 — bu **yardımcı metin** eşiği (3:1); bölüm başlığı yapısal bilgidir ve 4.5:1 ister | 8 yerde `text58` (6.90:1) |
| Hero kart koyu levha | `Color(0xFF14332B)` sabiti + üstünde light'ta koyulaşan `gain`/`gold` metni → koyu üstüne koyu | `context.isLight` ile yüzey/gölge/kenarlık ayrıldı |

**Ders:** `Colors.white` taraması yeterli değildi — `CupertinoColors.white`
ayrı bir sembol. Ayrıca "token kullanılıyor" ≠ "doğru token kullanılıyor";
`text36` her yerde geçerliydi ama light modda yapısal etiketler için yanlış
seçimdi. Kontrast testi bunu yakalayamaz çünkü token *değeri* doğru — hata
token *seçiminde*.

### İkinci tur — genel okunabilirlik denetimi (2026-08-09)

Kullanıcı "koyu sarı çok koyu, yazılar okunmuyor" ve bildirim ekranı
görüntüsü gönderdi. Tüm ekranlar betikle tarandı (37 bulgu), üç sınıf çıktı:

| Sınıf | Bulgu | Düzeltme |
|---|---|---|
| **Çamurlu sarı** | `amberText`/`gold` 5.67:1 ile AA geçiyordu ama sarıyı koyulaştırmak hue'yu kahveye kaydırıyor; göz "soluk renk" okuyor | `#4A3618` → **10.98:1**, kahve-nötr |
| **Sabit koyu yüzey** | Bildirim sheet'i `0xFF0F2A1F`, hero kart, yarış gradyanı — light'ta yabancı levha + üstünde koyu-üstüne-koyu metin | `context.isLight` ile ayrıldı |
| **Ters kontrast** | `zoomable_chart` tooltip'i koyu zemin + `text90` (light'ta koyu) → görünmez | Tooltip kendi kontrast dünyasını taşır: sabit koyu zemin + sabit açık metin |

Ayrıca 13 `foregroundColor: Colors.black` → `onAmber` (işlevsel olarak
doğruydu ama token dışındaydı; `amberFill` değişirse eşliği bozulurdu).

**Kalan (bilinçli):** `Colors.black.withValues(...)` gölge/scrim olarak
kullanılan ~8 yer — her iki modda doğru. `leaderboard` madalya ikincil
tonları (gümüş/bronz gölgesi) sabit; madalya rengi moda bağlı değil.

**Ders 2:** Kontrast eşiğini geçmek okunabilirlik için yeterli değil.
Sarı/turuncu ailesinde AA'yı geçen bir ton hâlâ "soluk" okunabilir çünkü
koyulaştırma hue'yu kaydırır. Bu yüzden `light_mode_contrast_test.dart`
marka tonları için 4.5 değil **9.0** eşiği kullanıyor.

### Üçüncü tur — üçüncül metin tonu + tema kısayolu (2026-08-09)

**Bulunan asıl sorun:** `text36` tonu **103 yerde gerçek metinde**
kullanılıyordu (boş durum açıklamaları, "Tümünü Temizle" gibi eylem
bağlantıları), çoğu 10–13pt. Kontrastı light'ta 3.79:1, **dark'ta 2.91:1**
idi — dark taraf AA'nın büyük-metin eşiğini (3:1) bile geçmiyordu.
Bu ton "yardımcı/dekoratif" varsayılarak düşük tutulmuştu ama kullanımı
öyle değildi.

| Token | Önce | Sonra |
|---|---|---|
| `text36` light | 3.79:1 | **5.31:1** |
| `text36` dark | 2.91:1 | **5.17:1** |
| `text20` | kullanılmıyor | ikisi de güçlendirildi |

Test eşiği 3.0 → 4.5'e çekildi, yani bu geri alınamaz.

**Yüksek kontrast desteği eklendi.** `MediaQuery.highContrastOf` açıkken
`SandikPalette.highContrast()` devreye girer: yalnızca yardımcı metin
tonları güçlenir (`text36` → 6.95:1), yüzeyler ve marka renkleri sabit
kalır. Android/iOS erişilebilirlik ayarına saygı gösterir.

**Tema kısayolu — Profil başlığı.** Ana sayfa başlığı düşünüldü ama orada
zaten dört aksiyon var ve satır 17px taşıyordu (kod yorumunda kayıtlı);
beşincisi yerleşimi kırardı. iOS HIG ve Material 3 görünüm ayarını
hesap/ayarlar bölgesine koyar. Tek dokunuş **açık ↔ koyu**; `system`
bilinçli tercih olduğu için yalnızca Ayarlar'daki üçlü seçicide kalır.
İkon hedefi gösterir (açık temadayken ay), mevcut durumu değil.

**Yanlış alarm notu:** Otomatik "tint zemin + metin" taraması 41 bulgu
verdi; incelemede 27'si `BoxShadow`/`Border` rengini zemin sanmaktan
kaynaklanıyordu, kalan 14'ü de grafik çizgi rengiydi. Betik düzeltildi.
**Ders:** otomatik kontrast taraması zemin/gölge ayrımını yapamazsa
gürültü üretir; bulguyu kodda doğrulamadan düzeltme uygulanmamalı.

### Dördüncü tur — `amberText` regresyonu (2026-08-09)

**Kendi ürettiğim hata.** Üçüncü turda `amberText` okunabilirlik için koyu
kahveye (`#4A3618`) çekildi. Ama bu token **9 yerde ZEMİN olarak**
kullanılıyordu: FAB dairesi (+ butonu), ortak sekmesi seçili pill'i, rozet
dolguları. Sonuç: koyu kahve zemin + `onAmber` metin = **1.41:1** → artı
işareti ve seçili sekme etiketi görünmez oldu.

Kullanıcı ekran görüntüsüyle yakaladı; testlerin hiçbiri görmedi çünkü
her iki token da tek başına geçerliydi — hata **eşleşmedeydi**.

**Kural netleştirildi:**
- `amberFill` → marka amberi, **zemin** (CTA, FAB, seçili pill)
- `amberText` → koyu kahve, **metin/ikon**
- `onAmber` → amber zemin üzerindeki metin

`design_token_leak_test.dart`'a regresyon koruması eklendi: `amberText`
bir `BoxDecoration`/`Container` içinde `color:` olarak geçerse test kırılır.
Kasten regresyon enjekte edilip doğrulandı.

**Ders 3:** Bir tokenin değerini değiştirmeden önce **nasıl kullanıldığına**
bak. "Metin rengi" diye adlandırılmış bir token pratikte zemin olarak
kullanılıyor olabilir; ad niyeti anlatır, kullanımı garanti etmez.

Tasarım ve komponent envanteri: `docs/archive/LIGHT_MODE_TASARIM_RAPORU.md`.

---

## ✅ KAPANDI

| Tarih | İş | Commit |
|---|---|---|
| 2026-09-01 | Gün içi sekmesinde tür dökümü (`getPortfolioHistoryHourlyBreakdown`) | commit bekliyor |
| 2026-08-03 | Ortak polling'i lifecycle'a bağla (900→240 istek/saat) | `2a956e4` |
| 2026-08-03 | History cache'e LRU + TTL | `2a956e4` |
| 2026-08-03 | Android AAB release pipeline | `b514c5a` |
| 2026-08-03 | PriceService bellek önbelleği | `b514c5a` |
| 2026-08-03 | Açılışta 3 servisi ertele (8→5 bloklayan await) | `fed8c87` |
| 2026-08-03 | Varlık listesi `ListView.builder` | `fed8c87` |
| 2026-08-03 | Ölü kod: SwiftUI prototipi + `DatabaseService` | `cde78d9` |
| 2026-08-03 | Paywall'da var olmayan özellik reklamı | `03f1798` |
| 2026-08-04 | `_buildAssetTile` → `TransactionRow` widget'ı; test yapısal kopyadan gerçek widget'a geçti (+ 19px satış satırı taşması bulundu) | — |
| 2026-08-04 | DM Sans asset olarak gömüldü, `allowRuntimeFetching = false` (P2 kapandı) | — |
| 2026-08-09 | Kâr/zarar renkleri WCAG AA altındaydı (`gain` 4.30:1, `loss` 3.90:1) → `#3DB77F` / `#FF6B52` ile 5.73:1 ve 5.17:1; kontrast testiyle kilitlendi | — |
| 2026-08-09 | Light mode Aşama 1–3: `SandikPalette` ThemeExtension, iki tema, `themeMode` bağlandı, ~1.150 çağrı `context.c.*`'a taşındı, 12 yeni test | — |

### Not: google_fonts çalışma zamanı indirmesi (kapandı 2026-08-04)

`google_fonts` paketi font **dosyalarını içermez** — varsayılan davranışı,
istenen aileyi ilk kullanımda `fonts.gstatic.com`'dan indirip cihaza
cache'lemektir. Sonuç: ilk açılış ağa bağımlıydı, offline'da DM Sans yerine
sistem fontu çiziliyordu.

Altı statik ağırlık (400/500/600/700/800/900 — `lib/` taraması bunları
kullanıyor) `assets/fonts/` altına alındı ve `main()` başında
`allowRuntimeFetching = false` yapıldı.

**Maliyet:** APK içinde sıkıştırılmış **161 KB**. Buna karşılık ağ isteği
sıfır, ilk açılış deterministik.

**Doğrulama tuzağı:** `flutter test` asset/font manifest'ini uygulamadaki
gibi yüklemez — pubspec'teki font kaydını tamamen bozsanız bile
`GoogleFonts.dmSans()` testte sorunsuz döner. Yani "çağrı fırlatmıyor"
biçimindeki bir test **hiçbir şey kanıtlamaz** (önce öyle yazıldı, sabotaj
denemesinde yakalanmadığı görülüp değiştirildi). `bundled_font_test.dart`
bunun yerine pubspec kaydını, dosyaların varlığını ve her TTF'in `OS/2`
`usWeightClass` alanını doğrudan okur; üç sabotaj senaryosuyla (aile adı
bozuk, ağırlık eksik, bayrak silinmiş) düştüğü teyit edildi.

Derlenmiş APK'daki `FontManifest.json` da elle kontrol edildi: aile adı
`"DM Sans"` ve altı ağırlık doğru eşlenmiş durumda.

---

## Ölçülemeyenler

Cold start süresi, scroll jank ve bellek profili **ölçülmedi**: geliştirme
emülatörü frame üretmiyor (`dumpsys gfxinfo` → "Total frames rendered: 1").
Gerçek cihazda `flutter run --profile` ile ölçülmeli.

### Emülatörde Flutter render etmiyor — kapsamı 2026-08-04'te daraltıldı

Bu makinedeki emülatörlerde **hiçbir Flutter build'i** görsel çıktı vermiyor.
Ekran siyah kalıyor, `screencap` ~20 KB tek renk PNG üretiyor.

Elenen ihtimaller (hepsi denendi, sonuç değişmedi):

| Değişken | Denenen | Sonuç |
|---|---|---|
| API seviyesi | 35 ve 36 | ikisinde de 1 frame |
| Build tipi | release (R8'li) ve debug | ikisinde de 1 frame |
| GPU modu | host default ve `swiftshader_indirect` | ikisinde de 1 frame |
| Renderer | Impeller ve `--ez enable-impeller false` | ikisinde de 1 frame |

**Emülatörün kendisi sağlam:** aynı cihazda sistem Ayarlar uygulaması 44
frame üretiyor ve 188 KB'lık dolu bir ekran görüntüsü veriyor. Sorun
Flutter/Impeller ile bu emülatörün GL yığını arasında.

**Uygulama sağlam:** logcat'te `Supabase init completed` görünüyor, süreç
yaşıyor, FATAL/ANR yok. Dart tarafı sonuna kadar çalışıyor — yalnızca
sunum katmanı okunamıyor.

**Sonuç:** Emülatör, görsel doğrulama için kullanılamaz. `uiautomator dump`
da boş dönüyor (Flutter erişilebilirlik ağacını doldurmuyor), yani otomatik
arayüz doğrulaması da bu yoldan yapılamaz. **Yerleşim/taşma doğrulaması
gerçek cihazda veya widget testiyle yapılmalı.**
