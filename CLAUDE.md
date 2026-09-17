# Claude Development Guidelines — sandık

## Proje

**sandık** — kişisel portföy takibi (BIST hisse, TEFAS fon, döviz, altın, emtia).
Flutter + **Riverpod** istemci; **Supabase** arka uç (Postgres + RLS, Edge Functions, pg_cron,
Vault); Firebase (Crashlytics, Analytics, Remote Config, FCM); iOS Live Activity ve
Android/iOS ana ekran widget'ları.

Yerel veritabanı **yoktur** (sqflite/Provider paketi eski prototipten kalmaydı, kaldırıldı).
Kalıcılık: Supabase (sunucu) + `shared_preferences` (tercihler, widget sözleşmesi).

Durum: TestFlight'ta; Play yayını `PLAY_STORE_YAYIN_REHBERI.md`. Güncel değerlendirme ve
yol haritası: `docs/DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md`; ilerleme
`docs/YOL_HARITASI_ILERLEME.md`.

## Çalışma biçimi

1. **Değişiklikleri onay beklemeden yap**, sonunda özetle. Kullanıcı sonuçları toplu inceler.
2. Özet: ne değişti, neden, hangi karar verildi. Teknik ayrıntı gerektiğinde ver.
3. Kaynak yorumları **karar kaydıdır** ("ne" değil "neden"). Bu üslubu koru; var olan
   gerekçeleri silme, güncelle.
4. **Her geliştirme talebi önce kurulu skill'e/komuta yönlendirilir.** Kod yazmaya
   başlamadan önce aşağıdaki tablodan ilgili skill'i çağır; hiçbiri uymuyorsa bunu
   özette **"skill dışı"** diye söyle ve neden uymadığını yaz. Skill'siz çalışmak
   istisnadır, varsayılan değildir.

### Talep → skill/komut yönlendirmesi

Sıra önemlidir: **üstteki kazanır.** Bir talep birden çok satıra uyuyorsa en üstteki
seçilir; ikisi de gerekiyorsa ikisini de çağır ama çakışma kuralına (aşağıda) bak.

| Talep | Çağrılacak |
|---|---|
| Flutter UI / widget / ekran | `flutter-architecture`, `flutter-adaptive-ui`, `flutter-expert` ⚠️ |
| Navigasyon | `flutter-navigation` (**`flutter-expert` GoRouter referansı değil**) |
| Animasyon / hareket | `flutter-animations`, `animate`, `apple-design` |
| Görsel tasarım / cila | `emil-design-eng`, `ui-ux-pro-max`, `frontend-design` |
| Flutter testi | `flutter-testing` (**`test-master` değil**) |
| Test *stratejisi* / kapsam boşluğu | `test-master` |
| Supabase şema / migration / RPC | `sql-pro` → yazım, `postgres-pro` → PG'ye özgü |
| Yavaş sorgu teşhisi | `database-optimizer` |
| Auth / RLS / GRANT / güvenlik *yazarken* | `secure-code-guardian` |
| Güvenlik *denetimi* (rapor) | `/security-review` → sonra `security-reviewer` |
| Kod incelemesi | `/code-review` → sonra `code-reviewer` |
| Sadeleştirme / tekrar temizliği | `/simplify` |
| Hata / çökme / stack trace | `debugging-wizard` |
| iOS Swift (Live Activity, widget) | `swift-expert` |
| Mimari karar / ADR | `architecture-designer` (ADR → `manage_adr`, dosyaya değil) |
| Dokümantasyon | `code-documenter` |
| Dokümansız kodu çözme | `spec-miner` |
| Bir kararı zorlatma / pre-mortem | `the-fool` |
| Video / tanıtım filmi / motion graphics | `remotion-motion-graphics` (**her video talebinde**; araç Remotion, npm'den) |
| Anlatımlı tanıtım / launch videosu ("brag") | `brag` → Hyperframes (`npx hyperframes`); çıktı `store_listing/preview_video/brag-output/`. Türkçe ses Kokoro'da yok → edge-tts `tr-TR-*Neural` |
| Uygulamayı çalıştırıp görme | `/run`, `tool/deploy_emulators.sh` |

**Çakışma kuralı — skill CLAUDE.md'yi asla ezmez.** Skill ile bu dosya çeliştiğinde
**bu dosya kazanır**; çelişkiyi özette yaz. Bilinen tuzaklar:
- `flutter-expert` → Bloc ve GoRouter önerir. Burada **Riverpod** + `adaptiveRoute`.
  Ayrıca ham `Colors.*` / `fontSize:` üretir — tasarım sistemi kuralı geçerlidir.
- `test-master` → Flutter/Dart bilmez (k6/Artillery/OWASP odaklı).
- `secure-code-guardian` → örnekleri web (Zod, CORS/CSP). Buradaki karşılığı
  **RLS + GRANT + `requireCronSecret()`**.
- Web kaynaklı tasarım skill'leri → CSS/React sözdizimi **alınmaz**, yargısı alınır.

Gerekçeler ve kurulmayanların listesi: `.claude/skills/SKILLS_README.md`.

### Onay eşikleri
- **Sormadan yap:** biçimlendirme, lint, hata düzeltme, test ekleme, dokümantasyon,
  refactor, performans, minör bağımlılık güncellemesi.
- **Yap ama özette işaretle:** yeni özellik, mimari refactor, API/servis entegrasyonu,
  şema değişikliği, kırıcı değişiklik.
- **Yap ama açıkça bayrakla:** çekirdek işlev kaldırma, kimlik doğrulama/güvenlik mantığı,
  büyük mimari değişiklik.
- **Asla kendiliğinden yapma:** git geçmişi yeniden yazma, force push, canlı secret
  rotasyonu, mağaza/hukuki adımlar (bunlar `YAPMAN_GEREKENLER.md`'ye yazılır).

## Proje yapısı

```
lib/config/      supabase_config.dart — yalnızca String.fromEnvironment, fallback literal YOK
lib/models/      Asset (+AssetKind), Position, AssetType, kategori enum'ları, sinyal/alarm modelleri
lib/providers/   auth, portfolio, preferences (_BoolPrefNotifier/_IntPrefNotifier deseni),
                 watchlist, signal, bulk_cart
lib/screens/     Sekmeler: home, portfolio ("Portföy" sekmesi), portfolio_performance ("Performans"),
                 profile; tekil varlık: asset_detail_screen; ekleme: add_asset, bulk_add.
                 portfolio_performance/ ve asset_detail/ = o ekranların `part` dosyaları
                 (aynı kütüphane; State üyeleri `extension` + `_guncelle`). Yeni kod ilgili
                 part'a gider, hub dosyasına değil.
lib/services/    supabase_service (DB geçidi), price_service/tefas_service (fiyat), history_service
                 (seri motoru), period_summary/recap/daily_summary, notification/remote_push,
                 home_widget/live_activity, leaderboard, inflation, analytics, db_logger
lib/l10n/        app_tr.arb / app_en.arb, l10n.dart (context.l10n), generated/ (gen-l10n çıktısı)
lib/theme/       sandik.dart — context.c (renk), context.t (tipografi), SandikSpace/Radius/Motion,
                 adaptiveRoute, SandikCard, SandikSectionHeader
lib/utils/       tr_format (fmtTRY/fmtPct/parseTrNumber), friendly_error, grafik yardımcıları
lib/widgets/     zoomable_chart (+ZoomDataController), percent_comparison_chart, sparkline, şeritler
test/            155+ dosya; parite/değişmez testleri (chart_interaction_parity, design_token_leak,
                 spacing_scale, touch_target_size, reduce_motion_coverage…) kasıtlı ratchet'lerdir.
                 Kaynak tarayan test ekran dosyasını `helpers/kaynak.dart` (`ekranKaynagiSync`)
                 ile okur — part'lar dahil; ham `File(...).readAsStringSync()` kullanma.
integration_test/ smoke_test.dart — gerçek uygulama + yerel Supabase (3.16); CI: integration.yml
supabase/        migrations/ (tek şema kaynağı; 0000 taban şema), functions/ (+_shared/cron_auth.ts,
                 fcm.ts), tests/ (Deno), audit/, config.toml + seed.sql (yerel yığın / CI)
```

Adlar sekmelerle örtüşür (2026-09 yeniden adlandırması): "Portföy" sekmesi
`PortfolioScreen`, "Performans" sekmesi `PortfolioPerformanceScreen`, tekil varlık ekranı
`AssetDetailScreen`. Eski adlar `ChartsScreen` / `PerformanceScreen` idi; arşiv dokümanlarda
o adlarla geçer.

## Kurallar

**Tasarım sistemi.** Renk yalnızca `context.c.*`, tipografi `context.t.*`, boşluk
`SandikSpace`, köşe `SandikRadius`, animasyon `SandikMotion.of(context)`. Ham `Colors.*`,
`Color(0x…)`, `fontSize:`, `Duration(milliseconds:)` ekleme — `design_token_leak_test` ve
`spacing_scale_test` sayıları **yalnızca azalabilir**. Kart için `SandikCard`, bölüm başlığı
için `SandikSectionHeader`; yeni `_SectionTitle` klonu yazma.

**Para ve tarih.** Tutar `fmtTRY`, yüzde `fmtPct`, kullanıcı girdisi `parseTrNumber`
(`lib/utils/tr_format.dart`). `NumberFormat.currency(locale:'tr_TR')` ve `toStringAsFixed`
UI kodunda kullanılmaz.

**Hata gösterimi.** Kullanıcıya ham `$e` / `e.toString()` gösterme; `friendlyError(e)` /
`showAppError` / `SandikErrorView`. Servis katmanı catch'leri sessiz kalmasın —
Crashlytics'e non-fatal bildir.

**Navigasyon.** `Navigator.push` yerine `adaptiveRoute` (iOS geçişi) ve `pushGuarded`
(çift dokunma koruması). `MaterialPageRoute` doğrudan kullanılmaz.

**Katmanlama.** `lib/screens` ve `lib/widgets` içinde `http` ve `Supabase.instance` yok;
veri erişimi `SupabaseService` / provider'lar üzerinden. Hesaplama `build()` içinde değil,
model/servis katmanında.

**Fiyat kaynağı.** *"Tüm varlıklar her yerde tek kaynaktan ve tutarlı şekilde
çekilmelidir"* (kullanıcı kararı 2026-09-17). Sözleşme `lib/services/fiyat_kaynagi.dart`:
(1) bir varlığın hangi seriden besleneceğine **yalnızca orası** karar verir —
yeni yüzey (widget, sparkline, rapor) kendi sembol merdivenini kurmaz;
(2) ekranda görünen fiyat ile serinin **ölçeği** aynı olmalı — farklı sağlayıcı varsa
seri canlı kotasyona hizalanır (`kurSerisiniHizala`, `altinKalibrasyonHaritasi`);
(3) **uydurma sayı yasak** — kur/fiyat bilinmiyorsa nokta seriye girmez,
`35.0`/`40.0` gibi sabit yazılmaz. `fiyat_kaynagi_sozlesmesi_test` üçünü de tarar.

**Kapanmış pozisyon.** Bugünkü mülkiyeti soran yerler `aktifLotlar(...)` kullanır; geçmişi
soran yerler (hareket listesi, `HistoryService`, dönem hesapları) ham defteri kullanmaya
**devam eder** (`TECHNICAL_DEBT.md` "Net miktarı 0'a düşmüş varlık").

**Sunucu.** Şema kaynağı `supabase/migrations/` (kök `supabase_schema.sql` yalnızca nottur).
Her `SECURITY DEFINER` fonksiyonunda `SET search_path`. GRANT ve RLS ayrı şeylerdir; yeni
RPC'de ikisini de yaz, eksikse `raise exception` ile doğrula (0036/0042/0043 örnek). Cron
edge function'ları `requireCronSecret()` ile **fail-closed**; secret'sız `if (secret)` bloğu
yazma. Edge function yanıtlarında `error.message`/token/ham FCM yanıtı **dönme**.

**Gizli anahtar.** Repoya asla: `google-services.json`, `GoogleService-Info.plist`,
`key.properties`, keystore, Vault değerleri, `.env`. `tmp/` gitignore'dadır ve öyle kalır.

**i18n.** Ana dil Türkçe, hitap **sen**. 3.20 (2026-09-14): `lib/l10n/app_tr.arb` (şablon) +
`app_en.arb`, `flutter gen-l10n` → `lib/l10n/generated/` (commit'li), erişim `context.l10n.anahtar`
(`lib/l10n/l10n.dart`; delegate yoksa Türkçe'ye düşer). Çevrilmiş ekranlarda (liste
`test/l10n_coverage_test.dart`) yeni metin **ham literal olarak eklenmez**: iki .arb'a anahtar
+ gen-l10n + `context.l10n`. Henüz çevrilmemiş ekranlarda Türkçe literal serbest; İngilizce
BETA, varsayılan dil Türkçe (`LocaleNotifier`).

**Yenilikler / tanıtım.** "Bunu tanıtımda da gösterelim", "kullanıcı bunu
görsün", "sürüm notuna ekle" dendiğinde **üç ayak birden** yapılır — biri
eksikse özellik sessizce görünmez:

1. **Sürüm notu** → `lib/config/surum_notlari.dart`, listenin BAŞINA.
   `surum` alanına **yayınlanacak** sürümü yaz (pubspec'i **elle bump etme**,
   fastlane CI'da yapar). Eşleşmezse not hiç gösterilmez — sessiz arıza.
   Ana yüzey değişiyorsa `onemli: true` (otomatik açılır), yama ise `false`
   (yalnızca Ayarlar'da).
2. **Tanıtım turu** → ana yüzeylerden birini değiştiriyorsa
   `onboarding_screen.dart` → `_adimlariKur()` içine adım ekle
   (`rozet: 'YENİ'`). Tur uygulamanın GÜNCEL hâlini anlatmalı.
3. **Yeni `TourTarget` eklediysen** onu bir ekranda `TourAnchor` ile
   işaretle — `onboarding_tour_test` işaretlenmemiş hedefi kırar.

Gösterim kararı `SurumNotuService.yeniNotlar` saf fonksiyonundadır
(`test/surum_notu_test.dart`): ilk kurulumda gösterilmez, aynı sürüm ikinci
kez gösterilmez, atlanan sürümler birikir, notu yazılmamış sürümde susar.
Bu kuralları değiştirirken testi de güncelle.

## Doğrulama

Feature/bugfix turunda:
```bash
flutter analyze lib/ test/
flutter test test/<o turda yazılan veya etkilenen>_test.dart
```
Testler yine **yazılır**; tam paket her turda koşulmaz. CI (`.github/workflows/ci.yml`)
PR'da ve `main`'de tam paketi + `deno check`/`deno test` koşar; `integration.yml` yerel
Supabase yığınını (`supabase start`: 0000 + tüm migration'lar + `seed.sql`) kaldırıp
`tool/supabase_smoke.sh` ve Android emülatöründe `integration_test/` koşar. Yeni migration
taze yığında kırılırsa orada görünür.

Push / commit öncesi, kullanıcı görsel doğrulama istediğinde ya da bir dizi değişikliğin
sonunda tam paket + emülatör dağıtımı:
```bash
bash tool/deploy_emulators.sh        # analyze → test → build → install → başlat → çökme kontrolü
```
Betik herhangi bir adımda kırılırsa durur; kırık APK emülatöre gitmez.

Teknik borç: ertelenen **kod** kararı `TECHNICAL_DEBT.md`'ye (neden, maliyet, ne zaman);
kapanınca commit hash'iyle "KAPANDI" tablosuna. Kullanıcının elden yapacağı işler
`YAPMAN_GEREKENLER.md`'ye.

## Yerel makine notları (yalnızca geliştiricinin Windows makinesi)

Bu bölüm tek bir geliştirme makinesini tarif eder; başka ortamda (CI, Claude Code web,
başka bilgisayar) **geçerli değildir** ve buradaki yollar bulunamazsa bu bir hata değildir.

- flutter: `/c/flutter/bin/flutter` (PATH'te yok, Bash ile çağır)
- adb: `C:\Users\vasin\Android\sdk\platform-tools\adb.exe`
- ffmpeg: PATH'te **yok**. Tam sürüm `store_listing/preview_video/brag-output/composition/tools/`
  (ffmpeg-static). `@remotion/compositor`'ın ffmpeg'i kısıtlı build — filtergraph ve
  `silenceremove` çalışmaz, Hyperframes onunla render edemez. Git Bash'te `scale=886:1920`
  gibi `:`'li argümanlar MSYS yol dönüşümüne takılır; ffmpeg'i Python `subprocess` ile çağır.
- Emülatörler: `pixel7_1` (emulator-5554) ve `pixel7_2` (emulator-5556); kapalıysa
  `flutter emulators --launch pixel7_1` / `pixel7_2`. `hw.keyboard = yes` (2026-05-09).
- ⚠️ Bu emülatörler Flutter'ı **render edemiyor** (ekran görüntüsü siyah; süreç yaşıyor,
  FATAL yok — doğrulandı 2026-08-09). Betik "çalışıyor mu"yu yanıtlar, "doğru görünüyor mu"yu
  değil. Görsel doğrulama gerçek cihazda veya widget testiyle.
- ⚠️ Disk: debug APK ~215 MB, kurulum iki katını ister. `INSTALL_FAILED_INSUFFICIENT_STORAGE`
  gelirse AVD'yi sıfırla:
  ```bash
  adb -s emulator-5556 emu kill
  "C:/Users/vasin/Android/sdk/emulator/emulator.exe" -avd pixel7_2 -wipe-data
  ```

### MCP sunucuları (`.mcp.json`, proje kapsamlı)
Bu makinede üç sunucu bağlıdır; başka ortamda bağlanamazlar ve bu beklenen durumdur —
kod keşfi `Grep`/`Glob`/`Read` ile yapılır.

- **codebase-memory-mcp** (v0.9.0, `C:\Users\vasin\AppData\Local\Programs\codebase-memory-mcp\…exe`,
  graph adı `C-projects-PortfoyTakip`). Kod keşfinde önce graph (`search_graph`, `query_graph`,
  `trace_path`, `get_architecture`), sonra geniş grep. Mimari kararlar `manage_adr`'de.
  Büyük değişiklik sonrası: `codebase-memory-mcp cli index_repository --repo-path "c:\projects\PortfoyTakip"`.
  ⚠️ `index_repository` ADR'yi siler — önce indeksle, ADR'yi sonra yaz. Ham JSON argümanı
  deprecated; flag kullan (`--repo-path`, `--project`, `--mode`; uzun içerik `--args-file`).
- **ui-ux-pro-mcp** (npm global). Yeni ekran/komponent tasarlarken `search_ui`,
  `get_platform_guidelines` sorgula; yerleşim/hiyerarşi önerilerini al, **renk paletini alma** —
  sandık amber/gold/gain/loss/surface + DM Sans korunur.
- **dart** (`dart mcp-server --force-roots-fallback`; bayrağı kaldırma). Analiz/test/pub
  için ham kabuk çıktısı yerine bu sunucunun yapılandırılmış sonuçlarını tercih et.

Oturum başı denetim: `.claude/settings.local.json` `SessionStart` hook'u `tool/mcp_health.sh`
koşar (çalıştırılabilir yerinde mi, indeks son commit'ten geride mi). Betik sunucu
**başlatmaz**; ikinci kopya codebase-memory'nin SQLite kilidiyle çakışır. `.claude/`
gitignore'da olduğundan hook bu makineye özgüdür; betik commit'lidir.

---
**Son güncelleme:** 2026-09-17 (brag/Hyperframes satırı + ffmpeg notu; 2026-09-15: Yenilikler/tanıtım kuralı eklendi; 2026-09-14: vadeli mevduat
kaldırıldı, Apple/Google giriş eklendi; sqflite/Provider/emülatör-ilk-kurulum bölümleri kaldırıldı).
