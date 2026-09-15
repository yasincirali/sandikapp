# Yol Haritası İlerleme Defteri

Kaynak plan: `DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §8.
Bu dosya her adımda güncellenir; **son kalınan yer** en üstte.

> ✅ Flutter 3.47.2 bu oturumda `/opt/flutter-sdk` altına kuruldu (2026-09-13,
> Faz 1 sonunda). O andan itibaren her commit öncesi `flutter analyze lib/ test/`
> ve tam `flutter test` koşuldu. Faz 0–1 değişikliklerinin tümü doğrulandı:
> analyzer 0 sorun, 1.665+ test geçiyor. `deno` hâlâ yok — edge function
> değişiklikleri yalnızca okunarak incelendi; `ci.yml` deno job'ı ilk PR'da
> gerçek sonucu verecek.

## Son kalınan yer (2026-09-15)

**Kullanıcı bildirimi (2026-09-15):** "menülere eklenen feature'lar çalışmıyor; dil
seçeneği uygulamayı tümüyle İngilizce yapmıyor, yatırımcı seviyesi değiştirildiğinde
fark göremedim." İkisi de gerçek kusurdu, ikisi de kapandı:

**Yatırımcı seviyesi — tablo tek ve çoğu kullanıcıda BOŞ bir yüzeye bağlıydı.**
`seviyeGorunurlugu` yalnızca Performans › Özet kartlarını süzüyordu; üçü de 1Y dönemine
(sağlık/XIRR) ya da k-anonimlik eşiğine (yüzdelik) bağlı. Bir yıllık geçmişi ya da sekiz
kişilik havuzu olmayan kullanıcıda seviye değiştirmek ekranda hiçbir şeyi değiştirmiyordu.
Tablo artık ilk açılışta GÖRÜLEN yüzeyleri de kapsıyor (`teknikSinyaller` bayrağı): ana
ekran yüzdelik şeridi, ana ekran sinyal zili, tekil varlıkta sinyal kartı + gösterge
paneli. Kural aynı: Başlangıç yalnızca gizler, İleri yalnızca ekler, Orta varsayılan ve
bugünkü görünüm. `yatirimci_seviyesi_test` hem karar tablosunu hem ekranlara bağlantıyı
kilitliyor.

**3.20 İngilizce — kapsam ~130 → 780+ anahtar.** `l10n_coverage_test` 87 ekran/widget
dosyasını yalnızca-azalır tavanlarla bağlıyor; **47'si sıfır Türkçe literal taşıyor**,
kalan 212 literal 41 dosyaya yayılmış küçük etiketler. Çevrilenler: giriş/kayıt/şifre/OTP,
gezinme, kilit, yasal uyarı onayı, ana ekran (sinyal sayfası dahil), Portföy, Performans
(+7 part), Özet kartlarının tamamı, tekil varlık (+4 part), Yarış, Takip listesi,
Karşılaştırma, Portföy Hareketleri, Fiyat Alarmları, Ayarlar'ın tüm bölümleri, Profil,
Paywall, Yıllık Özet, CSV/toplu ekleme, tüm diyalog ve şeritler, varlık türü adları.

Dile bağlanan dört enum: `AssetType` (`labelOf`/`tickerHintOf`), dönem etiketleri
(`donemEtiketi`), `ContributionInterval` (tekil ad ikame etmek yerine tam cümle — Türkçe'de
ek uyumu sözcüğe göre değişiyor), `_DateRange`. Üçünde `label` alanı TÜRKÇE bırakıldı:
bildirim/özet/paylaşım metinleri ve alt kategori karşılaştırmaları onu VERİ gibi kullanıyor.

Kasıtlı Türkçe kalan dört ada ve nedenleri `TECHNICAL_DEBT.md`'de: yasal metinler,
`asset_categories` (sütunda veri), admin teşhis aracı, tanıtım turu. Varsayılan dil bu
yüzden hâlâ Türkçe.

Kaynak tarayan 11 test anahtar adlarına geçirildi; beşinde iddia ikiye bölündü — ekran
doğru ANAHTARI kullanıyor mu + o anahtarın Türkçe metni hâlâ o şeyi söylüyor mu
(`trMetni`, `test/helpers/kaynak.dart`). Tam paket 2.113 test yeşil.

## Son kalınan yer (2026-09-14)

Main ile birleşik, her adım analyzer + tam Flutter paketi (1.719 test) + Deno paketi (222 test)
ile doğrulandı.

**2026-09-14 (ikinci tur, kullanıcı kararları):** vadeli mevduat **silindi** (ekran, servis,
`deposits_enabled`, `AssetType.mevduat`, tüm "mevduat hariç" dalları; 0058 eski satırları
'diger'e çevirir). Yarış ve Paywall **kalıyor**; Sybil için 0059 (havuza girmek zaman ister:
≥7 günlük hesap, son 30 günde ≥5 gün snapshot, ≥2 tür). **Apple / Google ile giriş** kodu
tamam (`SocialAuthService`, `SocialSignInButtons`, sosyal hesapta şifresiz hesap silme);
sağlayıcı kimlikleri `YAPMAN_GEREKENLER.md` #15-16. Güvenlik: M1, M2, M7, M8, M9, L2, L4,
L5, L8, L12, L13, L14 kapandı (aşağıdaki tablo). Kalan: M12 (GoTrue dashboard, sende),
L3 (pinning: **yapılmıyor**, kullanıcı kararı 2026-09-14; gerekçe `TECHNICAL_DEBT.md`). **Tamamlanan:** Faz 0 (tümü), Faz 1 (tümü), Faz 2: 2.1–2.11, 2.13 (kısmi);
Faz 3: 3.2 (çekirdek), 3.3, 3.4, 3.5, 3.6, 3.7, 3.8 (kısmi), 3.9 (ortak altyapı), 3.10, 3.11,
3.15, 3.17, 3.19 (kısmi).

**2026-09-14 (üçüncü tur, P2→P4 sırası):** CI'da Google giriş define'ları secret'tan
(`GOOGLE_WEB_CLIENT_ID`/`GOOGLE_IOS_CLIENT_ID`; boşsa düğme gizli). Pinning için
karar önerisi (yapılmasın). iOS bildirim izni `checkPermissions()` ile ölçülüyor.
Altın gecikmesi için `slow_history_fetch` teşhis olayı. `seyreltSpots` silindi.
`add_asset_screen_overflow_test` (5 genişlik × 4 mod) — düzenleme modunda 320pt'te
**309px gerçek taşma buldu**, düzeltildi. Yüzdelik şeridi: 0061 medyan farkı +
"Getiri sıralaması" etiketi. Gün içi karşılaştırma açıldı. TÜFE karşılaştırma
ekranına basamaklı seri olarak eklendi. Light mode: ölü glass yardımcıları silindi,
`AssetType.onSurface` ile kategori ikon/metinleri ≥ 4,5:1. **Bilinçli atlananlar:**
3.2 baz para birimi (58 site, cihaz doğrulaması şart), 3.9 ekran birleştirme,
`signal_state` yeniden anahtarlama (tetikleyici şikâyet yok). ~~3.16~~, ~~fon NAV çapası~~,
~~mum grafik~~, ~~dev ekran parçalama~~, ~~yatırımcı seviyesi~~ ve ~~3.20~~ (beta) aynı gün
kapandı/açıldı (aşağıda).

**2026-09-14 (dördüncü tur, "dış bağımlılık" ikilisi):** **3.16** — dış bağımlılık
sanılan şey (test Supabase projesi) aslında eksik taban migration'ıydı; `0000` +
yerel yığın + seed + duman testi + `integration.yml` ile kapandı (tablo satırı).
**Fon NAV çapası** — TEFAS damga vermiyor, damga GÖZLEMLE üretildi: `observe-tefas-nav`
(0063, iş günü 30 dk'da bir) NAV tarihinin ilk görülme anını yazar,
`HistoryService.fonBasamakAni` basamağı oraya koyar; gözlem yoksa 10:00 aynen.
Sunucu ayağı `YAPMAN` #24. Deno 222+13 test, Flutter tam paket yeşil.

**2026-09-14 (beşinci tur, "atlananlar"):** **Mum grafik** — OHLC türetilerek
beşinci tip olarak eklendi (`mum_turetici`, kova bazlı; TECHNICAL_DEBT KAPANDI).
**Yatırımcı seviyesi** — Ayarlar › Görünüm'de opsiyonel Başlangıç/Orta/İleri
(varsayılan Orta = bugünkü görünüm); Başlangıç gizler, İleri risk-ayarlı getiri /
zamanlama etkisi / toparlanma kartı ekler (TECHNICAL_DEBT KAPANDI). **Dev ekran
parçalama** — `portfolio_performance_screen.dart` 4.600 → 650 satır (7 part:
`portfolio_performance/grafik_kabi, seriler, kontroller, kartlar, yardimci_widgetlar,
tur_dokumu_karti, ozet_yan_veri`), `asset_detail_screen.dart` 3.800 → 1.600 satır
(4 part: `asset_detail/eylemler, sinyal_widgetlari, seritler, karsilastirma_secici`).
Yöntem `part`/`part of` + State üyeleri için `extension` (aynı kütüphane, private
erişim aynen, davranış sıfır değişiklik; `setState` yerine `_guncelle` sarmalayıcısı).
Bölme betikle yapıldı (satır kopyası, elle düzenleme yok). Kaynak tarayan 25 test
`test/helpers/kaynak.dart` (`ekranKaynagiSync`: ana dosya + part'lar) ile güncellendi.
`build()` gövdeleri (perf ~600, detay ~1.300 satır) bilinçli olarak yerinde: onları
bölmek widget ağacını parçalamak demek, ayrı ve görsel doğrulama isteyen bir iş.
**İngilizce arayüz (3.20) — altyapı + çekirdek akış, BETA:** `l10n.yaml` + `lib/l10n/app_tr.arb`
(şablon) / `app_en.arb`, üretilen sınıflar `lib/l10n/generated/` (commit'li), `context.l10n`
(`lib/l10n/l10n.dart`; delegate yoksa Türkçe'ye düşer — 155+ widget testi değişmeden geçer),
`localeProvider` (`PrefKeys.locale`: tr/en/system; **varsayılan Türkçe**, sistem değil —
İngilizce cihaz kullanıcı seçmeden karışık arayüz görmesin), Ayarlar › Görünüm › Dil.
Çevrilen: giriş, kayıt (yasal metinler hariç), şifre sıfırlama, OTP, kilit ekranı, yasal uyarı
onayı, alt gezinme + çıkış onayı, Ayarlar hub'ı ve Görünüm (tema/dil/yatırımcı seviyesi),
ana ekran boş durumu + fiyat hatası, Portföy sekme başlıkları + boş durum, varlık ekleme
formu etiketleri (~130 anahtar). **Kalan (Türkçe):** ~1.900 literal — profil, lider tablosu,
performans/özet kartları, karşılaştırma, takip listesi, sinyal ayarları, paywall, recap,
onboarding turu, yasal belgeler (bilinçli), teşhis ekranı (admin). `l10n_coverage_test`
çevrilen dosyalarda Türkçe literal sayısını yalnızca-azalır tavana bağlar; `l10n_test`
tr/en anahtar paritesini ve geri dönüşü sabitler. Kapsam bitince varsayılan "sistem"e
çekilir ve "beta" notu kalkar (TECHNICAL_DEBT).

**Kalanlar ve neden burada durdu:**

| Kalem | Neden kod tarafında ilerlemedi |
|---|---|
| 3.1 Apple / Google ile giriş | ✅ Kod tamam (2026-09-14). Apple Developer yeteneği, Google Cloud OAuth kimlikleri ve Supabase provider ayarı sende (`YAPMAN_GEREKENLER.md` #15-16); Google düğmesi `GOOGLE_WEB_CLIENT_ID` verilmeden görünmez. |
| 3.2 Baz para birimi (USD/EUR/altın) | 🟡 Çekirdek 2026-09-14: Ayarlar › Görünüm'de TRY/USD/EUR/gram altın seçici (`baseCurrencyIndexProvider`, kişiye özel); `BazPara`/`ParaBicimi` (`utils/money_format.dart`) TRY tutarını bugünkü kurla çevirip yazar, kur yoksa ₺'ye düşer. Bağlanan yüzeyler: ana ekran hero + kişi kartları, Portföy (donut, varlık kartı, detay paneli), Performans (özet, grafik ekseni/tooltip, tür dökümü, dönem özeti, katkı kartı). 2. tur (aynı gün): tekil varlık ekranında dönem değişim TUTARI baz birime bağlandı (`_PeriodChangeRow.baz`); `money_format_scope_test` değer/fiyat kümelerini kaynakta kilitler (fiyat yüzeyleri `BazPara` kullanamaz). 3. tur (aynı gün): tekil varlık PnL şeridinin TOPLAM kâr/zararı ve hareket satırlarının tutarı da değer kümesine alındı (maliyet zaten bugünkü kurla çevriliyordu; aynı sınıf sayının ₺ kalması tutarsızdı). **Kalan (₺ sabit, bilinçli):** tekil varlık fiyat grafiği/ipucu/birim fiyatı ve takip listesi (kote fiyat), bildirim/özet metinleri (daily_summary, recap, milestone), ana ekran widget'ı ve Live Activity. Cihazda görsel doğrulama sende. |
| Ayarlar bilgi mimarisi (2026-09-14, yol haritası dışı) | ✅ Ayarlar sığ hub: Görünüm · Bildirimler · Hesap & Güvenlik · Yardım & Yasal (+ admin Tanılama). Yarış anahtarı Lider tablosu ekranına (menü: "Yarıştan ayrıl"), fiyat alarmı kurma varlık ekranına (app bar zili + alarm şeridi; hızlı ±%5/%10 hedefler), Portföy kartında aktif alarm rozeti; alarm listesi `priceAlertsProvider` tek kaynak. **Yapılmadı:** grafiğe uzun basınca "buraya alarm kur" (ZoomableChart etkileşimi ayrı tur), hero tutarına dokununca para birimi döngüsü. Cihazda görsel doğrulama sende. |
| Özeti paylaş — görsel kart (2026-09-14, yol haritası dışı, kullanıcı isteği) | ✅ "Özetini paylaş" dört satır metni doğrudan sistem sayfasına veriyordu — kullanıcı ne paylaştığını görmüyordu ("arkası boş"). Şimdi `showShareSheet`: önizlemeli 320×400 koyu kart (`widgets/share_card.dart`, `ShareCard`/`ShareCardData`), `RepaintBoundary` → PNG (`services/share_card_service.dart`), "Görsel olarak paylaş" (PNG + metin) / "Metin olarak paylaş". Dönem özeti ve yıllık özet aynı kartı kullanır; kartta TUTAR yok (kaynak taraması testi), metin ölçeği 1,3× ile sınırlı (HIG ratchet'i ile uyumlu). `share_card_test` (10). Cihazda görsel doğrulama sende. |
| 3.9 Performans ekranlarını birleştir | 🟡 İlk adım 2026-09-14: ortak altyapı çıkarıldı — `TransactionSegment` tek model (`widgets/transaction_segment.dart`; tekil varlık ekranındaki ölü `dashed` bayrağı `piyasaKapali` ile birleşti), tam ekran çipi `ChartFullscreenChip`. Asıl birleştirme (8.4k satır, iki ekranın gün içi/kapalı piyasa/fon basamağı davranışları) gerçek cihazda görsel doğrulama ister; parite testleri güvenlik ağı olarak duruyor. |
| 3.10 `add_asset_screen` Notifier'a taşı | ✅ 2026-09-14: durum makinesi `providers/add_asset_form_provider.dart` (`AddAssetFormNotifier`, `AddAssetPriceLookup` kapısı, `parseQuickEntry`); ekranda `_AddAssetScreenState` içinde `setState` kalmadı (ratchet testi). Metin controller'ları ekranda, geçişler `AlanYazimi` döner. 22 birim testi. |
| 3.12 Yarış / 3.13 Paywall | Kullanıcı kararı (2026-09-14): ikisi de KALIR; Sybil çözümü 0059 ile uygulandı. 3.14 vadeli mevduat SİLİNDİ (aşağıda). |
| 3.16 integration_test | ✅ 2026-09-14: hosted proje GEREKMİYORDU — asıl eksik taban şemanın migration olarak var olmamasıydı (defter 0007'den başlıyordu, `supabase db reset` sıfırdan ortam kuramıyordu). `0000_base_schema.sql` (git 1b23813'teki `supabase_schema.sql`'in 0008-sonrası, idempotent hâli; canlıda deftere işaretlenecek → `YAPMAN` #24), `supabase/config.toml` + `seed.sql` (tohum kullanıcı `smoke@sandik.test`, onboarding tamam, yasal uyarı bilinçli onaysız). `integration_test/smoke_test.dart`: gerçek `app.main()` → giriş → yasal uyarı → FAB → "Diğer" türü elle fiyatlı varlık → Portföy'de görünür. `tool/supabase_smoke.sh`: aynı akış Flutter'sız (GoTrue token + PostgREST + RLS reddi). `.github/workflows/integration.yml`: `supabase start` → başsız duman → Android emülatörü (api 34, KVM) → integration_test. **Bu oturumda koşulamadı** (Docker daemon ve KVM yok); 0000 + 0008 + seed + 0063 yerel Postgres 16'da stub auth şemasıyla doğrulandı (idempotent, RLS/GRANT), Flutter tarafı analyze temiz. İlk CI koşusunda emülatör işi kırılabilir — `supabase-smoke` işi yeşilse sorun uygulama/emülatör tarafındadır. |
| 3.18 Swift widget derleme CI | ✅ Zaten kapalı (2026-09-14 tespiti): `ios-testflight.yml` `flutter build ios` ile widget extension'ı her main push'unda derliyor; uygulama TestFlight'ta. Ayrı `xcodebuild` adımı gereksiz. |
| 3.20 İngilizce arayüz | 🟡 BETA (2026-09-14): altyapı + çekirdek akış çevrildi, dil seçici Ayarlar › Görünüm'de; kalan ekranlar Türkçe (yukarıdaki paragraf). |
| 2.12 / 2.14 | Görsel doğrulama isteyen UI kalemleri (segment kontrolleri, hero yeniden tasarımı); cihazsız yapılmadı. 2.10 ve 2.13 2026-09-14'te kapandı. |
| 3.8 dış bağlantı köprüsü, 3.19 sertifika pinning | 3.8: ✅ kod tamam (2026-09-14) — `app_links` ile `DeepLinkService` (`sandik://asset/<id>` → `openAssetPerformance`; widget/live-activity host'ları `HomeWidgetService`'e bırakıldı, çift işleme yok). **Cihazda doğrulanmadı** (tarayıcıdan `sandik://asset/<id>` aç). 3.19: ✅ kapandı — pinning yapılmıyor (kullanıcı kararı 2026-09-14), FORCE RLS (L9) ve db_logs retention (L6) 0056 ile canlıda. |

**Senin tarafında bekleyenler** (`YAPMAN_GEREKENLER.md` en üst tablo): secret rotasyonu, 7 cron
secret'ının `x-cron-secret` desenine göre set edilmesi, `DELETION_HASH_SALT`, edge function
deploy'ları, 0055/0056/0057 migration'ları, biyometrik kilidin cihazda denenmesi, GoTrue rate
limit'leri.

## Güvenlik bulguları — ikinci tur kapanışları (2026-09-14)

| Bulgu | Durum | Ne yapıldı |
|---|---|---|
| M1 Sybil | ✅ 0059 | `leaderboard_eligible_users()` (istemciye kapalı) tek kaynak; iki RPC de havuzu bununla JOIN'ler ve çağıranın kendisi de uygun olmalı. k_min=8 / n_max=4 korunur (`percentile_strip_test` + `leaderboard_sybil_eligibility_test`). |
| M2 Token düz depoda | ✅ | `lib/services/secure_session_storage.dart`: `LocalStorage` Keychain/Keystore üstünde; ilk açılışta SharedPreferences'taki eski oturum taşınır ve silinir (yeniden giriş yok). Kasa okunamazsa oturum yok sayılır, çökme yok. |
| M7 Davet limiti hesaba keyli | ✅ | `redeem-invite-code`: `ip:<x-forwarded-for>` öznesiyle ikinci sayaç (10 dk / 20); başarısız tahminde ikisi de artar. IP yoksa eski davranış. |
| M8 UUID sızıntısı | ✅ | Redeem yanıtından `partner_user_id` çıkarıldı; istemci kullanmıyordu. |
| M9 Admin e-postayla | ✅ 0060 | `push_admins(user_id)` tablosu, 0021 adresinden BİR kez tohumlanır; `is_push_admin()` UUID'ye bakar. |
| L2 Idle logout kill sonrası yok | ✅ | `PrefKeys.backgroundedAtMs` arkaya alınınca yazılır; açılışta ≥10 dk ise ilk kullanıcı yayınında `logout()`. |
| L4 Cron CORS `*` | ✅ | 6 cron fonksiyonu + `cron_auth.ts` 401 yanıtı: Allow-Origin yok (tarayıcı çağrısı yok). |
| L5 Maske listeye inmiyor | ✅ | `DbLogger._maskValue` liste ve Map'e özyineler. |
| L8 Dışa aktarımda ham hata | ✅ | Sabit metin + Crashlytics non-fatal. |
| L12 Şifre üst sınırı | ✅ | 72 bayt (bcrypt), mesajla. |
| L13 Hedef reddi kodu yakıyor | ✅ | Hedef vazgeçince `to_user_id/requester_name` sıfırlanır, `used` değişmez; sahibin reddi eskisi gibi yakar. |
| L14 Çıkışta iz | ✅ | `rl_attempts_*` ve `push_device_id` silinir. |
| M12 GoTrue throttle | ⏳ sende | Dashboard (`YAPMAN` #10). |
| L3 Sertifika pinning | ✅ karar: yapılmıyor (2026-09-14) | Pre-mortem `TECHNICAL_DEBT.md`'de: `*.supabase.co` sertifikası haber verilmeden döner, pin uyuşmazlığı = mağaza güncellemesine kadar tam kesinti; Android 7+ kullanıcı CA'larını zaten reddediyor; veri JWT+RLS arkasında. Kullanıcı onayladı. |

## Faz 0 — Kanamayı durdur

| # | Durum | Not |
|---|---|---|
| 0.1 | 🟡 Kod tarafı yapıldı | `tmp/` git'ten silindi, `.gitignore`'a eklendi. **Secret rotasyonu ve geçmiş temizliği SENDE** (`YAPMAN_GEREKENLER.md` en üst tablo #1-2). |
| 0.2 | ✅ | `push-live-activity`: main'in `x-cron-secret` desenine (0054) bağlandı + `cronSecretZorunlu` fail-closed; `userId` kâhini kaldırıldı, hata mesajı sabit koda çevrildi. Deploy + secret sende (#3, #6). |
| 0.3 | ✅ (main ile birleşti) | Main aynı sırada `x-cron-secret` desenine geçmişti (gateway JWT'yi Authorization'da istiyor; Bearer <secret> gateway'de 401 alıyordu — benim ilk sürümüm de o tuzağa düşerdi). Birleşimde main'in `cronYetkisiVarMi` API'si korundu, üstüne `cronSecretZorunlu` (secret yoksa 503; yerelde `CRON_AUTH_ALLOW_UNSET=1`) ve `sabitZamanliEsit` eklendi. 7 fonksiyon bu iki kapıyı sırayla çağırıyor. |
| 0.4 | ✅ | `send-partner-invite-push` yanıtı `{ok, delivered}`; ham hata echo'su kaldırıldı. İstemci `results` okumuyordu — kırılma yok. |
| 0.5 | ✅ | `build.gradle.kts`: `key.properties` yoksa `GradleException`. |
| 0.6 | ✅ | `supabase_reset.sql` silindi; `supabase_schema.sql` migrations'a işaret eden nota indirildi. |
| 0.7 | ✅ | `delete-account`: `DELETION_HASH_SALT` varsayılanı kaldırıldı (yoksa 503), `detail` echo'su kaldırıldı. Secret set etme sende (#5). |
| 0.8 | ✅ | `main_navigation_screen.dart`: çıkış onayı `SystemNavigator.pop()`. |
| 0.9 | ✅ | `.github/workflows/ci.yml`: PR + main'de `flutter analyze` + `flutter test`; ayrı job'da `deno check` + `deno test`. **İlk koşuda kırılabilir** — özellikle deno job'ı (testlerin izin gereksinimi `--allow-all` ile geçildi, `deno check` importları çözemezse job'ı gevşet). |
| 0.10 | ✅ | `SupabaseService.isPushAdmin()` + `isPushAdminProvider` + Ayarlar tile'ı yalnızca admin'e; "GELİŞTİRİCİ" → "TANILAMA"; `adaptiveRoute`. Debug "Test Crash" tile'ı admin'den bağımsız ayrı bloğa alındı. Migration `0055` GRANT — koşulması sende (#7). (Main ile birleşince 0054 numarası cron-auth migration'ına gitti.) |

## Faz 1 — Temizlik ve tutarlılık altyapısı

| # | Durum | Not |
|---|---|---|
| 1.1 | ✅ (kısmi) | Silindi: `asset_detail_screen.dart`, `portfolio_detail_screen.dart`, `premium_gate.dart`, `PortfoyTakip.xcodeproj/`, `assets/images/sandik_original_circle.png` + `splash_icon.png` (Android kendi drawable kopyasını kullanıyor). `tools/` → `tool/` birleşti. `chart_interaction_parity_test` listesi güncellendi. **Bilerek bırakıldı:** `bar_interval_selector.dart` (kullanıcının son commit'i, bağlanması bekleniyor), `chart_downsample`/`series_downsample` (`TECHNICAL_DEBT.md` "ERTELENDİ" kaydı var), `store_listing/screenshots/orig+raw` (`build_screenshots.py` raw/ okuyor). |
| 1.2 | ✅ | 17 kök doküman → `docs/archive/` ("ARŞİV" başlığıyla), çapraz bağlantılar düzeltildi. `README.md` dizin oldu. `CLAUDE.md` yeniden yazıldı: sqflite/Provider/emülatör-ilk-kurulum kaldırıldı, kurallar (tasarım sistemi, para/tarih, hata, navigasyon, katmanlama, sunucu, gizli anahtar) tek yerde, Windows yolları "yerel makine notları" bölümünde. |
| 1.3 | ✅ | `lib/utils/sandik_snack.dart`: `sandikSnack(kind: neutral/success/warning/error, onUndo, action)` + `sandikSnackError` (friendlyError zorunlu). 30 `showSnackBar` sitesi + 12 ham `$e`/`e.toString()` sitesi geçirildi (profil, toplu ekleme, mevduat, temettü, hızlı işlem, ortaklık istekleri, alarm). Push teşhisi ham hatayı bilinçli koruyor (admin aracı). `test/sandik_snack_test.dart`: ham hata sızmaz, undo çalışır, kuyruk birikmez, `showSnackBar` yalnızca yardımcıda (ratchet). L7 şifre metni 8+harf+rakam ile hizalandı. Nav bar inset eklenmedi: dış Scaffold `extendBody` kullanmıyor, sekme Scaffold'u nav bar'ın üstünde bitiyor. |
| 1.4 | ✅ | `tr_format.dart`: `tryFormatter(digits, symbol)`, `qtyFormatter`, `fixedFormatter`, `dayKey`. 20 `NumberFormat.currency` + 13 `NumberFormat('#…')` kopyası bunlara bağlandı (ondalık sayısı çağıranda kaldı, locale/sembol tek yerde). 38 `DateTime(y,m,d)` → `dayKey`. 17 `toStringAsFixed` → `fmtNum` (leaderboard `12.5%` → `12,5%` TR ayracı düzeldi); kalan 5'i eksen sözleşmeli, bilinçli. `context.signColor(v)` eklendi, 5 satır içi kazanç/kayıp üçlüsü buna geçti. `test/tr_format_single_source_test.dart` ratchet. Kullanılmayan `intl` importları temizlendi. |
| 1.5 | ✅ | `lib/config/pref_keys.dart` (`PrefKeys`): 18 `pref_*` anahtarı tek yerde; `preferences_provider`, `notification_service`, `surface_theme` buna bağlandı. `test/pref_keys_single_source_test.dart`: literal PrefKeys dışında yazılamaz + benzersizlik. `sandik_*` (widget IPC) ve `retention_*` bilinçli kapsam dışı. |
| 1.6 | ✅ (silme ile) | `Asset.toMap()/fromMap()` lib+test'te SIFIR çağıran — "partner kod payload" yorumu bayattı. Alan paritesi kurmak yerine ölü çift SİLİNDİ; tek serileştirme şeması `toSupabase/fromSupabase`. |
| 1.7 | ✅ (auth kapsamı) | `lib/services/crash_reporter.dart`: `CrashReporter.report(e, st, reason:)` — sanitize + non-fatal + Firebase yoksa no-op. `auth_service`'teki 7 jenerik `catch (e)` buna bağlandı ve kullanıcı mesajı `friendlyError(e)` üzerinden. `remote_push_service` breadcrumb'ında tam UUID yerine ilk 8 karakter (M6). Diğer servislerdeki bilinçli `catch (_)` blokları (yorum gerekçeli) dokunulmadı. |
| 1.8 | ✅ (kısmi) | Kayıt hatası artık hesap varlığını doğrulamıyor (M4). Şifre sıfırlama OTP'sinde 6 hane kontrolü. **Login/OTP sunucu tarafı throttle (M12) yapılmadı**: istemci sayacı güvenlik sınırı değil (S1 dersi); doğru yer GoTrue rate limit ayarları — `YAPMAN_GEREKENLER.md` #10. |
| 1.9 | ✅ | `flutter_launcher_icons` → `dev_dependencies`. 2026-09-14: `google_fonts` kaldırıldı (DM Sans paketli, `kSandikFontFamily`/`sandikFont`), `flutter_lints` 6 + strict analyzer (`unawaited_futures`, strict-casts/inference/raw-types); `avoid_dynamic_calls` bilinçli kapalı (127 site). |
| 1.10 | ✅ | `test/design_token_ratchet_test.dart`: `Colors.*` ≤ 89 satır, `fontSize:` ≤ 181 satır (tema dışı). |
| 1.11 | ✅ (kısmi) | `lib/utils/polling.dart`: `ForegroundPoller` (arka planda durur, üst üste binmez) ve `BackoffPoller` (3→15 sn, 10 dk tavan). Profil bekleyen istekler ve ortaklık istekleri ekranı 5 sn → 20 sn + arka planda durur; davet durumu yoklaması geri çekilmeli. **Leaderboard'daki 5 tick timer dokunulmadı** — ekran Faz 3.12 kararına bağlı (kapatılabilir). |
| 1.12 | ✅ | `FxRateMigrationService.runFor` kullanıcı başına günde bir kez (`PrefKeys.fxMigrationLastRunMs_<uid>`); yeniden deneme davranışı korunuyor. |

## Faz 2 — UX tutarlılığı ve modern UI

| # | Durum | Not |
|---|---|---|
| 2.1 | ✅ | `lib/widgets/sandik_skeleton.dart`: `SandikSkeleton` (nabız, reduce-motion'da sabit), `SandikSkeletonList`, `SandikSkeletonChart`. Alarm listesi ve karşılaştırma grafiği iskelete geçti; 5 ekrandaki ham `CircularProgressIndicator` → `CustomLoadingIndicator`/iskelet (onboarding'deki ilerleme halkası bilinçli istisna). `test/loading_and_refresh_parity_test.dart` kilitliyor. |
| 2.2 | ✅ | Pull-to-refresh 3 → 11 veri ekranı: Performans sekmesi (fiyat + gün içi future sıfırlama), varlık detayı, takip listesi, takip detayı, alarmlar, tüm hareketler, karşılaştırma (periyot yeniden çekimi), profil (ortaklar). Test listeyi kilitliyor. |
| 2.3 | ✅ | `showSandikConfirm()` (`friendly_error.dart`): tek onay yüzeyi, `destructive` → loss + uyarı ikonu, `detail` kutusu. `_SandikDialogShell` tek/çift eylemli dialogların ortak kabuğu (`_SandikDialog` da ona geçti; GoogleFonts/Colors kopyaları düştü). `lib/widgets/delete_asset_dialog.dart`: iki kopya "varlığı sil" → `confirmAndDeletePosition`. 9 onay sitesi geçti: çıkış, sepet temizle, bildirim silme, ortaklık iptal/kaldır, oturum kapatma, takipten çıkar, de-dup sıfırlama, hesap silme 1. kademe. Kalan `AlertDialog`'lar form/doküman (izin listesi testte). `test/sandik_confirm_test.dart`. |
| 2.4 | ✅ (kısmi) | `_SectionTitle` klonları (settings 10, profile 4) → `SandikSectionHeader`. `SandikCard` benimsemesi (307 ad-hoc BoxDecoration) ayrı tur — büyük ve görsel doğrulama ister. |
| 2.5 | ✅ | `lib/widgets/sandik_app_bar.dart`: tek zemin, tek başlık stili (headlineSmall w700, tek satır), tek geri oku (yalnızca pop edilebiliyorsa). 14 ekrandaki `appBar: AppBar(` buna geçti (`transparent`, `backgroundColor`, `showBack`, `onBack`, `titleWidget` seçenekleriyle). `test/sandik_app_bar_test.dart` ratchet + davranış. Ana ekrandaki SliverAppBar bilinçli ayrı (büyük başlık + 5 kontrol). |
| 2.6 | ✅ | Onay dialogları ve 4 UI metni `sen` kipine çekildi; yasal metinler bilinçli `siz`. `en_US` `supportedLocales`'tan çıkarıldı (gerekçe main.dart'ta). Kullanıcı metinlerindeki 3 emoji kaldırıldı (db_logger/teşhis log'ları geliştiriciye, kaldı). Bölüm başlıkları: ana ekranın iki büyük harf başlığı da `SandikSectionHeader`'a geçti — tek kasa. |
| 2.7 | ✅ | (1) OTP doğrulaması sonrası sorumluluk reddi kaydı otomatik düşülüyor — kayıt ekranındaki 'Yasal Koşullar' onayı zaten disclaimer'ı içeriyordu; `DisclaimerAcceptanceScreen` artık yalnızca eski/kaydı olmayan hesaplara çıkar. (2) **'Belgeyi açıp sonuna kadar kaydır' kapısı kaldırıldı** — kutu doğrudan işaretlenir, belge bağlantısı bir dokunuş uzakta. ⚠️ Hukuki tarafta bilinçli karar: KVKK açık rıza 'bilgilendirilmiş' olmayı ister, 'sonuna kadar kaydırılmış' olmayı değil; itiraz edersen `_LegalConsentBox.onTap` tek satırla eski davranışa döner. (3) Turda 'Atla' zaten vardı; Ayarlar → Destek'e 'Tanıtım turunu yeniden izle' eklendi. |
| 2.8 | ✅ (boş durum) | Ana ekranda kendi görünümü + sıfır varlık = `_EmptyPortfolioCta` özetin hemen altında; şeritler, kişi kartları, filtre çipleri ve iki boş başlık gizli. Tür filtresi boşken aynı bileşen 'Bu türde varlık yok' diliyle. **3 şeridi tek yatay karta toplama yapılmadı** — şeritler zaten kendi kendini gizliyor; dolu portföyde katlama üstü sorunu ölçülmeden yeniden düzenlemek erken. |
| 2.9 | ✅ (adlar) | `charts_screen.dart`/`ChartsScreen` → `portfolio_screen.dart`/`PortfolioScreen`; `performance_screen.dart`/`PerformanceScreen` → `asset_detail_screen.dart`/`AssetDetailScreen`. 73 dosya (lib, test kaynak-metin yolları, CLAUDE.md, TECHNICAL_DEBT.md) tek geçişte; arşiv dokümanlar eski adla kaldı. **Geri tuşu sekme geçmişi ve predictive back yapılmadı** — `PopScope(canPop:false)` çıkış onayıyla iç içe; ayrı bir tasarım kararı. |
| 2.10 | ✅ | 2026-09-14: takip listesi ve varlık silmede snack üzerinden geri al (`restorePositionLots` — lotlar geri, silme log'u kaldırılır). |
| 2.11 | ✅ (zaten) | Denetim iddiası eskiydi: `chart_interaction_parity_test` karşılaştırma ve takip grafiklerinin `PercentComparisonChart` → `ZoomableChart` üzerinde olduğunu zaten kilitliyor (pinch/pan/crosshair paritesi var). Sparkline bilinçli etkileşimsiz. |
| 2.12 | ⏸️ | `ModernTabSelector`/`_PeriodToggle` markaya özel; Material `SegmentedButton`'a geçmek tasarım dilini değiştirir ve cihazda görülmeden yapılmaz. |
| 2.13 | ✅ | `ZoomableChart.semanticLabel`; sparkline bilinçli sessiz. 2026-09-14: `minimumSize: Size.zero` butonlar 44pt'ye çıkarıldı (`SandikTouch.min`, `touch_target_size_test` ratchet); add_asset çipleri (tür/döviz/miktar/altın) ve seçiciler `Semantics(button, selected, label)` taşıyor; sign-renkli sayıların 7 sitesi de +/− işareti basıyor (ok glifi gereksiz). Kalan yok. |
| 2.14 | ⏸️ | Hero uçuşu iki uçtaki boyut farkında bozuk görünür; cihaz doğrulaması olmadan eklenmedi. |

## Faz 3 — Ürün ve mimari

| # | Durum | Not |
|---|---|---|
| 3.1 | ✅ | `lib/services/social_auth_service.dart` (Apple: rastgele nonce → SHA-256 Apple'a, ham nonce Supabase'e; Google: `serverClientId`=Web istemci), `AuthService.loginWithSocial` (profil yoksa yazar; Apple adı yalnızca ilk girişte gelir), `AuthNotifier.loginWithSocial` (vazgeçme = hata değil), `lib/widgets/social_sign_in_buttons.dart` giriş + kayıt ekranında (Apple yalnızca iOS, Google yalnızca yapılandırıldıysa). Şifresiz hesapta hesap silme: `delete-account` `{provider,id_token,nonce}` alır, `signInWithIdToken` ile doğrular ve `data.user.id === user.id` şartı koyar. iOS `applesignin` entitlement eklendi; Info.plist ters Google URL şeması kimlik gerektirdiği için elle (#16-d). Testler: `test/social_sign_in_test.dart`. |
| 3.14 | ✅ SİLİNDİ | Kullanıcı kararı. `add_deposit_screen.dart`, `deposit_service.dart`, `deposits_enabled`, `visibleAssetTypes`/`filterHiddenTypes`, `AssetType.mevduat`, `PortfolioCharacter.mevduatci`, `_DepositDetailsPanel`, TS `'mevduat'` dalları gitti; `piyasaKapaliEtiketi` kuralı döviz/emtia/altın için aynen. 0058: eski satırlar 'diger' + not (silinmez). Testler: mevduat vakaları çıkarıldı, `tefas_model_test.dart` kaldı. |
| 3.3 | ✅ (ucuz biçim) | Karşılaştır ekranına tek dokunuşlu kıyas çipleri: Portföyüm / BIST 100 / Dolar / Gram altın (`SymbolSearchService`'in tanıdığı semboller, yeni veri yolu yok). Performans sekmesine overlay eklenmedi — o ekran Faz 3.9 birleşmesini bekliyor. |
| 3.4 | ✅ (gerçekleşen K/Z) | `PortfolioState.realizedGainLoss` + `hasRealized`: Σ(satış − maliyet)×miktar×alım kuru, `sell_price`'sız eski satırlar atlanır. Özet kartında "Satışlardan gerçekleşen: ±₺x" satırı (yalnızca satış varsa) + ekran okuyucu cümlesi. Bedelsiz/split işlem tipi eklenmedi (şema + ekleme akışı ister). `test/realized_gain_and_cache_test.dart`. |
| 3.6 | ✅ (cihazda doğrulanmadı) | `local_auth` eklendi. `BiometricLockService` (available/authenticate, asla fırlatmaz, PIN de kabul), `LockScreen` (içerik kurulmadan önce, otomatik ister), `_AuthGate`: soğuk açılışta ve 30 sn+ arka plandan dönüşte kilit; çıkışta sıfırlanır. Ayarlar → Hesap → 'Biyometrik kilit' (açarken bir kez doğrular; cihaz desteklemiyorsa uyarır). Android: `USE_BIOMETRIC` + `MainActivity` → `FlutterFragmentActivity` (local_auth şartı; splash API'si FragmentActivity ile de çalışır). iOS: `NSFaceIDUsageDescription`. ⚠️ Gerçek cihazda bir kez denenmeli. |
| 3.7 | ✅ | `lib/services/portfolio_cache.dart`: başarılı çekimde defter (`toSupabase` JSON) prefs'e yazılır; çekim başarısızsa önbellekten açılır ve `errorMessage` ile mevcut çevrimdışı şeridi çıkar; önbellek yoksa eski davranış (hata). Kullanıcı kimliğine bağlı anahtar, çıkışta silinir. Fiyat önbelleği bilinçli ayrı tutuldu. |
| 3.8 | ✅ (cihaz testi bekliyor) | `DeepLinkRouter.hedefVarlikId`: `sandik://asset/<id>` → `NotificationService.openAssetPerformance` (push ile aynı yol). Android manifest'e `sandik` şeması için VIEW/BROWSABLE intent-filter eklendi (iOS'ta `CFBundleURLSchemes` zaten vardı). 2026-09-14: köprü kuruldu — `app_links` + `services/deep_link_service.dart` (`main.dart`'ta bildirim servisinden sonra init; yalnızca `asset` host'u, diğerleri `HomeWidgetService`'te). 2026-09-15: `flutter_deeplinking_enabled` Flutter 3.44'te VARSAYILAN AÇIK çıktı — motor intent'i Navigator'a `/<id>` rotası diye itip "Could not find a generator for route" hatasını Crashlytics'e düşürüyordu (emülatörde `adb shell am start` ile görüldü); manifest'te `false`, iOS'ta `FlutterDeepLinkingEnabled=false`. Sahte / başkasına ait / silinmiş id → `AssetNotFoundScreen` (yalnızca dış bağlantı yolunda; push yolu sessiz; oturum yoksa sessiz). `test/deep_link_asset_test.dart`, `test/deep_link_service_test.dart` (karar + wiring + manifest/plist). **Cihaz testi sende.** |
| 3.15 | ✅ (dışa aktarım) | Dışa aktarım 7 → 13 tablo: watchlist, price_alerts, signal_preferences, signal_notifications, milestones, live_activity_sessions eklendi (`export_version` artırıldı). İçe aktarım (geri yükleme) yapılmadı — şema doğrulaması + çakışma politikası ister. |
| 3.19 | ✅ | `0056_force_rls_and_db_logs_retention.sql`: 19 tabloda `FORCE ROW LEVEL SECURITY` (var olanlara, `to_regclass` ile), `cleanup_db_logs()` + günlük 03:15 UTC pg_cron işi (30 gün). **Sertifika pinning yapılmıyor — kullanıcı kararı 2026-09-14** (kesinti riski > fayda; pre-mortem `TECHNICAL_DEBT.md`). 0056 canlıda (2026-09-14). |
| 3.5 | ✅ (yapıştır biçimi) | `CsvImportService.parse` (saf): ayraç otomatik (`;`/`,`/sekme), TR/EN başlık takma adları, başlıksız sıra `sembol, adet, fiyat, tarih`, TR sayı, 3 tarih biçimi, tür sütunu ya da semboldan çıkarım (`inferType`), `.IS`/`USDTRY=X`/altın alt türü normalizasyonu; hatalı satır atlanır, nedeni listelenir. `CsvImportScreen`: yapıştır → önizle → sepete ekle (kayıt toplu ekleme ekranında; fiyatı boş satırlar kapanışı orada çeker). Giriş: Toplu Ekle app bar ikonu + boş sepet düğmesi. **Dosya seçici bilerek yok** (eklenti + izin akışı yerine kopyala-yapıştır). Aracı kurum özel biçimleri (Midas/İş Yatırım) eklenmedi — örnek ekstre gerekir. `test/csv_import_service_test.dart`. |
| 3.17 | ✅ | `tefas_model_test`; 2026-09-14: `price_alert_service` (`PriceAlertStore` kapısı), `data_export_service` (saf `belgeKur`/`topla`), `remote_push_service` (`push_message_router`) testli; `add_asset_form_provider` (22) ve `money_format` (10) eklendi. |
| 3.11 | ✅ (sessiz saatler) | `profiles.quiet_start/quiet_end` (0057, TR saati, sarmalı pencere), `_shared/quiet_hours.ts` (`sessizSaatteMi`, `sessizKullanicilar`), 4 proaktif fonksiyon (brifing, haftalık özet, takvim, fiyat alarmı) sessiz saatte ATLAR (alarm damgalanmaz — pencere bitince koşul sürüyorsa gider). İstemci: `quietHoursProvider` (sunucu kaynaklı), Ayarlar → Bildirimler → 'Sessiz saatler' anahtarı + başlangıç/bitiş kutuları. Sinyaller kendi tür bazlı penceresinde kaldı. **Global sıklık tavanı eklenmedi** — haftalık tavan zaten sunucuda (RETENTION §7). `supabase/tests/quiet_hours_test.ts`. |
