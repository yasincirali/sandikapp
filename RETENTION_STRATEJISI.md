# sandık — Etkileşim & Tutundurma Stratejisi

**Tarih:** 2026-09-06
**Kapsam:** Kullanıcıyı uygulamada tutan, uygulamayı sık açtıran mekanikler — kanıt,
uygulama planı ve kod dokunuş noktalarıyla.
**Durum:** Araştırma çıktısı. Kod değişikliği içermez.

> **Terminoloji notu:** Talep "CPI artırmak" olarak geldi. Bu doküman **kullanıcı
> başına etkileşim** (açılma sıklığı, DAU/MAU, tutunma) olarak ele alıyor. Cost Per
> Install anlamındaki CPI için ayrı bir bölüm var (§10) — orada mantık ters yönde
> işler: retention'ı yükseltmek CPI'yı *artırmana izin verir*.

---

## 0. Altı cümlede karar

1. **Şu an körsün.** `analytics_service.dart` 18 event tanımlıyor ama içlerinde tek bir
   tutunma/aktivasyon event'i yok. D1/D7 ölçemeden hiçbir mekaniğin işe yarayıp
   yaramadığını bilemezsin. **Önce ölçüm, sonra mekanik.**
2. **Tracker'ın yapısal problemi:** Kullanıcının uygulamada yapacak bir *işi* yok.
   Broker'da "al-sat" var, Duolingo'da "ders" var; sende sadece "bakmak" var. Bu yüzden
   klasik streak buraya **doğrudan kopyalanamaz** — hollow engagement üretir (§5.D).
3. **Uygulamanın kendisi değil, veri açığı geri getirir.** Kullanıcıyı geri çağıran şey
   "gel bak" değil, **"senin portföyünde şu oldu"**. Kişiselleştirilmiş insight push'u
   ile jenerik hatırlatma arasındaki fark, açılma oranında kat farkıdır.
4. **İki yüzey yarım kalmış: widget ve percentile.** Percentile RPC yazılmış ve
   Yarış ekranında teaser olarak *kullanılıyor* — ama oraya kullanıcı bilerek gider,
   yani zaten gelmiş olanı görür; ana ekranda yok ve hiç ölçülmüyor. Widget ise
   yalnızca **Android'de** var: `HomeWidgetService` iOS'u destekliyor ama
   `SandikWidgetBundle.swift` sadece Live Activity içeriyor, WidgetKit görünümü
   hiç yazılmamış. *(Düzeltme 2026-09-06: bu maddenin ilk hâli ikisini de "hiç
   kullanılmıyor" ve widget'ı "Android + iOS" diye yazıyordu.)*
5. **Türkiye'ye özel takvim senin en savunulabilir diferansiyatörün:** her ayın 3'ü TÜİK
   enflasyon açıklaması, maaş günü, bayram-altın mevsimi, Mart beyanname. Bunlar
   uydurma bildirim sebebi değil, **ulusal dikkat anları**.
6. **Bilerek yapmayacağın şeyler bu işin yarısı.** Sen AL/SAT sinyali push'layan bir
   uygulamasın. Robinhood'un confetti'si 7,5 milyon dolarlık uzlaşmayla bitti (§8).
   Türkiye'de SPK'nın YTD çerçevesi var. "Daha çok açtır" hedefi, "daha çok işlem
   yaptır"a dönüşürse kullanıcıya da sana da zarar verir.

---

## 1. Ölçüm boşluğu — bunu kapatmadan hiçbir şey yapma

### Şu an ne var
`lib/services/analytics_service.dart` — auth, onboarding, asset CRUD, sinyal, paywall,
partner event'leri. Hepsi **eylem** event'i. Hiçbiri tutunma sorusuna cevap vermiyor.

### Cevaplayamadığın sorular
| Soru | Neden kritik | Şu an ölçülüyor mu |
|---|---|---|
| D1/D7/D30 tutunma kaç? | Tüm çalışmanın temel çizgisi | ❌ |
| Kullanıcı haftada kaç gün açıyor? | Asıl "CPI" metriği | ❌ (sadece Firebase'in otomatik `session_start`'ı) |
| Push iznini kaç kişi verdi? | En büyük geri getirme kanalı | ❌ |
| Widget'ı kaç kişi kurdu? | İkinci kanal, izin gerektirmez | ❌ |
| İlk oturumda kaç varlık eklendi? | **Aktivasyon eşiği** — D30'un en güçlü tahmincisi | ❌ |
| Sinyal push'u açan / gelen oranı | Bildirim kalitesi | Kısmen (`signal_received` var, `signal_opened` yok) |

### Eklenecek event seti (Faz 0 — 1 gün iş)

```dart
// lib/services/analytics_service.dart — eklenecekler

// ── Aktivasyon (D30'un tahmincileri) ──────────────────────────────────
logActivationMilestone({required String milestone});   // first_asset | three_assets | first_week_survived
logPushPermission({required bool granted, required String prompt_context});
logWidgetInstalled({required String platform, required String size});
logWidgetTapped({required String surface});            // home_widget | lock_widget | live_activity

// ── Ritim ──────────────────────────────────────────────────────────────
logAppOpen({required String source, required int daysSinceInstall});
                                                        // source: cold | push | widget | live_activity | share_link
logStreakDay({required int currentStreak});
logSessionDepth({required int screensViewed, required int secondsActive});

// ── Bildirim yaşam döngüsü ─────────────────────────────────────────────
logNotificationOpened({required String type, required int minutesSinceSent});
logNotificationSettingsChanged({required String channel, required bool enabled});

// ── Değer anları ───────────────────────────────────────────────────────
logMilestoneReached({required String kind, required String value});
logRecapViewed({required String period});
logRecapShared({required String period, required String channel});
logPercentileViewed({required int bucket});
```

**Ayrıca user property olarak yaz** (kohort kesmek için):
`asset_count_bucket` (0/1-3/4-10/10+), `has_widget`, `push_enabled`, `has_partner`,
`primary_asset_type`, `install_week`.

### Sprint 0 — uygulanan (2026-09-06)

| Ne | Nerede | Durum |
|---|---|---|
| Tutunma event yüzeyi (13 metot) | `lib/services/analytics_service.dart` | ✅ |
| Cihaz defteri: kurulum günü, aktif gün, tek seferlik eşikler | `lib/services/retention_tracker.dart` *(yeni)* | ✅ |
| Soğuk açılış + öne dönüş kaydı | `lib/main.dart` | ✅ |
| Aktivasyon eşikleri (`first_asset`, `three_assets`) | `lib/providers/portfolio_provider.dart` | ✅ |
| Push izni sonucu (Android) | `lib/services/notification_service.dart` | ✅ |
| Bildirim açılma (`push_opened`) | `lib/services/notification_service.dart` | ✅ |
| Birim testler (16 senaryo) | `test/retention_tracker_test.dart` *(yeni)* | ✅ |
| Push izni sonucu (iOS) | — | ⛔ bkz. `TECHNICAL_DEBT.md` |
| Widget kurulum + dokunuş atfı | — | ⛔ native iş, Sprint 1 §B |

**Firebase ayrılmış ad tuzağı:** `session_start`, `notification_open`,
`notification_receive`, `first_open` Firebase'in kendi kullandığı adlar —
bu adlarla özel event göndermek otomatik toplananla karışır. Bu yüzden
sırasıyla `app_launch`, `push_opened`, `activation_milestone` kullanıldı.
Yeni event eklerken ayrılmış adlar listesini kontrol et.

**Ölçüm kararları:**
- Kısa arka plan dönüşleri (30 dk altı) yeni açılış SAYILMAZ — yoksa
  telefonu cebe koyup çıkarmak günlük açılış metriğini şişirir. Bildirimden
  dönüş bu kurala takılmaz; o gerçek bir açılıştır.
- Aktivasyon eşikleri **bir kez** gönderilir; tekrar, "ilk varlığını ekleyen
  kullanıcı sayısı"nı kullanıcı başına birden çok kez artırırdı.
- "Üç varlık" eşiği lot değil **distinct pozisyon** sayar — aynı hisseye üç
  kez ekleme yapan kullanıcı çeşitlenmiş sayılmamalı.
- Gün farkı takvim gününden hesaplanır (UTC normalize), 24 saatten değil:
  D1 kohortu takvim günü üzerinden tanımlıdır ve yaz saati geçişinde kaymaz.

### Sprint 1 — uygulanan (2026-09-06)

Üçü de **Remote Config bayrağı arkasında ve kapalı doğar.** Sprint 0'ın taban
çizgisi birikmeden açılırlarsa etkileri ölçülemez — "öncesi" verisi olmadan
öncesi/sonrası karşılaştırması yapılamaz.

| Ne | Bayrak | Nerede | Durum |
|---|---|---|---|
| Ana ekran yüzdelik dilim şeridi + ölçüm | `percentile_strip_enabled` | `lib/widgets/percentile_strip.dart` *(yeni)*, `home_screen.dart` | ✅ |
| Widget dokunuş atfı (Android) | — | `SandikWidgetProvider.kt`, `home_widget_service.dart`, `main.dart` | ✅ |
| Bildirim izni: ilk varlık sonrası | `push_prompt_after_first_asset` | `main.dart`, `main_navigation_screen.dart` | ✅ |
| **Sabah brifingi push** | cron (`daily-brief`) | `supabase/functions/daily-brief/`, `0044_daily_brief.sql` | ✅ |
| Widget kurulum önerisi | `widget_prompt_enabled` | `lib/widgets/widget_install_sheet.dart` *(yeni)* | ✅ |
| **iOS ana ekran widget'ı** | — | `ios/SandikWidget/SandikHomeWidget.swift` *(yeni)* | ✅ derlenmedi |

**Şeridin üç kapısı:** Remote Config bayrağı, kullanıcının yarış opt-in'i,
sunucudaki k-anonimlik eşiği. Üçünden biri kapalıysa şerit **hiç çizilmez** —
"yakında" plaseholderi ana ekranda yer işgal etmeye değmez. Dolgu widget'ın
içindedir; dışarıda olsaydı gizliyken bile boşluk bırakırdı.

**Şerit snapshot'ı kendisi tazeler.** `get_percentile_bucket` yalnızca son 24
saatte snapshot atmış kullanıcıları karşılaştırıyor ve yükleme eskiden sadece
Yarış ekranında yapılıyordu. Şerit ona bağlı kalsaydı yalnızca "bugün Yarış'a
uğramış" kullanıcıda çalışırdı — yani pratikte hiç görünmezdi.

**Dil kararı:** "İlk %X'tesin" yerine "senin gibi yatırımcıların %Y'sinden iyi
getirdin". Aynı sayı, daha az yarışmacı çerçeve — ve §9'daki "işlemi değil
birikimi ödüllendir" ilkesiyle tutarlı. Tutar hiçbir yerde gösterilmiyor.

**Widget atfı neden gerekliydi:** Android widget'ı dokunulunca uygulamayı zaten
açıyordu ama düz bir launch intent'le — Dart tarafı açılışın widget'tan
geldiğini bilmiyordu, dolayısıyla widget kaynaklı her açılış analytics'te
organik (`cold`) görünüyor ve widget'ın katkısı ölçülemiyordu. Artık
`HomeWidgetLaunchIntent` bir URI taşıyor ve açılış kaynağı **yazılmadan önce**
belirleniyor (önce `cold` yazıp sonra `widget` eklemek aynı açılışı iki kez
saydırırdı).

**Sabah brifingi v1 bilerek dar tutuldu.** "Portföyün %X arttı" *demiyor*,
"portföyünde en çok hareket eden hisse şu" diyor. Sebep doğruluk: portföy
yüzdesi için her varlığı TRY'ye çevirmek gerekir ve canlı kur sunucuda yok;
üstelik altın serisi `GC=F` (ons/USD) olarak çözülüyor — onun günlük yüzdesi
TRY gram altınınki değildir (arada USD/TRY var). Yanlış bir yüzde, hiç
bildirim göndermemekten kötüdür: kullanıcı sayıyı uygulamadakiyle
karşılaştırır. BIST hissesinde bu tuzak yok, seri de holding de TRY.
Kapsamı genişletmek önce sunucuya kur modeli koymayı gerektiriyor.

**Brifing "son kapanışta" der, "bugün" değil.** 09:45'te BIST açılmamıştır ve
fiyat cache'i günlük kapanış tutar; serinin son noktası bir önceki işlem
günüdür. "Dün" demek pazartesi yanlış olurdu (son kapanış cuma).

**Eşik %1,5.** Altındaki günlerde bildirim gitmez — "%0,3 yükseldi" §7'deki
haftalık 5 bildirimlik bütçeyi hiçbir şey söylemeden harcar. `daily_brief_log`
tablosu da aynı güne ikinci bildirimi engelliyor.

**Yan bulgu — kapatıldı:** `analyze-signals` silinmiş lot'ları filtrelemiyordu
(`deleted_at IS NULL` yoktu), yani kullanıcı sildiği varlık için hâlâ sinyal
bildirimi alıyordu. Tek satırla düzeltildi.

**iOS widget'ı PNG değil, çizim.** Android hazır bir PNG okur çünkü
`RemoteViews` özel görünüm çizemez. iOS'ta bu yol kapalıydı: PNG
`getApplicationSupportDirectory()` altına yazılıyor — uygulamanın *kendi*
kabı — ve uzantı ayrı sandbox'ta o yolu göremiyor. Çözüm, paylaşımlı
`UserDefaults` (app group) üzerinden görsel değil **sayı** göndermek; eğri
`SandikSparkline` ile uzantıda çizilir. Bunun için normalize hesabı
`LiveActivityService`'ten `DailySummary`'ye taşındı: kilit ekranı ve ana
ekran widget'ı yan yana görülebiliyor, iki ayrı normalize aynı portföy için
iki farklı eğri demek olurdu (`surface_parity_test` bunu kilitliyor).

**Widget önerisi ilk varlıktan sonra çıkar, önce değil.** Öncesinde widget
boş görünürdü ("—") ve kullanıcı işe yaramadığını düşünüp kaldırırdı. Bir
kez gösterilir; izin isteminden bir kare sonra açılır ki sistem izin
diyaloğu sheet'in üstüne binmesin.

**İzin isteminin iki kolu birbirini dışlar:** bayrak açıkken ana ekrandaki
2 saniyelik istem devre dışı kalır. İkisi birden çalışsaydı kullanıcı izni
ilkinde reddeder ve bağlamlı istem hiç gösterilemezdi — Android izni ikinci
kez sormaz.

### Sprint 2 — başladı (2026-09-06)

| Ne | Bayrak | Nerede | Durum |
|---|---|---|---|
| Reel getiri (TÜFE) rozeti | `real_return_enabled` | `lib/services/inflation_service.dart`, `lib/widgets/real_return_strip.dart` *(yeni)*, `0045_inflation_index.sql` | ✅ kod |
| TÜFE endeks verisi | — | `inflation_index` tablosu | ⛔ **boş** — elle doldurulacak |
| **Fiyat alarmları** | `free_price_alert_limit` | `supabase/functions/check-price-alerts/`, `0046_price_alerts.sql`, `lib/screens/price_alerts_screen.dart` *(yeni)* | ✅ |
| Kilometre taşları | — | — | ⛔ |
| Takvim kancaları (TÜİK günü, maaş günü…) | — | — | ⛔ |

**Endeks değerleri bilerek doldurulmadı.** Yanlış bir TÜFE, portföy
getirisini olduğundan iyi ya da kötü gösterir; kullanıcı bunu TÜİK'in
açıkladığı rakamla karşılaştırdığında uygulamaya güveni gider. §1'deki
"yanlış ölçüm, ölçüm yokluğundan kötüdür" kuralı burada da geçerli, üstelik
sonucu kullanıcıya görünür. Tablo boşken rozet hiç çizilmiyor; doldurma
yönergesi `YAPMAN_GEREKENLER.md`'de.

**Endeks DEĞERİ saklanıyor, aylık yüzde değil.** İki tarih arası enflasyon
tek bölmeyle çıkıyor (`son / ilk - 1`); yüzde saklansaydı aradaki bütün
ayları çarpmak gerekir ve her ay bir yuvarlama hatası eklenirdi.

**Rozet "puan farkı" gösteriyor, bileşik reel getiri değil.** Gündelik dilde
okunan sayı bu ("TÜFE'yi 6,4 puan geçti"). İkisi yüksek enflasyonda ayrışır
— %46,4 nominal / %40 enflasyonda puan farkı 6,4 ama alım gücü artışı ~%4,6
— bu yüzden `realReturnPct` de serviste duruyor ve testlerle kilitli.
Rozetin sağında ham iki sayı da veriliyor: kullanıcı farkı doğrulayabilmeli.

**Fiyat alarmı, kaynağı istemciyle aynı tutmak zorunda.** Altın ve döviz
için `truncgil`, geri kalanı için Yahoo — yani uygulamanın kendi kaynakları.
Farklı bir kaynak kullansaydık kullanıcı ekranda 5.401 görürken 5.400
alarmının çalışmadığını fark eder ve haklı olarak "bozuk" derdi. Aynı sebeple
`price_history.ts` kullanılmadı: o modül günlük kapanış tutuyor ve 12 saatlik
cache'i var; "gram altın 5.400 olunca" diyen kullanıcı ertesi günü beklemez.

**En sinsi hata kaynağı sayı biçimiydi.** truncgil "5.412,37" gönderiyor;
düz `parseFloat` bunu **5.412** okur — bin katı hatalı bir fiyat ve sessizce
yanlış tetiklenen bir alarm. `parseTruncgilNumber` bunun için ayrı bir
fonksiyon ve testli.

**Alarm tek atış.** Hedefin etrafında salınan bir fiyat, tekrar eden alarmda
yarım saatte bir bildirim üretirdi. Damga bildirimden ÖNCE yazılır: ters
sırada, push gidip damga yazılamazsa kullanıcı her turda aynı bildirimi
alırdı — geri alınamaz olan bu.

**Sıra kasıtlı:** reel getiri şeridi percentile'den ÖNCE. "Eridim mi?"
sorusu "başkalarına göre nerdeyim?" sorusundan önce gelir — biri alım gücü,
diğeri sosyal karşılaştırma.

### Guardrail metrikleri (bunlar bozuluyorsa mekanik zararlıdır)
- Push opt-out oranı (haftalık) — %2/hafta üstü alarm
- Uygulama silme (uninstall) — Firebase `app_remove`
- Oturum başına süre **düşerken** oturum sayısı artıyorsa: anksiyete üretiyorsun, değer değil
- Sinyal bildirim sonrası varlık silme oranı

---

## 2. Kanıt tabanı — hangi sayılara yaslanıyoruz

Bu bölümdeki her sayı kaynaklı. Satıcı pazarlama iddiası olanlar **[satıcı]** ile işaretli.

| Bulgu | Sayı | Kaynak |
|---|---|---|
| Fintech D1 tutunma ortalaması | ~%28; bölgesel: Avrupa %17, MENA %18 | Adjust/UXCam derlemeleri, 2026 |
| Fintech D7 | ~%18 | aynı |
| Finans dikeyi D30 | Adjust 2026: **%2** (bir önceki yıl %3) — abonelikli uygulamalarda %10-15 | Adjust Mobile App Trends 2026 |
| Abonelikli vs reklamlı D30 | %14 vs %5,4 | Adjust 2026 |
| **Finans uygulamalarında push opt-in** | **%72,3** — tüm dikeylerin en yükseklerinden | Airship Push Benchmarks 2025 |
| Finans/bankacılık direct open rate | Android %8,8 / iOS %7,2 (jenerik kampanya) | Airship 2025 |
| Duolingo: 1 yıldan uzun streak'i olan kullanıcı | 10M+; DAU'nun 1/3'ünde Friend Streak | Duolingo Q4 2024 hissedar mektubu |
| Duolingo DAU/MAU | %34,7 (YoY +4 puan) | aynı |
| Duolingo "Streak Revival" tek seferlik kampanya | 15M+ kullanıcı streak'ini geri kazandı | aynı |
| Spotify Wrapped 2025 | ilk 24 saatte 200M+ kullanıcı (+%19 YoY), 500M+ paylaşım (+%41) | TechCrunch, Ara 2025 |
| Wrapped 2020'nin indirmeye etkisi | Aralık ilk haftası indirmelerde %21 artış | sektör analizleri |
| Android widget kullanıcılarında tutunma | %25 daha yüksek (Gratitude uygulaması vakası) | Google Android Developers vaka çalışması **[satıcı/vaka]** |
| Referral ile gelen kullanıcı | %18-25 daha az churn, ~%25 daha yüksek LTV | fintech referral derlemeleri **[satıcı]** |
| Referral CAC vs paid CAC | %50-70 daha düşük | aynı **[satıcı]** |
| **Sık portföy kontrolünün getiriye etkisi** | En çok işlem yapan hane %11,4/yıl; en az işlem yapan %18,5; piyasa %17,9 | Barber & Odean, 66.465 hane, 1991-96 |
| Robinhood gamification uzlaşması | 7,5M$ idari para cezası + dijital etkileşim pratiklerinde değişiklik | Massachusetts Securities Division consent order, Oca 2024 |
| Türkiye pay senedi yatırımcı sayısı | **6,78 milyon** (4 Eyl 2026), yıl içinde 6,4M→6,8M | MKK verileri |
| 2026 halka arzlarına katılım | 34 şirket, 25,79M yatırımcı katılımı | MKK |
| Türkiye'de yastık altı altın | 600-750 milyar $ (GSYH'nin ~yarısı) | TCMB Başkanı açıklaması / Reuters |

**Dikkat:** D30 rakamlarında kaynaklar çelişiyor (%2 ile %15 arası). Sektör benchmark'ı
yön verir, **hedef koymaz**. Kendi taban çizgini 4 hafta ölçüp ona göre hedef koy.

---

## 3. Stratejik çerçeve: tracker'da "günlük iş" nereden gelir?

Kullanıcının uygulamada yapacak işi yoksa, uygulamanın kullanıcıya **söyleyecek sözü**
olmalı. Söz üç kaynaktan gelir:

```
1. PİYASA         → fiyat hareketi, sinyal, alarm, seans açılış/kapanış
2. KULLANICININ   → kilometre taşı, percentile, dağılım kayması, TÜFE karşılaştırması
   KENDİ VERİSİ      (bu senin tekelin — rakip aynı veriyi üretemez)
3. TAKVİM         → TÜİK enflasyon, maaş günü, bayram, temettü, beyanname
```

**Kural:** Her geri çağırma bir *bilgi* taşımalı. "Sandık'ı açmayı unutma" değil,
"portföyün bu ay TÜFE'yi 4,2 puan geçti" — ikincisi açılmadan bile değer veriyor,
ve tam bu yüzden açtırıyor.

---

## 4. Mevcut altyapı envanteri — neyi bedavaya kullanabilirsin

| Var olan | Dosya | Retention'da kullanımı |
|---|---|---|
| Firebase Analytics | `lib/services/analytics_service.dart` | Event tabanı — genişletilecek |
| Remote Config (9 flag, `paywall_variant` dahil) | `lib/services/remote_config_service.dart` | **A/B testi bedava** — her mekanik flag arkasında |
| FCM + payload routing | `lib/services/notification_service.dart` | Yeni bildirim tipleri aynı yola takılır |
| **pg_cron kurulu** | `supabase/migrations/0033_live_activity_cron.sql` | Yeni zamanlanmış iş marjinal maliyet |
| Edge Functions (6 adet) | `supabase/functions/` | `analyze-signals` deseni kopyalanabilir |
| Home widget (601 satır, sparkline) — **yalnızca Android** | `lib/services/home_widget_service.dart` | **İzin gerektirmeyen 2. kanal** |
| iOS Live Activity (764 satır) | `lib/services/live_activity_service.dart` | Seans boyu kilit ekranında varlık |
| **k-anonim percentile RPC** (k 20→8, bkz. 0031) | `0012_leaderboard_snapshots.sql` | Yarış ekranında teaser var; **ana ekranda yok, ölçülmüyor** |
| `snapshots` (user_id, ts, JSONB) | `supabase_schema.sql:40` | Recap/özet için ham veri |
| Partner/aile paylaşımı | `partnerships`, `partner_invites` | Referral ve sosyal bağ |
| Watchlist | `0043_watchlist.sql` | Alarm için doğal yer |

**Eksik:** streak/rozet tablosu, haftalık özet push, recap, referral ödülü, retention event'leri.

---

## 5. Mekanikler

Her mekanik: **ne → kanıt → sandık'ta nasıl → kod dokunuşu → efor → risk**.
Efor: S (≤2 gün), M (3-5 gün), L (1-2 hafta).

---

### A. Sabah Brifingi — kişiselleştirilmiş tek satır (⭐ en yüksek öncelik)

**Ne:** Seans açılmadan (TR 09:45) veya kapandıktan sonra (18:20) tek bir push:
kullanıcının **kendi** portföyüne dair bir cümle. Jenerik değil, hesaplanmış.

Örnek varyantlar (Remote Config ile A/B):
- `"Portföyün dün %1,8 arttı. En çok katkı: ASELS (+%4,2)"`
- `"Altın tarafın 3 gündür yükselişte, portföyünün %38'i orada"`
- `"Bu ay ilk kez 250.000 ₺'yi geçtin"`
- `"USD pozisyonun bu hafta TÜFE'nin 1,1 puan altında kaldı"`

**Kanıt:** Finans uygulamalarında push opt-in %72,3 — kanal zaten açık, sorun içerik.
Jenerik kampanyalarda direct open %7-9 bandında; kişiselleştirilmiş insight bunun
belirgin üstünde çalışır (kendi A/B'inle doğrula, dışarıdan sayı alma).

**sandık'ta nasıl:** `analyze-signals` deseninin birebir kopyası. pg_cron → Edge Function
→ kullanıcı başına son iki `snapshots` satırını oku → en büyük katkıyı bul → FCM.

**Kod dokunuşu:**
- Yeni Edge Function: `supabase/functions/daily-brief/index.ts`
- Yeni migration: `00XX_daily_brief_cron.sql` (`45 6 * * 1-5` UTC = TR 09:45)
- `notification_service.dart` → yeni tip `daily_brief`, payload `daily_brief:<date>`
- Remote Config: `daily_brief_enabled`, `daily_brief_variant`, `daily_brief_hour`

**Efor:** M
**Risk:** Düşük. **Şart:** günde **tek** brifing. İki olursa opt-out yükselir.

---

### B. Widget'ı birinci sınıf retention kanalı yap (⭐ en düşük maliyet/en yüksek getiri)

**Ne:** Widget zaten var ama (a) kurulum oranı ölçülmüyor, (b) kullanıcıya hiç
önerilmiyor, (c) dokunma ile açılma atfedilmiyor.

**Kanıt:** Google'ın Gratitude vakasında widget kullanıcılarında **%25 daha yüksek
tutunma**. Mekanizma açık: widget, bildirim izni gerektirmeyen kalıcı bir yüzeydir ve
ana ekranda **marka varlığı** kurar. Push'u kapatan kullanıcıya ulaşan tek kanaldır.

**sandık'ta nasıl:**
1. **Kurulum funnel'ı:** İlk varlık eklendikten sonra (kutlama anında) tek seferlik
   bottom sheet: "Portföyünü ana ekranda gör" + platforma özel 3 adımlık görsel anlatım.
   iOS 16+ `WidgetCenter` ile kurulu widget sayısı okunabilir → `logWidgetInstalled`.
2. **Deep link atfı:** Widget dokunuşu `sandik://widget/home` ile açılsın,
   `logAppOpen(source: 'widget')`.
3. **Widget'ı değerli tut:** Şu an toplam + değişim + sparkline var. Ekle: **günün en çok
   katkı yapan varlığı** ve TÜFE karşılaştırma rozeti. Widget'ın silinmemesinin tek
   sebebi, bakınca bir şey öğrenmektir.
4. **iOS 18 Control / Kilit ekranı widget'ı** — `accessoryRectangular` ailesi zaten
   `home_widget` paketi ile erişilebilir.

**Kod dokunuşu:** `lib/services/home_widget_service.dart` (veri alanları),
`lib/screens/add_asset_screen.dart` (kurulum önerisi tetikleyicisi),
iOS `SandikWidget` extension, Android `SandikWidgetProvider`.

**Efor:** S (ölçüm + öneri) / M (içerik zenginleştirme)
**Risk:** Yok.

---

### C. Fiyat alarmı — kullanıcının kendi kurduğu tetikleyici

**Ne:** "Gram altın 5.400 ₺ olunca haber ver", "THYAO %5 düşerse haber ver".

**Neden en yüksek niyetli push budur:** Kullanıcı bildirimi **kendisi** istedi. Opt-out
riski yok, alaka garantili, ve alarm kuran kullanıcı uygulamayı "kurulu bırakma" sebebi
edinir. Fintables'ın öne çıkardığı özellik de tam olarak bu (fiyat alarmı + hisse bazlı
gelişme takibi) — Türkiye pazarında beklenen bir yetenek hâline gelmiş durumda.

**sandık'ta nasıl:** `watchlist` tablosu zaten var; alarm satırı oradan türer.
Fiyat kontrolü `price_service` verisiyle mevcut `*/5 * * * *` cron'a eklenir —
yeni altyapı gerektirmez.

**Kod dokunuşu:** yeni migration `price_alerts` tablosu (RLS'li),
`supabase/functions/check-price-alerts/index.ts`, `watchlist_detail_screen.dart` UI,
`notification_service.dart` → tip `price_alert`.

**Efor:** M
**Risk:** Düşük. Alarm sayısını sınırla (free 3 / premium sınırsız — paywall için doğal kanca).

---

### D. Streak — ama "giriş serisi" değil

**Ne yapmamalı:** "Uygulamayı 7 gün üst üste aç" streak'i. Bu, tracker'da **hollow
engagement**tir: kullanıcı hiçbir değer üretmeden açar, kapatır; sen DAU'yu şişirirsin
ama tutunma gerçek değildir. Dahası — Barber & Odean verisi net: en çok bakan/işlem
yapan hane %11,4 kazanırken en az bakan %18,5 kazanmış. **Kullanıcıyı her gün baktırmak,
onun getirisine zarar veren bir hedeftir.** Buna hizmet eden bir metrik kovalamak,
uzun vadede uygulamanın itibarını yer.

**Ne yapmalı — üç meşru varyant:**

1. **"Portföyün güncel" serisi (veri bütünlüğü streak'i).**
   Sayaç, kullanıcının portföyünün *doğru* olduğu ardışık **hafta** sayısını sayar.
   Haftada bir "değişen bir şey var mı?" sorusuna "hayır, aynı" demek de seriyi sürdürür.
   Ödül: veri doğruluğu → grafiklerin ve TÜFE karşılaştırmasının anlamlı olması.
   Duolingo'nun streak freeze'i buraya birebir uyar: **ayda 2 pas hakkı**, kırılmayı
   affetmek streak'in anksiyete üretmesini engeller. Duolingo'nun tek seferlik "Streak
   Revival" kampanyasında 15M+ kullanıcının serisini geri kazanması, **affetmenin
   cezalandırmadan daha çok tutunma ürettiğinin** kanıtı.

2. **Aylık katkı serisi (birikim ritmi).** "Bu ay portföyüne ekleme yaptın" — art arda
   kaç ay. Bu, kullanıcının **finansal olarak lehine** olan davranışı ödüllendirir.
   Sende `add_deposit_screen` ve `deposits_enabled` flag'i zaten duruyor.

3. **Partner/aile serisi.** İki kişinin de aktif olduğu hafta sayısı. Sosyal streak,
   bireysel streak'ten daha güçlüdür (Duolingo'da DAU'nun 1/3'ü Friend Streak'te).

**Kod dokunuşu:** `user_streaks` tablosu (`user_id, kind, current, longest,
last_period, freezes_left`), `home_screen.dart` header'da sayaç,
`streak_provider.dart`.

**Efor:** M
**Risk:** Orta. **Ton kuralı:** fintech tonunda kal, çocuk emojisi yağmuru yok.
Streak kırılınca **suçlayıcı dil yasak** ("kaybettin" değil, "seriye yeniden başladın").

---

### E. Kilometre taşı kutlamaları — Türkiye'ye özel olanlarla

**Ne:** Portföy bir eşiği geçtiğinde tek seferlik, ölçülü bir kutlama.

**Neden işe yarar:** Endowed progress + kimlik. Kullanıcı "yatırımcı olduğunu" hisseder.
**Neden Robinhood'un confetti'sinden farklı:** Robinhood **işlem başına** kutluyordu —
yani riskli davranışı ödüllendiriyordu; Massachusetts uzlaşması (7,5M$) tam olarak
bunu hedef aldı. Senin kutladığın şey **birikim**, işlem değil. Bu ayrım hem etik hem
hukuki olarak belirleyicidir ve raporlanabilir olmalı.

**Türkiye'ye özel eşikler (rakipte yok, kültürel olarak yankılanır):**
- "İlk çeyreğin" / "10 çeyrek altın oldun" / "Bir tam altına ulaştın"
- "Bir Cumhuriyet altını değerinde birikimin var"
- "Asgari ücretin X katı portföy"
- "Portföyün 1 yaşında" (yıl dönümü — güçlü duygusal kanca)
- "İlk 100.000 ₺", "İlk 1 milyon ₺"

**Kod dokunuşu:** `milestones` tablosu (idempotent — aynı eşik iki kez kutlanmaz),
`home_screen.dart` bottom sheet, `analytics: logMilestoneReached`.

**Efor:** M
**Risk:** Düşük. Frekans sınırı koy: ayda en fazla 1 kutlama.

---

### F. Percentile karşılaştırma — altyapı hazır, kullanılmıyor (⭐ hızlı kazanç)

**Ne:** "Son 30 günde senin gibi yatırımcıların %72'sinden iyi getirdin."

**Neden liderlik tablosundan iyi:** Para miktarı üstünden liderlik tablosu Türkiye'de
mahremiyet açısından da motivasyon açısından da riskli (kimse portföy büyüklüğünü
göstermek istemez, ve alttakiler demotive olur). **Anonim yüzdelik dilim** ise
sosyal karşılaştırmanın motive eden yarısını verir, utandıran yarısını vermez.

**Kritik avantaj:** `get_percentile_bucket` RPC'si **zaten var**, k≥20 anonimlik
korumasıyla, RLS'li, ham satır sızdırmıyor (`0012_leaderboard_snapshots.sql`,
`0029_harden_leaderboard_rpcs.sql`). Yani bu mekaniğin backend'i bitmiş durumda.

**sandık'ta nasıl:** Ana ekranda haftada bir görünen ince bir şerit + haftalık özet
push'unda tek satır. Getiri değil **dilim** göster; mutlak tutar asla.

**Kod dokunuşu:** `lib/services/leaderboard_service.dart` (RPC çağrısı var),
`home_screen.dart` şerit, `logPercentileViewed`.

**Efor:** S
**Risk:** Düşük — ama alt dilimdekilere gösterirken dili dikkatli kur
("%30'undasın" yerine "portföyünü çeşitlendirmek dilimini yükseltebilir").

---

### G. "sandık Özeti" — aylık + yıllık recap (⭐ viral motor)

**Ne:** Spotify Wrapped formatının finansal karşılığı. Aylık kısa, yıllık büyük.

**Kanıt:** Wrapped 2025 ilk 24 saatte 200M+ kullanıcı, 500M+ paylaşım (+%41 YoY);
2020 sürümü Aralık ilk haftası indirmelerde %21 artış üretti. Monzo "Year in Monzo"
ile aynı formatı bankacılığa taşıdı. **Mekanizma:** insanlar veriyi değil **kimliği**
paylaşır — sen ona kendini anlatacak malzeme verirsin, karşılığında organik erişim alırsın.

**sandık'ta içerik (her biri `snapshots`'tan hesaplanabilir):**
- Yılın en iyi ve en kötü kararı (en çok/az getiren varlık)
- "Portföyünün karakteri": Altıncı / Dövizci / Hisseci / Dengeli — **kimlik etiketi,
  paylaşılabilirliğin çekirdeği budur**
- TÜFE'yi kaç puan geçtin
- Kaç gün takip ettin, kaç kez ekleme yaptın
- En sabırlı varlığın (en uzun tutulan)
- Yıl boyu portföy eğrisi (tek grafik)

**Paylaşım kartı:** `share_plus` zaten bağımlılıklarda. Kart **tutar içermemeli** —
yüzde ve etiket yeter. Tutarsız kart paylaşılabilir; tutarlı kart paylaşılmaz.

**Zamanlama:** Aylık → ayın 1'i sabahı. Yıllık → **31 Aralık değil, 26-28 Aralık**
(Wrapped'in erken çıkma sebebi: yıl sonu gürültüsünden önce olmak).

**Kod dokunuşu:** `supabase/functions/generate-recap/index.ts`,
yeni ekran `lib/screens/recap_screen.dart` (hikâye formatı, tam ekran sayfalar),
`logRecapViewed` / `logRecapShared`.

**Efor:** L
**Risk:** Düşük — ama **zarar eden yılda gönderme.** Monzo Wrapped'in eleştirildiği
nokta buydu: kötü haberi kutlama formatında sunmak. Kayıptaysa ton değişmeli
("zor bir yıldı, ama şunları doğru yaptın").

---

### H. Enflasyon karşılaştırması — en güçlü yerel diferansiyatörün (⭐)

**Ne:** "Portföyün bu yıl TÜFE'yi 6,4 puan geçti."

**Neden bu, Türkiye'de her şeyden önemli:** Türk tasarrufçusunun asıl sorusu "kaç para
kazandım" değil, **"eridim mi?"**. Yastık altındaki 600-750 milyar $'lık altın stoğunun
sebebi de bu. Hiçbir rakip (Midas, Foreks, Fintables, Investing TR) bunu portföy
seviyesinde birinci sınıf metrik yapmıyor — hepsi nominal getiri gösteriyor.

**Ürün karşılığı:**
- Ana ekranda nominal getirinin yanında **reel getiri** rozeti
- Widget'ta TÜFE rozeti
- Her ayın **3'ü, saat 10:00**'da TÜİK enflasyonu açıklanır → o gün 10:15'te push:
  "Enflasyon açıklandı: %X. Portföyün bu ay Y puan önde." **Bu, ulusal bir dikkat anına
  meşru şekilde bağlanmaktır** — uydurulmuş bir bildirim sebebi değil.
- Yıllık recap'te bir sayfa

**Kod dokunuşu:** TÜİK TÜFE serisi (aylık, EVDS API ya da manuel besleme) →
`inflation_index` tablosu; `portfolio_provider.dart`'a reel getiri hesabı;
cron `0 7 3 * *` (UTC) → push.

**Efor:** M
**Risk:** Düşük. Metodolojiyi ekranda açıkla (hangi endeks, hangi dönem) — güven meselesi.

---

### I. Türkiye takvimi — meşru geri çağırma anları

Bildirim için sebep uydurmak yerine, ülkenin zaten baktığı anlara bağlan:

| An | Zaman | Mesaj |
|---|---|---|
| **TÜİK enflasyon** | Her ayın 3'ü 10:00 | Reel getiri karşılaştırması (§H) |
| **Maaş günü** | Ayın 1'i / 15'i (kullanıcı seçer) | "Bu ay portföyüne ekleme yaptın mı?" — katkı serisi (§D.2) |
| **Asgari ücret / zam sezonu** | Aralık-Ocak | "Portföyün asgari ücretin X katı" |
| **Bayram + düğün sezonu** | Ramazan/Kurban, yaz | Altın hediyesi girişi: "Bayramda altın aldıysan portföye ekle" |
| **Temettü sezonu** | Mart-Haziran (BIST) | `dividend_dialog.dart` zaten var — hatırlatmaya bağla |
| **Gelir vergisi beyannamesi** | Mart | Yıllık kâr-zarar özeti (premium PDF için doğal kanca) |
| **Seans açılış/kapanış** | 10:00 / 18:10 | Live Activity zaten bu pencerede çalışıyor |

**Efor:** S (her biri ayrı ayrı, cron + şablon)
**Risk:** Düşük — **ama toplam bildirim bütçesini aşma** (§7).

---

### J. Referral — mevcut partner sistemi üstüne kur

**Ne:** Davet ettiğin kişi 7 gün aktif kalırsa ikinize de ödül.

**Kanıt:** Referral ile gelen kullanıcılar %18-25 daha az churn ediyor, LTV'leri ~%25
yüksek; referral CAC paid CAC'ın %50-70 altında **[satıcı verisi, temkinli oku]**.
Nubank'ın ilk 350.000 kredi kartı müşterisi ağırlıkla referral'dan geldi.
Türkiye'de tavsiye-güven ilişkisi güçlü; bu kanal burada ortalamanın üstünde çalışır.

**sandık'ta nasıl:** `partner_invites` + `accept-invite` + `redeem-invite-code` zaten var.
Eksik olan tek şey **ödül**: `referrals` tablosu + 7 günlük aktivite kontrolü + 1 ay premium.

**Kod dokunuşu:** `referrals` tablosu, `supabase/functions/check-referral-activation`,
`profile_screen.dart` referral kartı.

**Efor:** M (paywall açıldıktan sonra anlamlı — `paywall_enabled` şu an `false`)
**Risk:** Düşük. Ödülü **premium ay** olarak ver, nakit verme (SPK/vergi karmaşası).

---

### K. Aktivasyon — ilk 10 dakika her şeydir

D30 tutunmanın en güçlü tahmincisi ilk oturumdaki davranıştır. Sende ölçülmüyor, ama
hipotez net ve test edilebilir:

**Aktivasyon hipotezi:** *İlk oturumda ≥3 varlık eklemiş VE push izni vermiş kullanıcı,
D30'da diğerlerinin 3-5 katı tutunur.*

Bunu ölçtükten sonra onboarding'i tek hedefe odakla:
- `onboarding_screen.dart` sonunda **varlık ekleme boş ekranıyla bırakma** —
  "portföyünde ne var?" diye 3 hızlı seçim sun (altın / dolar / hisse), tek dokunuşla ekle
- `bulk_add_asset_screen.dart` zaten var — onboarding'e bağla
- **Push izni zamanlaması:** açılışta değil, **ilk varlık eklendikten sonra** iste
  ("ASELS %5 hareket ederse haber verelim mi?"). İzin oranını belirgin yükseltir.
- Widget önerisini de buraya koy (§B)

**Efor:** M
**Risk:** Düşük — en yüksek getirili işlerden biri.

---

### L. Aile/partner — Türkiye'de en güçlü bağ

Partner paylaşımı zaten var ve **rakiplerde yok**. Retention açısından sosyal bağ,
bireysel mekaniklerin hepsinden güçlüdür: uygulamayı silmek artık tek kişilik bir karar
değildir.

**Yapılacaklar:** partner aktivitesi bildirimi ("eşin portföye altın ekledi"),
ortak kilometre taşı ("birlikte 500.000 ₺'yi geçtiniz"), ortak recap sayfası,
partner serisi (§D.3).

**Efor:** M
**Risk:** Mahremiyet. Neyin paylaşıldığı **her zaman** açık olmalı, tek dokunuşla kapanmalı.

---

## 6. Öncelik sırası (ICE)

Impact × Confidence / Effort. 1-10 ölçek.

| # | Mekanik | I | C | E | Skor | Faz |
|---|---|---|---|---|---|---|
| 1 | Retention event'leri + aktivasyon ölçümü (§1) | 9 | 10 | 2 | **45** | 0 |
| 2 | Percentile şeridi — RPC hazır (§F) | 6 | 8 | 2 | **24** | 1 |
| 3 | Widget kurulum funnel'ı + atıf (§B) | 8 | 7 | 3 | **19** | 1 |
| 4 | Sabah brifingi push (§A) | 9 | 7 | 4 | **16** | 1 |
| 5 | Onboarding aktivasyon akışı (§K) | 9 | 7 | 4 | **16** | 1 |
| 6 | Enflasyon karşılaştırması + TÜİK günü push (§H) | 9 | 7 | 4 | **16** | 2 |
| 7 | Fiyat alarmları (§C) | 8 | 8 | 4 | **16** | 2 |
| 8 | Kilometre taşları (§E) | 7 | 7 | 3 | **16** | 2 |
| 9 | Takvim kancaları (§I) | 6 | 6 | 3 | **12** | 2 |
| 10 | Partner etkileşimi (§L) | 7 | 6 | 4 | **11** | 3 |
| 11 | Streak (veri bütünlüğü / katkı) (§D) | 6 | 5 | 4 | **8** | 3 |
| 12 | Aylık + yıllık recap (§G) | 9 | 7 | 8 | **8** | 3 |
| 13 | Referral ödülü (§J) | 7 | 6 | 6 | **7** | 4 (paywall sonrası) |

### Üç sprintlik plan

**Sprint 0 — Ölçüm (3-5 gün).** Event seti, user property'ler, Firebase kohort
panoları, 2 hafta taban çizgisi topla. *Bu bitmeden Sprint 1'e geçme.*

**Sprint 1 — Kanalları aç (2 hafta).** Percentile şeridi → widget funnel'ı →
onboarding aktivasyon → sabah brifingi. Hepsi Remote Config flag'i arkasında,
%50 trafikle A/B.

**Sprint 2 — Yerel değer (2 hafta).** Enflasyon karşılaştırması + TÜİK günü,
fiyat alarmları, kilometre taşları, takvim kancaları.

**Sprint 3 — Derinlik (2-3 hafta).** Partner etkileşimi, streak, recap.
Recap'i Aralık'a yetiştirmek istiyorsan Sprint 3'ü Ekim'de başlat.

---

## 7. Bildirim bütçesi — tek en önemli kısıt

Finans uygulamalarında opt-in %72,3 ile en yüksek dikeylerden biri. **Bu bir emanet.**
Bir kez kaybedersen geri gelmez: opt-out tek yönlüdür.

**Kural seti:**
- **Haftalık tavan: 5 bildirim.** Sinyal push'ları buna dahil.
- **Günde en fazla 1** proaktif (kullanıcının kendi kurduğu alarm hariç).
- Sessiz saatler: 22:00-08:00 kesin yasak.
- Her bildirim tipi **ayrı Android kanalı** + iOS'ta ayrı ayar → kullanıcı hepsini
  değil, sadece rahatsız edeni kapatabilsin. Tek kanal = tek "kapat" = tüm kanal kaybı.
- **Time Sensitive** interruption level sadece fiyat alarmı için; brifing ve özet
  normal seviyede kalsın (yoksa iOS Notification Summary'ye düşerler ama rahatsız
  etmezler — bu doğru davranış).
- Her tip için `logNotificationOpened` → 4 hafta boyunca açılma oranı %3'ün altında
  kalan tipi **kapat**.

---

## 8. Yapılmayacaklar listesi (bu bölüm en az diğerleri kadar önemli)

| Yapma | Neden |
|---|---|
| İşlem/ekleme başına confetti | Robinhood'un Massachusetts uzlaşması (7,5M$, Oca 2024) tam olarak "işlem başına confetti + kazı-kazan + bekleme listesinde sıra atlatma" pratiklerini hedef aldı. Sen kutlarsan **birikimi** kutla, eylemi değil. |
| Para tutarı üstünden liderlik tablosu | Mahremiyet riski + alttakileri demotive eder. Anonim yüzdelik dilim aynı motivasyonu üretir, zararı üretmez. |
| "Günde 3 kez bak" teşviki | Barber & Odean: en çok işlem yapan hane %11,4, en az yapan %18,5 kazandı. Sık baktırmak kullanıcının getirisine zarar verir. Myopic loss aversion: sık bakan daha çok küçük kayıp görür, riskten kaçar, daha az kazanır. |
| Kayıp gününde "portföyün düştü!" push'u | Kayıp anında bildirim panik satışı tetikler. Düşüş günlerinde **sus** ya da bağlam ver ("bu ay hâlâ +%3"). |
| Sinyal push'unu artırmak | Zaten günde 2 slot var. Daha fazlası hem SPK açısından hem opt-out açısından riskli. |
| Yapay kıtlık / geri sayım / FOMO | Fintech'te güveni yer. Sandık'ın konumu "sakin, güvenilir kasa". |
| Çocuksu emoji/rozet yağmuru | `MONETIZATION_ROADMAP.md`'de de not düşülmüş — fintech tonu korunmalı. |

---

## 9. Regülasyon ve etik çerçeve

**SPK.** Uygulama teknik AL/SAT sinyali push'luyor. SPK'nın Yatırım Hizmetleri ve
Kuruluşları Rehberi'ne göre bu içerikler yatırım danışmanlığı kapsamına girmemeli
ve genel nitelikte olmalı; standart uyarı metni ("Burada yer alan yatırım bilgi, yorum
ve tavsiyeleri yatırım danışmanlığı kapsamında değildir…") görünür olmalı.
Kodda `disclaimer_service.dart` + `disclaimer_acceptances` tablosu var — **her yeni
bildirim tipinde bu metnin kapsamının hâlâ geçerli olduğunu kontrol et.** Özellikle
kişiselleştirme arttıkça ("senin portföyün için…") "kişiye özel tavsiye" sınırına
yaklaşırsın. Güvenli çizgi: **durum bildir, eylem önerme.**
"Portföyünün %38'i altında" ✅ — "Altın al" ❌.

**Uluslararası emsal.** Massachusetts–Robinhood consent order (7,5M$, Ocak 2024)
dijital etkileşim pratiklerini doğrudan menkul kıymet mevzuatı kapsamında ele aldı.
AB tarafında da MiFID çerçevesinde gamification tartışması sürüyor. Türkiye'de henüz
bu konuda özel bir düzenleme yok — ama gelirse ilk bakılacak şey **etkileşim
mekaniklerinin işlem davranışını nasıl etkilediği** olur. Bugünden "birikimi ödüllendir,
işlemi ödüllendirme" ilkesine oturursan, düzenleme geldiğinde uyumlusun.

**KVKK.** Yeni event'ler davranışsal veri üretiyor. Aydınlatma metnine
"uygulama içi kullanım analizi" kalemini ekle; `AnalyticsService` zaten debug'da
kapalı, ayrıca kullanıcıya **kapatma seçeneği** sun (`settings_screen.dart`).

**Etik test — her mekanik için sor:** *Bu, kullanıcının finansal olarak lehine olan
davranışı mı ödüllendiriyor, yoksa sadece benim metriğimi mi?*
Birikim, çeşitlendirme, veri güncelliği, sabır → lehine.
Sık bakma, panik, işlem sıklığı → değil.

---

## 10. "CPI" Cost Per Install anlamındaysa

Retention doğrudan CPI'yı düşürmez — ama iki yoldan CPI ekonomisini değiştirir:

1. **LTV yükselir → aynı CPI'ya daha fazla ödeyebilirsin.** Abonelikli uygulamalarda
   D30 %14 iken reklamlıda %5,4. Paywall açıldığında (`paywall_enabled`) tutunma
   doğrudan LTV'ye çevrilir; LTV/CAC oranı 3'ün üstündeyse ödenen CPI ne olursa olsun
   sürdürülebilirdir.
2. **Blended CPI düşer.** Referral (§J) ve recap paylaşımı (§G) organik kurulum getirir;
   organik kurulumlar blended CPI'yı aşağı çeker. Wrapped'in Aralık indirmelerine %21
   katkısı bunun ölçeklenmiş örneği.
3. **ASO ikinci kanal:** Türkiye'de arama hacmi "altın fiyatları", "dolar kuru",
   "portföy takip", "borsa" etrafında. Widget ve enflasyon karşılaştırması store
   ekran görüntülerinde öne çıkarılabilir — bunlar rakipte olmayan görsellerdir.

---

## 11. Rakip konumlandırma notu

| Rakip | Ne yapıyor | Sende olmayan | Sende olan / onda olmayan |
|---|---|---|---|
| **Midas** | SPK lisanslı aracı kurum, BIST + ABD, sıfır komisyon | Gerçek işlem | Sen tracker'sın — **tüm** varlıkları (fiziksel altın dahil) tek yerde görürsün |
| **Fintables** | Fon/hisse analizi, fiyat alarmı, sanal portföy, aracı kurum entegrasyonu | Fiyat alarmı (§C ile kapanır), fon derinliği | Fiziksel altın alt tipleri, partner paylaşımı |
| **Foreks / Matriks** | Profesyonel veri terminali | Veri derinliği | Temiz UX, kişisel portföy odağı |
| **Investing.com TR / Bigpara** | Genel finans içeriği | İçerik/haber | Kişisel portföy, TÜFE karşılaştırması |
| **Paramla / Finvestor** | Portföy takibi | — | Partner paylaşımı, sinyal, widget+Live Activity |

**Savunulabilir üç ada:**
1. Türk altın alt kategorileri (çeyrek/yarım/ata/reşat/cumhuriyet) — kimsede yok
2. Partner/aile portföyü — kimsede yok
3. **Reel getiri (TÜFE) birinci sınıf metrik** — henüz kimsede yok, en kolay kopyalanan
   da bu, o yüzden **önce sen yap**

---

## 12. Kaynaklar

- Adjust / UXCam — Mobile App Retention Benchmarks 2026: https://uxcam.com/blog/mobile-app-retention-benchmarks/
- Airship — Mobile App Push Notification Benchmarks 2025: https://www.airship.com/resources/benchmark-report/mobile-app-push-notification-benchmarks-for-2025/
- Airship — Push Notification Benchmarks 2026: https://www.airship.com/resources/mobile-app-push-notification-benchmarks-2026/
- Duolingo Q4/FY2024 hissedar mektubu: https://investors.duolingo.com/static-files/99006c40-d8cf-41ca-b5b1-c5cb1fa5ba88
- TechCrunch — Spotify Wrapped 2025, ilk gün 200M kullanıcı: https://techcrunch.com/2025/12/04/spotify-says-wrapped-2025-is-its-biggest-yet-with-200m-users-in-its-first-day
- Massachusetts–Robinhood uzlaşması (7,5M$), V&E analizi: https://www.velaw.com/insights/game-over-robinhood-pays-7-5-million-to-resolve-gamification-securities-violations/
- Bloomberg Law — Robinhood "gamification" iddiaları: https://news.bloomberglaw.com/securities-law/robinhood-accused-of-gamification-by-massachusetts-regulator
- Yale Law Journal — "On Confetti Regulation": https://yalelawjournal.org/essay/on-confetti-regulation-the-wrong-way-to-regulate-gamified-investing
- Berkeley Technology Law Journal — Gamification of Investments (US/EU): https://btlj.org/2025/11/the-gamification-of-investments-a-comparative-approach-between-the-us-and-eu/
- Myopic loss aversion / Barber & Odean derlemesi: https://www.behavioraleconomics.com/resources/mini-encyclopedia-of-be/myopic-loss-aversion/
- NBER — Myopic Loss Aversion and Investment Decisions: https://www.nber.org/system/files/working_papers/w28730/w28730.pdf
- MKK pay piyasası yatırımcı verileri (6,78M, Eylül 2026): https://www.borsagundem.com.tr/pay-piyasasinda-yatirimci-sayisi-678-milyona-ulasti
- SPK — Yatırım Hizmetleri ve Kuruluşları Rehberi (i-SPK.37.8, 10.03.2026): https://spk.gov.tr/data/61e496a11b41c60d1404d6b2/Yat%C4%B1r%C4%B1m%20Hizmetleri%20ve%20Kurulu%C5%9Flar%C4%B1%20Rehberi%20(i-SPK.37.8)%2010%2003%202026.pdf
- Yastık altı altın büyüklüğü (Reuters aktarımı): https://turkish.aawsat.com/ekonomi%CC%87/5245519-reuters-t%C3%BCrkiyede-%C3%A7o%C4%9Fu-yast%C4%B1k-alt%C4%B1ndaki-alt%C4%B1n%C4%B1n-de%C4%9Feri-750-milyar-dolar%C4%B1-a%C5%9Farak
- Fintables App Store sayfası: https://apps.apple.com/tr/app/fintables-borsa-hisse-ve-fon/id1632913774
- Midas App Store sayfası: https://apps.apple.com/tr/app/midas-borsa-hisse-al%C4%B1m-sat%C4%B1m/id1554268946
- Fintech referral benchmark derlemesi (satıcı verisi): https://growsurf.com/examples/fintech-referral-programs/
- Android widget tutunma vakası (Gratitude): https://studiomosaicapps.com/2025/02/13/increase-user-retention-and-engagement-using-app-widgets/

---

## Ek: Araştırma yöntemi ve sınırları

- Araştırma WebSearch ile yapıldı; bu oturumda WebFetch egress politikası nedeniyle
  kapalıydı, dolayısıyla **kaynak sayfalarının tam metni okunamadı** — arama sonucu
  özetleri ve alıntıları esas alındı. Kritik kararlardan önce ana kaynakları
  (özellikle Adjust ve Airship raporlarının PDF'lerini) doğrudan aç.
- Türk rakip uygulamalarının **App Store / Play puanları ve yorum sayıları
  doğrulanamadı** (mağaza sayfaları fetch edilemedi). Konumlandırma tablosu özellik
  düzeyinde, popülerlik düzeyinde değil.
- D30 benchmark'ında kaynaklar çelişiyor (%2 ile %15). Sektör sayısı yön verir,
  hedef koymaz — kendi taban çizgini ölç.
