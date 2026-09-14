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
                 profile; tekil varlık: asset_detail_screen; ekleme: add_asset, bulk_add, add_deposit
lib/services/    supabase_service (DB geçidi), price_service/tefas_service (fiyat), history_service
                 (seri motoru), period_summary/recap/daily_summary, notification/remote_push,
                 home_widget/live_activity, leaderboard, inflation, analytics, db_logger
lib/theme/       sandik.dart — context.c (renk), context.t (tipografi), SandikSpace/Radius/Motion,
                 adaptiveRoute, SandikCard, SandikSectionHeader
lib/utils/       tr_format (fmtTRY/fmtPct/parseTrNumber), friendly_error, grafik yardımcıları
lib/widgets/     zoomable_chart (+ZoomDataController), percent_comparison_chart, sparkline, şeritler
test/            155 dosya; parite/değişmez testleri (chart_interaction_parity, design_token_leak,
                 spacing_scale, touch_target_size, reduce_motion_coverage…) kasıtlı ratchet'lerdir
supabase/        migrations/ (tek şema kaynağı), functions/ (+_shared/cron_auth.ts, fcm.ts),
                 tests/ (Deno), audit/
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

**i18n.** Arayüz Türkçe; `en_US` `supportedLocales`'ta ilan edilmiş ama `.arb` yok.
Yeni metin Türkçe, hitap **sen**.

## Doğrulama

Feature/bugfix turunda:
```bash
flutter analyze lib/ test/
flutter test test/<o turda yazılan veya etkilenen>_test.dart
```
Testler yine **yazılır**; tam paket her turda koşulmaz. CI (`.github/workflows/ci.yml`)
PR'da ve `main`'de tam paketi + `deno check`/`deno test` koşar.

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
**Son güncelleme:** 2026-09-14 (vadeli mevduat kaldırıldı, Apple/Google giriş eklendi; sqflite/Provider/
emülatör-ilk-kurulum bölümleri kaldırıldı).
