# sandık — Teknik Borç Defteri

Ertelenmiş **kod** kararları. Kullanıcının elden yapacağı işler
`YAPMAN_GEREKENLER.md`'de; burası yalnızca kod tabanına dair borç.

Her madde: neden ertelendi, ertelemenin maliyeti ne, ne zaman ele alınmalı.

**Son güncelleme:** 2026-08-13

---

## ⏸️ ERTELENDİ — Live Activity: resmî tatil takvimi

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
| `lib/screens/performance_screen.dart` | 2.553 |
| `lib/screens/portfolio_performance_screen.dart` | 2.209 |
| `lib/screens/charts_screen.dart` | 1.690 |
| `lib/screens/leaderboard_screen.dart` | 1.665 |

**Ertelemenin maliyeti — teorik değil, ölçüldü:**
2026-08-03'te ortak kâr/zarar hatası **üç ekrana birden** yayılmıştı, çünkü
ortak filtreleme mantığı (`_view` == '' / null / uuid ayrımı) bu dosyalara
kopyalanmıştı. Tek bir hata üç ayrı yerde düzeltildi. Aynı kopyalama
`portfolio_performance_screen` ile `charts_screen` arasında hâlâ duruyor.

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
- `asset_card_overflow_test.dart` — `ChartsScreen` (8 senaryo)
- `leaderboard_overflow_test.dart` — `LeaderboardScreen`, opt-in açık/kapalı
  iki hâl (8 senaryo)
- `performance_screen_overflow_test.dart` — `PerformanceScreen` (8 senaryo)
- `home_screen_overflow_test.dart` — `HomeScreen`, boş/dolu portföy
  (11 senaryo)

Hepsi çok genişlikli tarama yapıyor (320–430pt).

**Bulunan gerçek hatalar:** bu testler yazılırken **beş** taşma ortaya çıktı,
hiçbiri gözle görülmüyordu:
| Yer | Taşma | Sebep |
|---|---|---|
| `TransactionRow` satış satırı | 19px yatay | "Çıkarıldı" etiketi "Eklendi"den uzun, 116pt kolona sığmıyor |
| `performance_screen` TOPLAM MİKTAR | 105px yatay | etiket + değer ikisi de sınırsız |
| `performance_screen` TEKNİK ANALİZ başlığı | — | başlık + sayaç ayar bağlantısını itiyor |
| `performance_screen` grafik lejantı | 15px yatay | uzun ticker rozetleri |
| `performance_screen` DEĞİŞİM kartı | 54px @320pt | etiket tam genişliği alıyor, değer taşıyor |

Bu yaklaşımın değeri ölçüldü: gerçek widget'a bağlanan test, ilk çalıştırmada
**daha önce bilinmeyen bir taşmayı** ortaya çıkardı (satış satırında 19px
yatay — "Çıkarıldı" etiketi "Eklendi"den uzun ve 116pt'lik kolona sığmıyordu).
Yapısal kopya bunu yakalayamazdı çünkü kopyada etiket sabitti.

**Ekran-seviyesi test kalıbı (yeni):** `_AssetCard` gibi private ve çok
yardımcılı widget'lar için ayrı dosyaya çıkarmayı BEKLEMEYE gerek yok.
Ekranı `ProviderScope` override'larıyla pump et; iç yapı değil dış davranış
doğrulanır, ekran ileride parçalanınca test yine geçer. Örnek:
`asset_card_overflow_test.dart`.

**Sırada:** `add_asset_screen` (form alanları), `portfolio_performance_screen`.
`tester.takeException()` yeterli, golden test gerekmiyor.

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

## 🟡 AÇIK — `signal_state` hâlâ lot başına anahtarlı

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

## 🟡 AÇIK — Riverpod ile setState karışımı

Ekranlarda **147 `setState`** çağrısı. Yerel arayüz durumu (açık/kapalı
panel, seçili sekme) için doğru kullanım; veri durumu için Riverpod varken
ikili yönetim gereksiz rebuild ve kafa karışıklığı üretiyor.

**Ele alınma zamanı:** Ekran parçalama işiyle birlikte, ayrı bir tur olarak
değil.

---

## 🟡 AÇIK — Yarım kalan özellikler

İkisi de aynı kararı bekliyor: **ya tamamla ya sil.**

- `deposits_enabled: false` — vadeli mevduat kodu duruyor, kullanıcıya kapalı.
  Faiz/vade hesabı ayrı bir domain; yarım hâlde durması karmaşıklık borcu.
- `paywall_enabled: false` — premium altyapısı (PremiumGate, paywall ekranı,
  Remote Config flag'leri) hazır ama `pubspec.yaml`'da IAP paketi YOK. Flag
  açılsa satın alma çalışmaz. Ayrıntı: `MONETIZATION_ROADMAP.md`.
- `lib/screens/asset_detail_screen.dart` — **ölü kod** (bulundu 2026-08-10).
  Hiçbir yerden `push` edilmiyor; sınıfa yapılan tek referans kendi tanımı,
  testi de yok. Varlık satırı bunun yerine `PerformanceScreen`'e gidiyor.

  Neden hemen silinmedi: dosya `PerformanceScreen`'e geçiş yapan bir alt
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

1. **`glassDecoration` / `glassBox` moda duyarlı değil.** Hâlâ beyaz tint +
   koyu gölge varsayıyor. Light modda cam yüzeyler (hero kart, bazı sheet'ler)
   olması gerekenden soluk görünür. `context.elevatedCard()` yazıldı ama
   glass helper'ları henüz ona taşınmadı.
2. **`legal_doc_screen.dart` kendi paletini taşıyor** (~29 sabit renk).
   Hukuki belge render'ı kasten sabit kontrastlı; light modda da koyu kalır.
   Bilinçli, ama tutarsız görünüyor — ürün kararı.
3. **`asset_type.dart` kategori renkleri tek ton.** Rapordaki ölçüme göre
   yedisi de light zeminde AA altında (en kötüsü altın 1.52:1). Rozet
   *dolgusu* olarak sorun değil (arkada %15 alfa var), ama ikon/metin
   olarak kullanıldıkları yerde light varyantı gerekiyor.
4. **`fl_chart` grid/tooltip renkleri** elle verilmiş; grafik ekranları
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

Tasarım ve komponent envanteri: `LIGHT_MODE_TASARIM_RAPORU.md`.

---

## ✅ KAPANDI

| Tarih | İş | Commit |
|---|---|---|
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
