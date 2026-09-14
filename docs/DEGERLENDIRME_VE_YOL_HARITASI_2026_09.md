# sandık — Uygulama Geneli Değerlendirme ve Yol Haritası

**Tarih:** 2026-09-13 · **Sürüm:** 1.1.4+7 · **Kapsam:** `lib/` (121 dosya, 62.303 satır),
`test/` (155 dosya), `supabase/` (47 migration, 11 edge function), platform kodu, kök dokümanlar.

**Yöntem:** Dört paralel inceleme (güvenlik, UX/UI tutarlılığı, mimari/kod kalitesi, ürün
envanteri). Her iddia kaynak kodda `dosya:satır` düzeyinde doğrulandı. Önceki denetimlerde
(`SECURITY_AUDIT_2026_08.md`, `UI_DERIN_INCELEME_RAPORU.md`, `DESIGN_REVIEW.md`) kapatılmış
maddeler tekrar edilmedi; yalnızca **hâlâ açık** veya **yeni** bulgular listelendi.

---

## 0. Yönetici özeti

Uygulama teknik olarak olgun, ürün olarak fazla geniş. Güçlü bir tasarım sistemi, disiplinli
bir Supabase arka ucu ve olağanüstü zengin bir karar geçmişi var; buna karşılık altı ekran
tek başına kodun %27'sini taşıyor, üç manşet özellik veri yokluğundan görünmüyor ve
**canlı bir cron gizli anahtarı git'e commit edilmiş durumda**.

En kritik 5 madde (bu hafta):

| # | Madde | Alan | Süre |
|---|---|---|---|
| 1 | `tmp/update_daily_brief_vault.sql` içindeki canlı `daily_brief_cron_secret` git'te. Rotasyon + dosya silme + geçmiş temizliği | Güvenlik | 1 saat |
| 2 | `push-live-activity` fonksiyonunda hiç yetki kontrolü yok; diğer 6 cron fonksiyonunda gizli anahtar yoksa kontrol atlanıyor (fail-open) | Güvenlik | 2 saat |
| 3 | `send-partner-invite-push` yanıtı karşı kullanıcının ham FCM token'larını döndürüyor | Güvenlik | 30 dk |
| 4 | Çıkış onayı çalışmıyor: "Çık" tuşu kök navigator'da `pop()` çağırıyor, uygulama kapanmıyor | UX | 15 dk |
| 5 | `flutter test` yalnızca `v*` tag'inde koşuyor; PR/`main` için hiç CI kapısı yok | Kalite | 1 saat |

---

## 1. Güçlü yönler (artılar)

**Ürün**
- **Gerçek kâr muhasebesi.** Komisyon maliyet tabanına katlanıyor (`lib/models/asset.dart:129-235`), nakit temettü getiriye ekleniyor. Mağaza metnindeki iddia kodda karşılığını buluyor.
- **Türkiye piyasasına yerli.** BIST, TEFAS fon NAV'ı, çeyrek/yarım/ata/Cumhuriyet altını ve 22 ayar gram gibi Türklerin altını gerçekten tuttuğu biçimlerde alt kategoriler. Uluslararası rakiplerde yok.
- **TÜFE'ye göre reel getiri.** "Ne kadar kazandım" yerine "alım gücü kaybettim mi" sorusunu soruyor (`lib/services/inflation_service.dart`). Veri yoksa uydurmak yerine `null` döndürüyor.
- **Alım günü kuru saklanıyor** (`purchaseFxRate`) — çoğu takip uygulamasının yanlış yaptığı şey.
- **Gizlilik odaklı sosyal katman.** k-anonimlik sunucuda zorlanıyor, `n_max = floor(k_min/2)` değişmezi migration'da türetilmiş (`0031`).
- **Geniş yüzey erişimi.** Android/iOS ana ekran widget'ı, iOS Live Activity / Dynamic Island, test edilebilir saf deep-link yönlendiricisi.
- **Uyum erken yapılmış.** Hesap silme edge function'ı, JSON veri dışa aktarımı, sürümlü sorumluluk reddi kabulü, TR+EN KVKK/GDPR metinleri.

**Teknik**
- **Riverpod geçişi tam.** Sıfır `StateNotifier`, sıfır `package:provider`. `preferences_provider.dart` içindeki jenerik `_BoolPrefNotifier/_IntPrefNotifier` deseni örnek nitelikte.
- **Katmanlama ağ sınırında tutuyor.** 38 ekran + 30 widget içinde sıfır `http` importu, `Supabase.instance` yalnızca teşhis ekranında.
- **Önbellekler sınırlı ve katmanlı.** `history_service.dart:243-291` gerçek LRU (50 giriş, 15/5 dk TTL); TEFAS RAM/disk/fiyat üç katman.
- **Parite/değişmez testleri.** İki render yolunun aynı sonucu verdiğini iddia eden testler (`chart_interaction_parity_test`, `partner_pnl_consistency_test`) ve Dart ile Deno arasında paylaşılan `ta_golden_vectors.json`. 28.707 satır test / 62.303 satır kaynak.
- **Enum çözümlemesi hiç fırlatmıyor.** Her `fromString/fromDb` güvenli varsayılana düşüyor.
- **Gizli anahtar disiplini istemcide doğru.** `String.fromEnvironment`, fallback literal yok, Firebase config yoksa sessiz no-op, `_ConfigErrorApp`.
- **Android sertleştirmesi tamam.** `allowBackup=false`, `data_extraction_rules.xml`, `AD_ID` kaldırılmış, `FLAG_SECURE`, R8 minify, cleartext yok.
- **Supabase tarafı uygulamadan daha temiz.** Her `SECURITY DEFINER` fonksiyonunda `search_path` set (47 migration'da sıfır eksik), her tabloda RLS, GRANT eksikse `raise exception` atan runtime assertion'lar (`0036`, `0042`, `0043`).
- **Yorumlar karar kaydı niteliğinde.** `tr_format.dart:96-118` sessiz veri bozulması tablosu, `history_service.dart:255` TTL gerekçesi, `android-release.yml:44-51` Flutter pin gerekçesi. Kurumsal hafıza olarak nadir kalite.
- **`TECHNICAL_DEBT.md` gerçek bir defter.** Neden ertelendi, maliyeti ne, kapanınca commit hash'i.

---

## 2. Zayıf yönler (eksiler)

### 2.1 Ürün
1. **Ekip boyutuna göre özellik şişkinliği.** Yayın öncesi bir uygulama için 31 ekran, 30 servis, 53 migration, 11 edge function.
2. **Üç manşet özellik ölü doğuyor.** Reel getiri şeridi `inflation_index` boş (EVDS anahtarı alınmamış); yıllık özet yalnızca 26 Aralık–10 Ocak açılıyor; yüzdelik dilim k=8 eşiğinin altında hiçbir şey çizmiyor (`percentile_strip.dart:36`). Mart ayında kayıt olan kullanıcı üçünü de görmüyor ve neden görmediği açıklanmıyor.
3. **Yarış (leaderboard) hayalet özellik.** 1.893 satır ekran + 674 satır hero kart + 5 migration + günlük snapshot yazımı; sonuç "Yeterli katılımcı olunca sıran açılacak" (`leaderboard_screen.dart:1329`). Üstelik mağaza ekran görüntüsü `08_yaris` bunu öne çıkarıyor.
4. **Fiyat verisi tamamen resmî olmayan kaynaklardan.** Yahoo `v7/finance/quote` (`price_service.dart:417`), `finans.truncgil.com` (`:241`), TEFAS form POST'u, `open.er-api.com`. Lisanslı yedek yok, kullanıcıya bayatlık sözleşmesi yok.
5. **Tek para birimi (TRY).** `toTRY()` tek dönüşüm yolu (`portfolio_provider.dart:74`). Dolar cinsinden düşünen bir pazarda "portföyü USD göster" yok.
6. **i18n altyapısı var, içeriği yok.** `supportedLocales` `en_US` ilan ediyor (`main.dart:290`) ama `.arb` dosyası yok, `locale` `tr_TR`'ye sabit (`:284`). İngilizce mağaza sayfası var, İngilizce arayüz yok.
7. **Çevrimdışı hikâyesi zayıf.** Yalnızca bellek içi 45 sn `_quoteCache`; son bilinen portföy diske yazılmıyor.
8. **Sahte satın alma akışı bir Remote Config anahtarı uzakta.** `paywall_screen.dart:128` yalnızca SharedPreferences boolean'ı çeviriyor; `in_app_purchase`/RevenueCat pubspec'te yok. `paywall_enabled=true` yapılırsa App Store 3.1.1 reddi.
9. **Broker CSV içe aktarımı yok.** 2.713 satırlık manuel ekleme ekranı aktivasyonun en büyük sürtünmesi.
10. **Apple/Google ile giriş yok.** E-posta+şifre sunulduğunda App Store 4.8 fiilen Sign in with Apple istiyor.

### 2.2 Teknik
11. **Tanrı ekranlar.** `portfolio_performance_screen.dart` (4.311) + `performance_screen.dart` (3.879) = 8.190 satır paralel grafik ekranı. `TransactionSegment` sınıfı iki kez, farklı alanlarla tanımlı (`:1182` / `:3926`). Aynı taşma hatası birinde düzeltilip diğerinde yeniden çıktı (`portfolio_performance_screen.dart:2262`).
12. **`add_asset_screen.dart`** 67 metod, 37 `setState`, ~156 alan. Riverpod'un yanında paralel imperatif durum makinesi (240 `setState` / `lib`).
13. **Tekrar eden mantık.** Yüzde değişim formülü 5 kopya, `NumberFormat.currency(locale:'tr_TR')` 20 ad-hoc örnek (**ondalık basamak aynı ₺ tutarı için 0/2/3 arasında değişiyor**), `DateTime(y,m,d)` 38 kopya, kazanç/kayıp rengi 5 yerde satır içi.
14. **Hata görünürlüğü.** 221 `catch` bloğunun Crashlytics'e bildirdiği: sıfır (`recordError` yalnızca 2 dosyada). `auth_service.dart`'ta 26 sessiz catch.
15. **`friendlyError()` tek yerden çağrılıyor.** ~20 site `Text(e.toString())` ile ham PostgREST hatasını kullanıcıya basıyor.
16. **CI kapısı yok.** Test paketi yalnızca `v*` tag push'unda koşuyor (`android-release.yml:17-26`). `pull_request` tetikleyicisi hiçbir workflow'da yok. Deno testleri hiçbir workflow'da koşmuyor.
17. **`analysis_options.yaml` dokunulmamış şablon.** `flutter_lints` 4.x (güncel 6.x), strict mod kapalı.
18. **Şema için üç doğruluk kaynağı.** `supabase_schema.sql`, `supabase_reset.sql`, `supabase/migrations/0007+` (0001–0006 yok). Kök `.sql` dosyaları `0008` ile kapatılan zafiyetli RLS politikalarını hâlâ içeriyor.
19. **Polling agresif.** `profile_screen.dart:233` her 3 sn, `:869` ve `partnership_requests_screen.dart:36` her 5 sn ağ isteği; `leaderboard_screen.dart`'ta 4 ayrı `Timer.periodic`.
20. **`CLAUDE.md`'nin ilk üçte biri başka bir uygulamayı anlatıyor.** sqflite/DatabaseService/Provider paketi (hiçbiri yok), "emülatöre ilk kurulum" aşaması, tek makineye özgü Windows yolları.
21. **24 kök markdown, 8.066 satır**, yedi tanesi "ne kaldı" sorusuna farklı tarihlerde farklı cevap veriyor. `TECHNICAL_SIGNALS_IMPLEMENTATION.md` Portekizce ve ölü bir ekranı anlatıyor.
22. **Tek seferlik migration her açılışta koşuyor** (`fx_rate_migration_service.dart`, `main.dart`'tan).
23. **`Asset.toMap()` ile `toSupabase()` farklı alan kümesi taşıyor.** Ortak kodu payload'u `purchaseFxRate`, `commission`, `dividendAmount`'u sessizce düşürüyor (`asset.dart:359` vs `:402`).
24. **Swift widget ve pbxproj derlenerek doğrulanmadı** (`TECHNICAL_DEBT.md:467`, kendi beyanı).

---

## 3. Teknik güvenlik bulguları

Önceki denetimlerin kapattığı maddeler (invite RLS zinciri, S3 filtre enjeksiyonu, rate limit
redesign, PII maskesi) kodda doğrulandı ve yerinde. Aşağıdakiler **açık**.

### KRİTİK

**C1 — Canlı üretim cron gizli anahtarı git'te.**
`tmp/update_daily_brief_vault.sql:3` → `daily_brief_cron_secret` değeri açık metin, commit `61a74dc`.
`.gitignore` `tmp/`'yi kapsamıyor. `daily-brief` `--no-verify-jwt` ile deploy ediliyor; bu anahtar
uç noktayı koruyan **tek** kimlik bilgisi. Proje ref'i de repoda (`0044_daily_brief.sql:63`).
*Etki:* Repoya bir kez erişmiş herkes, FCM token'ı olan her kullanıcıya istediği sıklıkta push
gönderebilir. *Çözüm:* Vault + `supabase secrets set` ile rotasyon; `git rm`; `tmp/` → `.gitignore`;
`git filter-repo` ile geçmişten temizleme.

### YÜKSEK

**H1 — `push-live-activity` yetkisiz.** `supabase/functions/push-live-activity/index.ts:188-206`
`Authorization` başlığını hiç okumuyor. Cron tarafı Bearer gönderiyor (`0034:70-80`) ama fonksiyon
doğrulamıyor. `{"userId":"<uuid>"}` gövdesi varlık kâhini: "aktif oturum yok" ile başarılı gönderim
ayırt edilebiliyor. *Çözüm:* Kardeş fonksiyonlardaki cron-secret kapısını ekle, `userId` parametresini kaldır.

**H2 — Altı cron fonksiyonunda yetki fail-open.** `analyze-signals:625`, `calendar-nudge:125`,
`check-price-alerts:128`, `daily-brief:202`, `fetch-inflation:213`, `weekly-summary:245` hepsi
`if (cronSecret) { ... }` — env değişkeni yoksa (isim hatası, restore sonrası kayıp, secret
set edilmeden deploy) blok atlanıyor ve fonksiyon **tamamen açık**. Aynı fonksiyonlar
`SUPABASE_URL` eksikse `throw` ediyor; yalnızca güvenlik sınırı sessizce düşüyor.
*Çözüm:* `if (!cronSecret) return 503` + sabit zamanlı karşılaştırma.

**H3 — `send-partner-invite-push` karşı tarafın FCM token'larını döndürüyor.**
`index.ts:262-285` → `results: [{token, ok, rawText}]`. Token'lar `from_user_id`'ye ait, çağıran
`to_user_id`. Herkese açık paylaşılmış bir davet kodu, davet sahibinin kalıcı cihaz kimliklerini
veriyor. *Çözüm:* Yalnızca `{ok, delivered}` döndür.

**H4 — Bootstrap SQL'ler zafiyetli politikaları hâlâ içeriyor.** `supabase_schema.sql:140-160,
181-182, 250-251, 278-290` ve `supabase_reset.sql` — `0008` ile kapatılan `invites_redeem_select`,
`invites_claim_update`, `partnerships_insert`, `search_path`'siz `handle_new_user`. Yeni ortam /
felaket kurtarma bu dosyalarla başlarsa Mayıs'taki kritik zincir geri gelir.
*Çözüm:* `supabase_reset.sql`'i sil; `supabase_schema.sql`'i migrations'a işaret eden bir not yap.

**H5 — Release build sessizce debug anahtarıyla imzalanıyor.** `android/app/build.gradle.kts:62-66`
`key.properties` yoksa `signingConfigs.getByName("debug")`. Yerel `flutter build apk --release`
herkesin bildiği debug anahtarıyla imzalı, dağıtılabilir bir APK üretiyor, uyarı yok.
*Çözüm:* `else throw GradleException("key.properties yok")`.

### ORTA

| # | Bulgu | Yer | Çözüm |
|---|---|---|---|
| M1 ✅ | k=8 ile k-anonimlik Sybil hesaplarla kırılabilir: 7 sahte hesap + `roi_pct` istemciden geliyor → kurbanın ROI'si ikili aramayla, dağılımı doğrudan okunur | `0031:47-49`, `leaderboard_service.dart:248` | k paydasında yalnızca ≥N gün geçmişi olan kullanıcıları say, ya da liste kapalı kalsın |
| M2 ✅ | Supabase oturum token'ları düz `SharedPreferences`'ta (`flutter_secure_storage` yok) | `main.dart:184-187` | Keychain/EncryptedSharedPreferences destekli `LocalStorage` ver |
| M3 | Silme günlüğü hash tuzu varsayılan değerli: `?? "sandik-default-salt-CHANGE-ME"` | `delete-account/index.ts:28` | Varsayılanı kaldır, yoksa `throw` |
| M4 | Kayıtta hesap numaralandırma: "Bu e-posta zaten kayıtlı" (Mayıs H2 uygulanmamış) | `auth_service.dart:207-213` | Her durumda "Kod gönderildi" yolu, OTP çözsün |
| M5 | ~20 sitede `Text(e.toString())` ham PostgREST hatası (tablo/kolon/kısıt adı) | `profile_screen.dart:133,171,181,300,897,908`, `partnership_requests_screen.dart:89,108`, `charts_screen.dart:211`, `performance_screen.dart:1505`… | `showAppError(context, e)` |
| M6 | Crashlytics breadcrumb'ında ham user UUID (`sanitize()` bypass) | `remote_push_service.dart:246, 180, 210, 232` | İlk 8 karakter ya da takma ad |
| M7 ✅ | Davet kodu rate limit'i saldırganın kendi hesabına keyli; hesap açmak ücretsiz ve sınırsız | `redeem-invite-code/index.ts:79-84` | IP bazlı ikinci sayaç + global saatlik tavan |
| M8 ✅ | Davet onaylanmadan davet sahibinin UUID + adı dönüyor | `redeem-invite-code/index.ts:240-245` | `partner_user_id`'yi yanıttan çıkar (istemci kullanmıyor) |
| M9 ✅ | Admin yetkisi migration'a gömülü, değiştirilebilir e-posta ile | `0021:19-27` | `auth.uid() = '<uuid>'` |
| M10 | Edge function'lar `error.message`/`detail` echo ediyor | `send-partner-invite-push:287`, `delete-account:139` | Sabit hata kodu, `console.error` |
| M11 | Geliştirici teşhis ekranı release'te tüm kullanıcılara açık | `settings_screen.dart:574-589` | `is_admin()` sonucuna göre gizle |
| M12 | Login / OTP doğrulamada uygulama düzeyi throttle yok; şifre sıfırlama OTP'sinde 6 hane kontrolü yok | `auth_service.dart:318, 228, 424-434` | `rate_limit_attempts` tablosunu `login`/`otp_verify` kapsamıyla kullan |

### DÜŞÜK
L1 sabit zamanlı olmayan Bearer karşılaştırması · L2 ✅ 10 dk idle logout bellekte, process kill sonrası uygulanmıyor (`main.dart:985-997`) · L3 sertifika pinning yok (bilinen, ertelenmiş) · L4 cron fonksiyonlarında `Access-Control-Allow-Origin: *` · L5 `_maskSensitive` `List<Map>`'e inmiyor (`db_logger.dart:174-185`) · L6 `db_logs` 30 gün retention cron'u yorum satırında · L7 `friendly_error.dart:77` "en az 6 karakter" diyor, kural 8+harf+rakam · L8 dışa aktarım JSON'una ham hata gömülüyor (`data_export_service.dart:118`) · L9 `FORCE RLS` yalnızca 2 tabloda · L12 şifre üst sınırı yok (bcrypt 72 bayt, Türkçe karakter 2 bayt) · L13 davet hedefi `reject` ile sahibin 24 saatlik kodunu yakabiliyor (`accept-invite:99-105`) · L14 logout `push_device_id` ve `rl_attempts_*` anahtarlarını bırakıyor.

---

## 4. Kaldırılması gerekenler

### Şimdi sil (sıfır risk, ~2.100 satır + repo çöpü)
| Ne | Kanıt |
|---|---|
| `lib/screens/asset_detail_screen.dart` (597) | 0 import, 0 construct; 20 inline `TextStyle`, 4. "varlık detayı" varyantı |
| `lib/screens/portfolio_detail_screen.dart` (571) | 0 import; kendi `LineChart`, kendi `_SectionTitle`, kendi `NumberFormat` |
| `lib/widgets/premium_gate.dart` (126) | `PremiumGate` hiç construct edilmiyor |
| `lib/widgets/bar_interval_selector.dart` (108) | HEAD commit'te eklendi, hiçbir ekrana bağlanmadı; ya bağla ya sil |
| `lib/utils/chart_downsample.dart` + `series_downsample.dart` | İkisi de yalnızca kendi testlerinden referanslı; birleştir ya da sil (`seyreltSpots` çağıransız — `TECHNICAL_DEBT.md:502`) |
| `PortfoyTakip.xcodeproj/` | Silinmiş SwiftUI prototipinin yetim proje dosyası; referans verdiği `.swift` dosyaları yok |
| `tmp/` | Bkz. C1. Sil + `.gitignore` |
| `supabase_reset.sql` | `DROP TABLE CASCADE` + `DELETE FROM auth.users` + zafiyetli politikalar |
| `supabase_schema.sql` | Migrations'a işaret eden 5 satırlık nota indir |
| `assets/images/sandik_original_circle.png`, `splash_icon.png` | 0 referans |
| `store_listing/screenshots/orig/`, `raw/BURAYA_KOYUN.txt` | `raw_v2/out_v2` ile aşıldı |
| `tools/` | `tool/` ile birleştir (iki dizin yalnızca `s` ile ayrılıyor; PowerShell betiği `C:\Screenshots` mutlak yol) |

### Gizle, silme
- **Push Teşhisi tile'ı** — `settings_screen.dart:575-589` koşulsuz spread. Ekranın zaten çektiği admin sonucuna bağla; "GELİŞTİRİCİ" → "Tanılama".
- **`db_logger`** — release'te yalnızca hata; `List<Map>` maskesi eksik (L5).
- **`fx_rate_migration_service`** — her açılışta değil, bir kez koş (pref bayrağı).

### Ertele / karar ver
- **Yarış (leaderboard, ≈2.750 satır + 5 migration + günlük snapshot yazımı).** DAU k=8'i geçene kadar nav girişlerini kaldır, snapshot yazımını durdur; migration'lar kalsın. Mağaza görseli `08_yaris` değiştirilmeli. Ayrıca M1 (Sybil) çözülmeden açılmamalı.
- **Paywall (≈1.400 satır).** Ya RevenueCat entegre et ya `paywall_screen.dart` + sahte `_completePurchase`'ı sök. Sahte satın alma butonunun bir toggle uzakta olması repodaki en riskli ürün kararı.
- **Vadeli mevduat (≈800 satır, `deposits_enabled=false`).** Kod tam, cilasız. Bitir ve aç ya da sil; süresiz uyku en kötü seçenek.
- **Yıllık özet (707 satır).** Yılda 16 gün. Ucuz, kalsın; yayın öncesi efor harcanmasın.

### Doküman konsolidasyonu (24 → 7)
**Kalsın:** `README.md` (dizin hâline getir), `CLAUDE.md` (yeniden yaz), `TECHNICAL_DEBT.md`,
`YAPMAN_GEREKENLER.md`, `MONETIZATION_ROADMAP.md`, `PLAY_STORE_YAYIN_REHBERI.md`,
`SECURITY_AUDIT_2026_08.md`, bu dosya.
**`docs/archive/`'a taşı** ("X tarafından DATE'te aşıldı" başlığıyla): `FAZ_A/B/C_COMPLETE`,
`PRODUCTION_STATUS`, `PRODUCTION_ROADMAP`, `PLAN`, `DESIGN_REVIEW`, `UI_DERIN_INCELEME_RAPORU`,
`LIGHT_MODE_TASARIM_RAPORU`, `ANIMASYON_INCELEME_RAPORU`, `SKILL_GELISTIRME_RAPORU`,
`SECURITY_AND_UX_AUDIT`, `OPTIONAL_PRICE_FEATURE`, `CATEGORY_SYSTEM_UPDATE` (var olmayan
dosyaları anlatıyor), `TECHNICAL_SIGNALS_IMPLEMENTATION` (Portekizce, ölü ekran),
`ANDROID_DEPLOYMENT_CONTEXT`, `SUPABASE_DEPLOY_ADIMLARI.txt`, `RETENTION_STRATEJISI`
(monetization'a referans olarak bağla).

---

## 5. Geliştirilecek makul şeyler (ürün)

Öncelik sırasıyla; "kısmi destek" sütunu kodda ne kadarının hazır olduğunu gösterir.

| # | Özellik | Kısmi destek | Boşluk | Efor |
|---|---|---|---|---|
| 1 | **Apple / Google ile giriş** | Yok | App Store 4.8 + kayıt hunisinde en büyük kazanım | M |
| 2 | **Portföyü USD / EUR / gram altın bazında göster** | Alım günü kuru zaten saklı; `toTRY()` tek yol | Baz para birimi seçici; dönüşüm tesisatı büyük ölçüde var. **Bu pazar için en değerli boşluk** | M |
| 3 | **Portföy vs XU100 / USD / gram altın / TÜFE overlay** | `PercentComparisonChart` var, TÜFE karşılaştırması veri varsa var | Birinci sınıf "sandığın vs piyasa" çizgisi — mevcut widget ile ucuz | S |
| 4 | **Broker CSV / Excel içe aktarım** | JSON dışa aktarım var, `csv` bağımlılığı yok | Manuel giriş en büyük aktivasyon sürtünmesi | M |
| 5 | **Gerçekleşen vs gerçekleşmemiş K/Z** | Satış fiyatı saklı (`asset.dart:126`), soft-delete lot var (`0027`) | Ayrı "gerçekleşen kazanç" rakamı hiç gösterilmiyor | S |
| 6 | **Biyometrik / PIN kilidi** | Yok (`local_auth` pubspec'te yok) | Finans uygulamasında algılanan güven; düşük efor | S |
| 7 | **Kalıcı çevrimdışı görünüm** | 45 sn bellek önbelleği | Son bilinen portföyü diske yaz; uçakta açılabilsin | S |
| 8 | **Bildirim "sessiz saatler" + global sıklık tavanı** | Tür bazlı toggle'lar, `signal_frequency` | `RETENTION_STRATEJISI.md:753` bildirim bütçesini kilit kısıt sayıyor; tek ayar yok | S |
| 9 | **Stopaj / vergi modeli** | Yok | Temettü ve fon itfasında stopaj — yerel bir eksik | M |
| 10 | **FIFO / ağırlıklı ortalama seçimi** | Yalnızca ağırlıklı ortalama | Türk vergi beyanı için FIFO | M |
| 11 | **Bedelsiz / bölünme (split) işlemi** | Nakit temettü var (`dividend_dialog.dart`) | Bedelsiz hisse ve split yok | S |
| 12 | **Dışa aktarımı tamamla + içe aktarım** | 7 tablo dışa aktarılıyor | `watchlist`, `price_alerts`, `signal_preferences`, `milestones` eksik → GDPR 20 açısından eksik yanıt; geri yükleme yok | S |
| 13 | **Ortaklık isteklerine uygulama içi giriş** | Yalnızca push tıklamasından ulaşılıyor (`notification_service.dart:477`) | Push kaçarsa bekleyen davet görünmez | S |
| 14 | **Boş özelliklere "neden boş" açıklaması** | Şeritler sessizce kayboluyor | "Reel getiri: TÜFE verisi bekleniyor", "Yarış: N kişi daha katılınca" | S |
| 15 | **İleriye dönük hedef (goal)** | `milestone_service` geriye dönük kutlama | Tasarruf hedefi + ilerleme | M |
| 16 | **İngilizce arayüz** | `flutter_localizations` bağlı, `en_US` ilan edilmiş | `.arb` yok; ~1.500 literal. Ya yap ya `en_US`'i `supportedLocales`'tan çıkar | L |

---

## 6. UX tutarlılığı

### 6.1 Ölçülen tutarsızlıklar
| Konu | Durum | Kanıt |
|---|---|---|
| **Buton API'si** | 5 rakip: `FilledButton` 22 dosya, `CupertinoButton` 20 dosya (94 ref), `TextButton` 16, `OutlinedButton` 5, `ElevatedButton` 1 (`add_deposit_screen`), + `SandikAsyncButton/SandikTappable` 17 | grep |
| **Diyalog dili** | `AlertDialog` 13 dosya vs `CupertinoAlertDialog` 5; `showModalBottomSheet` 13 vs `showCupertinoModalPopup` 5. Aynı "varlığı sil" diyaloğu 3 kez yazılmış | `charts_screen.dart:159`, `performance_screen.dart:1453`, `asset_detail_screen.dart:550` |
| **Snackbar** | 60 site, merkezi yardımcı yok (Ağustos'ta 30'du, ertelendi, ikiye katlandı). Tab ekranlarında 60pt blur nav bar'ın arkasına giriyor | `main_navigation_screen.dart:246` |
| **Yükleme göstergesi** | `CustomLoadingIndicator` 18 dosya, ham `CircularProgressIndicator` 5 ekranda hâlâ | `price_alerts`, `comparison`×2, `onboarding`, `push_diagnostics`, `performance`×2 |
| **Pull-to-refresh** | Yalnızca 3 dosyada. **Performans sekmesinde yok** | `home`, `charts`, `partnership_requests` |
| **Boş durum** | 9 farklı el yapımı varyant; yalnızca 2'sinde CTA | `charts:597`, `watchlist:561`, `home:570`, `all_transactions:358`, `price_alerts:202`, `profile:734`, `bulk_add:262`, `portfolio_performance:1347` |
| **Para biçimi** | 20 ad-hoc `NumberFormat.currency`, aynı ₺ için 0/2/3 ondalık; 36 `toStringAsFixed` UI'da | `charts_screen.dart:1158` (0), `:1594` (2), `:1438` (3) |
| **Tarih biçimi** | 4 desen aynı kavram için | `'d MMM yyyy'`, `'d MMM'`, `'d MMMM EEEE'`, `'d MMM HH:mm'` |
| **Hitap** | `sen`/`siz` karışık; iki komşu onay diyaloğu zıt kipte | `main_navigation_screen.dart:178` "istiyor musunuz" vs `bulk_add_asset_screen.dart:194` "Emin misin?" |
| **Başlık kasası** | BÜYÜK HARF + letterSpacing (`home`, `settings`) vs Title Case (`profile`) vs cümle (`push_diagnostics`) | — |
| **Emoji** | 4 kullanıcı metninde, kuralsız; TalkBack/VoiceOver harfiyen okuyor | `leaderboard_screen.dart:1359`, `paywall_screen.dart:192` |
| **Navigasyon yardımcısı** | `adaptiveRoute` 30×, ham `MaterialPageRoute` 1 (iOS'ta yanlış geçiş), `pushGuarded` 7 site vs 29 ham `Navigator.push` | `settings_screen.dart:584` |
| **Form** | 6 ekran `Form+validator`; `add_asset_screen` aynı akışta `TextFormField` (`:1148`) ve bare `TextField` (`:2109`) karışık; ortak kodu alanı `number` klavye, alfanümerik ipucu | `profile_screen.dart:596` |
| **Yıkıcı onay** | Varlık/hesap/ortak/sepet için var; takip listesi satır silmede yok (geri alınamaz snackbar) | `watchlist_screen.dart:536` |

### 6.2 Tasarım sistemi benimsenmesi
Token sistemi güçlü, benimseme kısmi. `design_token_leak_test.dart` mevcut açığı **dondurmak**
için kalibre edilmiş (≤49 `Color(0x)`, ≤28 ham `Duration`); `Colors.*`, ham `fontSize`,
`SizedBox`/`EdgeInsets` sayılarını hiç gözetmiyor.

| Sızıntı | Sayı | En kötü |
|---|---|---|
| `Colors.*` tema dışı | 90 | `performance_screen` 16, `portfolio_performance_screen` 15, `main.dart` 11 |
| Inline `TextStyle(` | 154 | `settings_screen` 27, `comparison_screen` 21 |
| Ham `fontSize:` | 191, **17 farklı boyut** | `main.dart` 25, `comparison_screen` 19 |
| Ham sayısal `SizedBox` | 542 vs 218 `SandikSpace.*` (%29 kapsama) | — |
| Ham `EdgeInsets` | 385 | — |
| `BorderRadius.circular(n)` | 29 vs 325 `SandikRadius.*` | tek sağlıklı eksen |

**En çarpıcı bulgu:** `SandikCard` (`sandik.dart:1228`) ve `SandikSectionHeader` (`:1287`)
yazılmış, test edilmiş (`sandik_card_test.dart`) ve **üretimde sıfır kullanım**. Üç ekran kendi
özel `_SectionTitle` klonunu tanımlıyor (`settings:625`, `profile:1038`, `portfolio_detail:562`);
`context.surfaceCard()` 18 kez, ad-hoc `BoxDecoration(` 307 kez.

### 6.3 Navigasyon ve bilgi mimarisi
- **İsim tuzağı** (`main_navigation_screen.dart:24` kaynakta belgeli): "Portföy" sekmesi `ChartsScreen`, "Performans" sekmesi `PortfolioPerformanceScreen`, tekil varlık ekranı `PerformanceScreen`. Üç ekran, hiçbirinin adı sekme etiketiyle örtüşmüyor.
- **Çıkış no-op:** `PopScope(canPop:false)` → onay → `Navigator.of(context).pop()` (`:208`) kök navigator'da tek route ile hiçbir şey yapmıyor. `SystemNavigator.pop()` hiçbir yerde yok. Kullanıcı "Çık"a basıyor, uygulama açık kalıyor.
- **Geri tuşu önceki sekmeye dönmüyor** (Mayıs UI3, hâlâ açık).
- **Tek girişli dört büyük özellik:** Yarış (yalnızca Performans'tan), Karşılaştırma (yalnızca Portföy'den), Yıllık özet (yalnızca profil banner'ı), Ortaklık istekleri (yalnızca push).
- **Derin bağlantı yok:** `AndroidManifest.xml`'de VIEW/scheme intent-filter yok, `onGenerateRoute` yok. Push → belirli varlık mümkün değil.
- **Predictive back (Android 14+)** `PopScope(canPop:false)` ile küresel olarak engelli.

### 6.4 İlk kullanım
Soğuk başlangıç: Yükleme → Giriş/Kayıt → Sorumluluk reddi ekranı → 10 sahne / 27 adım tur → Ana ekran.
- Kayıtta 2 onay kutusu, **her biri tam yasal metni açıp sonuna kadar kaydırmayı zorunlu kılıyor** (`register_screen.dart:361-421`). 4 düz kutudan daha yavaş.
- Sorumluluk reddi kayıtta zaten onaylanmışken (`:365`) ikinci bir ekran olarak tekrar geliyor (`main.dart:1256`).
- 27 adımlık turda görünür "atla ve varlık ekle" kısayolu yok; Ayarlar'dan yeniden giriş yok.
- Tur biter bitmez: ₺0 özet + 3 boş şerit + boş dağılım; "İlk Varlığını Ekle" CTA'sı listenin **en altında** (`home_screen.dart:570`).

### 6.5 Ana ekran hiyerarşisi
375×812'de katlama üstü: 5 kontrollü app bar (kaynak yorumu `:346` kapasitenin dolduğunu söylüyor) → özet → reel getiri şeridi → yüzdelik şeridi → "Bu hafta" kartı → 2 kişi kartı → ortak seçici → filtre çipleri → **VARLIK DAĞILIMI**. Üç ardışık, bağımsız gizlenen, kapatılamayan şerit; varlık listesi her açılışta katlama altında.

### 6.6 Erişilebilirlik
**Güçlü:** 25 dosyada ~75 `Semantics`, 44pt testi, `boldText`, yüksek kontrast paleti, reduce-motion %100, WCAG doğrulanmış paletler, pasif sekmelerde `ExcludeSemantics`.
**Boşluk:** 4 grafik widget'ı ekran okuyucuya kapalı (yalnızca `watchlist_chart`'ta 1 `Semantics`); `settings`, `performance`, `add_asset`, `comparison`, `leaderboard` ekranlarında 0–1 `Semantics`; 20 `CupertinoButton(minimumSize: Size.zero)` 44pt testini atlıyor (`register_screen.dart:317` ≈48×20pt); kompakt yüzeylerde kazanç/kayıp yalnızca renkle (`transaction_row`, `portfolio_summary_widget`); nav bar `AnimatedScale` (`:286`) `SandikMotion` yerine ham 200 ms.

---

## 7. Modern ve işlevsel UI iyileştirmeleri

**Mevcut (iyi):** `useMaterial3: true` + 12 bileşen teması, `cupertinoOverrideTheme`, `adaptiveRoute`, `Switch.adaptive`, blur nav bar, 4 kademeli `SandikHaptic` (28 site), `RepaintBoundary` sparkline, edge-to-edge inset yönetimi, `highContrast`/`boldText`.

**Yok — somut fırsatlar:**

| Desen | Durum | Uygunluk | Efor |
|---|---|---|---|
| **Skeleton (iskelet) yükleyiciler** | Sıfır shimmer/skeleton; 23 spinner sitesi; tek emsal `_ChartPlaceholder` | **Yüksek** — her sekme girişte ağdan fiyat çekiyor; finans panosunda spinner "bozuk" okunuyor | M |
| **Merkezi snackbar + Undo** | 60 snackbar, sıfır `SnackBarAction` undo | **Yüksek** — silme akışlarında geri alma; `friendlyError` yönlendirmesi | S |
| **`Hero` geçişi** varlık satırı → varlık grafiği | Sıfır `Hero(` | Orta — en sık tekrarlanan navigasyon | S |
| **Tek `SandikAppBar` / büyük başlık** | 1 `SliverAppBar`, 19 sabit `AppBar`, 12 özel başlık = 3 başlık dili | Orta-yüksek — §6.2'deki başlık tutarsızlığını da çözer | M |
| **`SegmentedButton` / `CupertinoSlidingSegmentedControl`** | Sıfır; her segment el yapımı `AnimatedContainer` pill (`ModernTabSelector`, `_PeriodToggle`, filtre çipleri) | Orta — ücretsiz a11y + klavye + tema | M |
| **Grafik etkileşim paritesi** | `ZoomableChart` pinch/pan var; `PercentComparisonChart` ve `WatchlistChart` `ZoomDataController` dışında — pinch bir grafikte çalışıyor, ötekinde sessizce çalışmıyor | Orta | M |
| **`GrafikTipiSecici` (çizgi/mum)** yalnızca Performans sekmesinde (`:1173`); aynı grafik varlık ekranında yok | Tutarsız | S |
| **Insight şeritlerini tek yatay kaydırmalı "içgörü" kartına topla** (nokta göstergeli, uzun basınca kapat) | 3 ayrı şerit | Orta — varlık listesi katlama üstüne çıkar | M |
| **Predictive back + geri tuşu sekme geçmişi** | Küresel engelli | Orta — targetSdk yükseldikçe zorunluya yakın | S |
| **Derin bağlantı / App Links** | Manifest filtre yok, named route yok | Yüksek (retention: push → varlık) | M |
| **Yapışkan bölüm başlıkları** (`SliverPersistentHeader`) | Yok; hepsi `SliverToBoxAdapter` | Düşük-orta | S |
| **Dinamik renk (Material You)** | Yok | **Bilerek atlanmalı** — amber/altın marka kimliği; kararı belgele | — |

---

## 8. Yol haritası

Eforlar tek geliştirici için kaba tahmindir. Her faz kendi kabul kriteriyle biter; bir sonrakine
geçmeden CI yeşil olmalı.

### FAZ 0 — Bu hafta: kanamayı durdur (≈2 gün)
| # | İş | Alan | Kabul |
|---|---|---|---|
| 0.1 | `daily_brief_cron_secret` rotasyonu; `tmp/` sil + `.gitignore`; `git filter-repo` ile geçmiş temizliği; tüm klonlara bildirim | Güvenlik C1 | Yeni secret ile cron çalışıyor, eski secret 401 alıyor |
| 0.2 | `push-live-activity`'ye cron-secret kapısı; `userId` parametresi kaldır | H1 | Bearer'sız istek 401 |
| 0.3 | 6 cron fonksiyonunda `if (!cronSecret) return 503`; secret'ların set olduğunu `supabase secrets list` ile doğrula | H2 | Her fonksiyon secret'sız ortamda 503 |
| 0.4 | `send-partner-invite-push` yanıtından `token`/`rawText` çıkar | H3 | Yanıt `{ok, delivered}` |
| 0.5 | `build.gradle.kts` → `key.properties` yoksa `GradleException` | H5 | Yerel release build hata veriyor |
| 0.6 | `supabase_reset.sql` sil; `supabase_schema.sql` → nota indir | H4 | Repo'da zafiyetli politika metni kalmadı |
| 0.7 | `DELETION_HASH_SALT` varsayılanı kaldır; `error.message` echo'ları sabit koda çevir | M3, M10 | — |
| 0.8 | Çıkış onayı → `SystemNavigator.pop()` | UX | "Çık" uygulamayı kapatıyor |
| 0.9 | `pull_request` + `push: main` tetikleyicili `ci.yml`: `flutter analyze lib/ test/` + `flutter test` + `deno test supabase/tests/` | Kalite | PR'da kırmızı/yeşil görünüyor |
| 0.10 | Push Teşhisi tile'ını admin sonucuna bağla; `MaterialPageRoute` → `adaptiveRoute` | M11 | Admin olmayan hesapta "GELİŞTİRİCİ" görünmüyor |

### FAZ 1 — 2 hafta: temizlik ve tutarlılık altyapısı (≈8 gün)
| # | İş | Kabul |
|---|---|---|
| 1.1 | Ölü kodu sil: 2 yetim ekran, `premium_gate`, `bar_interval_selector` (ya bağla), downsample ikizi, `PortfoyTakip.xcodeproj`, yetim asset'ler, `tools/`→`tool/` | `flutter analyze` temiz, test sayısı düşmedi |
| 1.2 | Doküman konsolidasyonu: 17 dosya → `docs/archive/`; `README.md` dizin; `CLAUDE.md` yeniden yaz (sqflite/Provider/emülatör bölümleri sil, Windows yollarını "yerel makine notu" bölümüne al) | Yeni gelen 1 dosyadan başlıyor |
| 1.3 | `sandikSnack(context, msg, {kind, undo})` yardımcısı; 60 site migrasyonu; `friendlyError` zorunlu; nav bar inset | Ham `$e` kullanıcıya ulaşan 0 site (M5) |
| 1.4 | Para/tarih tek yol: 20 `NumberFormat.currency` + 36 `toStringAsFixed` → `fmtTRY/fmtPct/fmtNum`; `dayKey()` ve `gainLossColor()` yardımcıları; leak testi | `NumberFormat.currency` `tr_format.dart` dışında 0 |
| 1.5 | `PrefKeys` merkezi dosyası; çift tanımlı `pref_signal_notifications`/`pref_partner_notifications` birleştir | Tek sabit |
| 1.6 | `Asset.toMap()` ↔ `toSupabase()` alan paritesi + round-trip property testi | Ortak kodu komisyon/temettü/kur taşıyor |
| 1.7 | Servis katmanı catch'lerine `reportSilently(e, st, reason)` → Crashlytics; `auth_service` 26 catch öncelikli; Crashlytics breadcrumb UUID maskesi (M6) | Crashlytics non-fatal akışı görünüyor |
| 1.8 | Kayıt hata mesajı jenerik (M4); OTP sıfırlama 6 hane kontrolü; login/OTP için `rate_limit_attempts` kapsamı (M12) | — |
| 1.9 | `flutter_lints` 4→6, `strict-casts`, `unawaited_futures`; `flutter_launcher_icons` → dev_dependencies; `google_fonts` → `fontFamily: 'DM Sans'` | analyze temiz |
| 1.10 | Ratchet testleri: `Colors.*` ≤90, ham `fontSize` ≤191 → yalnızca azalabilir | CI'da |
| 1.11 | Polling: profil 3 sn / 5 sn poll'ları provider + lifecycle-pause + backoff'a; leaderboard 5 timer → 1 | Ekran açıkken arka planda istek yok |
| 1.12 | `fx_rate_migration_service` tek sefer bayrağı | — |

### FAZ 2 — 1 ay: UX tutarlılığı ve modern UI (≈15 gün)
| # | İş | Etki |
|---|---|---|
| 2.1 | **Skeleton yükleyiciler** 3 veri sekmesinde (özet kartı, varlık satırı, grafik alanı) | Yüksek |
| 2.2 | **Pull-to-refresh** 15 veri ekranının hepsinde; `invalidateQuoteCache()` bağlı | Yüksek |
| 2.3 | **Diyalog dili tekleştir:** `showSandikConfirm()` adaptif; 3 kopya "varlığı sil" → 1 | Orta |
| 2.4 | **`SandikCard` + `SandikSectionHeader` benimse:** 3 `_SectionTitle` klonu + ilk 30 `BoxDecoration`; leak testi | Orta |
| 2.5 | **Tek `SandikAppBar`** (3 başlık dili → 1); büyük başlık Ana/Portföy/Performans'ta | Orta-yüksek |
| 2.6 | **Hitap ve kopya geçişi:** `sen`, başlık kasası, emoji kuralı, `en_US`'i `supportedLocales`'tan çıkar (ya da Faz 3'te .arb) | Orta |
| 2.7 | **İlk kullanım kısalt:** Sorumluluk reddi ekranını kayıt onayına katla; "oku-sonuna-kadar" kapısını kaldır, hata metnini butonun yanına; tura "Atla ve varlık ekle"; Ayarlar'dan turu yeniden aç; boş ana ekranda CTA en üstte | Yüksek |
| 2.8 | **Ana ekran katlama üstü:** 3 şerit → 1 yatay kaydırmalı içgörü kartı; boş özelliklere "neden boş" satırı | Orta |
| 2.9 | **Sekme adları:** `ChartsScreen`→`PortfolioScreen`, `PerformanceScreen`→`AssetDetailScreen`; geri tuşu sekme geçmişi; predictive back | Orta |
| 2.10 | **Undo:** takip listesi/varlık silmede `SnackBarAction` | Orta |
| 2.11 | **Grafik paritesi:** `PercentComparisonChart` + `WatchlistChart` → `ZoomDataController`; `GrafikTipiSecici` varlık grafiğinde; 4 grafik widget'ına `Semantics` özet | Orta |
| 2.12 | **`SegmentedButton`/Cupertino segment** ile `ModernTabSelector`/`_PeriodToggle` değiştir | Orta |
| 2.13 | **A11y:** `Size.zero` butonlara padding, `settings`/`add_asset`/`performance` Semantics, kompakt yüzeylerde ok glifi | Orta |
| 2.14 | **Hero** varlık satırı → grafik | Düşük-orta |

### FAZ 3 — Çeyrek: ürün ve mimari (≈30 gün)
| # | İş | Not |
|---|---|---|
| 3.1 ✅ | **Apple / Google ile giriş** | Store gerekliliği + huni |
| 3.2 | **Baz para birimi seçici** (TRY/USD/EUR/gram altın) | Tesisat var |
| 3.3 | **Benchmark overlay** (XU100/USD/altın/TÜFE) | `PercentComparisonChart` ile |
| 3.4 | **Gerçekleşen K/Z** + bedelsiz/split işlemi | Veri var |
| 3.5 | **Broker CSV içe aktarım** (en az 2 aracı kurum formatı) | Aktivasyon |
| 3.6 | **Biyometrik kilit** + Keychain/EncryptedSharedPreferences oturum (M2) | Güven |
| 3.7 | **Kalıcı çevrimdışı önbellek** (son portföy + fiyatlar diske) | — |
| 3.8 | **Derin bağlantılar:** manifest intent-filter, `onGenerateRoute`, push → varlık | Retention |
| 3.9 | **Performans ekranlarını birleştir:** önce ikiz sınıflar (`TransactionSegment`, `_FullscreenChip`), sonra paylaşımlı grafik sunum katmanı; parite testleri güvenlik ağı | En büyük borç |
| 3.10 | **`add_asset_screen` durum makinesini Riverpod `Notifier`'a taşı** (37 setState) | — |
| 3.11 | **Sessiz saatler + bildirim tavanı** ayarı | Retention kısıtı |
| 3.12 | **Yarış kararı:** M1 Sybil çözümü (k paydasında ≥N gün geçmişi) VE DAU ≥ 2×k_min olmadan nav girişi kapalı | — |
| 3.13 | **Paywall kararı:** RevenueCat entegre et ya da sahte akışı sök | — |
| 3.14 ✅ silindi | **Vadeli mevduat:** bitir ve aç ya da sil | — |
| 3.15 | **Dışa aktarımı tamamla + içe aktarım** (GDPR 20) | — |
| 3.16 | `integration_test/` duman akışı: giriş → varlık ekle → portföyü gör | E2E sıfırdan 1'e |
| 3.17 | Testsiz servisler: `tefas_service`, `remote_push_service`, `data_export_service`, `deposit_service`, `price_alert_service` | — |
| 3.18 | Swift widget/pbxproj derleme doğrulaması CI'da (`ios-testflight.yml`) | `TECHNICAL_DEBT.md:467` |
| 3.19 | Sertifika pinning (L3); `FORCE RLS` tüm tablolarda (L9); `db_logs` retention cron (L6) | — |
| 3.20 | İngilizce arayüz (.arb) — yalnızca EN pazarı hedefleniyorsa | L |

---

## 9. Ölçüm ve kabul kriterleri

| Metrik | Bugün | Faz 1 sonu | Faz 2 sonu |
|---|---|---|---|
| CI'da test koşan tetikleyici | tag only | PR + main | PR + main + deno |
| Açık Kritik/Yüksek güvenlik bulgusu | 1 / 5 | 0 / 0 | 0 / 0 |
| `Text(e.toString())` siteleri | ~20 | 0 | 0 |
| `NumberFormat.currency` `tr_format` dışı | 20 | 0 | 0 |
| Ham `Colors.*` tema dışı | 90 | ≤90 (ratchet) | ≤40 |
| Ham `fontSize:` | 191 / 17 boyut | ≤191 | ≤80 / 7 boyut |
| Snackbar merkezi yardımcı kapsama | 0/60 | 60/60 | 60/60 |
| Pull-to-refresh olan veri ekranı | 3/15 | 3/15 | 15/15 |
| Ham `CircularProgressIndicator` | 9 | 9 | 0 |
| Kök markdown dosyası | 24 | 7 | 7 |
| Sıfır referanslı Dart dosyası | 5 | 0 | 0 |
| `recordError` çağıran dosya | 2 | ≥10 | ≥10 |
| >1500 satır UI dosyası | 6 | 6 | 6 → Faz 3'te 4 |

---

## 10. Bilerek yapılmayacaklar
- **Dinamik renk (Material You):** amber/altın marka kimliğiyle çelişir.
- **542 ham `SizedBox` toplu migrasyonu:** `spacing_scale_test.dart:16-19` gerekçesi geçerli; ratchet yeter.
- **Named route'lar tek başına:** yalnızca derin bağlantı (3.8) ile birlikte anlamlı.
- **Riverpod 3 yükseltmesi:** getirisi eforunu karşılamıyor; 2.x güncel ve tutarlı.
- **fl_chart yükseltmesi:** güvenlik advisory'si yok; 0.68 API'si 5 dosyada kırılır, Faz 3.9 sonrası tek noktadan yapılır.

---

## 11. Kaynak raporlar
Bu doküman dört ayrı incelemenin birleşimidir; her bulgunun `dosya:satır` kanıtı yukarıda
verilmiştir. Ayrıntı için: `SECURITY_AUDIT_2026_08.md` (önceki tur), `TECHNICAL_DEBT.md`
(açık borç defteri), `YAPMAN_GEREKENLER.md` (operasyonel bekleyenler: EVDS anahtarı, weekly-summary
vault secret, `push-live-activity` deploy durumu, `0049` migration).
