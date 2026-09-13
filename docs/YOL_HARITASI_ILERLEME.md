# Yol Haritası İlerleme Defteri

Kaynak plan: `DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §8.
Bu dosya her adımda güncellenir; **son kalınan yer** en üstte.

> ⚠️ Bu ortamda `flutter`/`dart`/`deno` YOK. Dart değişiklikleri analiz
> edilmeden commit'lendi; ilk `flutter analyze` + `flutter test` koşusu
> (yeni `ci.yml` PR'da otomatik) kırık bir şey bulursa önce onu düzelt.
> Değişiklikler bilinçli olarak küçük ve mekanik tutuldu.

## Son kalınan yer
Faz 0 tamam, Faz 1.1–1.6 ve 1.12 tamam. Sıradaki: **Faz 1.7** (Crashlytics non-fatal).

## Faz 0 — Kanamayı durdur

| # | Durum | Not |
|---|---|---|
| 0.1 | 🟡 Kod tarafı yapıldı | `tmp/` git'ten silindi, `.gitignore`'a eklendi. **Secret rotasyonu ve geçmiş temizliği SENDE** (`YAPMAN_GEREKENLER.md` en üst tablo #1-2). |
| 0.2 | ✅ | `push-live-activity`: `requireCronSecret(LIVE_ACTIVITY_CRON_SECRET)`, `userId` kâhini kaldırıldı, hata mesajı sabit koda çevrildi. Deploy + secret sende (#3, #6). |
| 0.3 | ✅ | `_shared/cron_auth.ts` (fail-closed, sabit zamanlı karşılaştırma). 6 fonksiyon buna bağlandı. Secret doğrulaması sende (#4). |
| 0.4 | ✅ | `send-partner-invite-push` yanıtı `{ok, delivered}`; ham hata echo'su kaldırıldı. İstemci `results` okumuyordu — kırılma yok. |
| 0.5 | ✅ | `build.gradle.kts`: `key.properties` yoksa `GradleException`. |
| 0.6 | ✅ | `supabase_reset.sql` silindi; `supabase_schema.sql` migrations'a işaret eden nota indirildi. |
| 0.7 | ✅ | `delete-account`: `DELETION_HASH_SALT` varsayılanı kaldırıldı (yoksa 503), `detail` echo'su kaldırıldı. Secret set etme sende (#5). |
| 0.8 | ✅ | `main_navigation_screen.dart`: çıkış onayı `SystemNavigator.pop()`. |
| 0.9 | ✅ | `.github/workflows/ci.yml`: PR + main'de `flutter analyze` + `flutter test`; ayrı job'da `deno check` + `deno test`. **İlk koşuda kırılabilir** — özellikle deno job'ı (testlerin izin gereksinimi `--allow-all` ile geçildi, `deno check` importları çözemezse job'ı gevşet). |
| 0.10 | ✅ | `SupabaseService.isPushAdmin()` + `isPushAdminProvider` + Ayarlar tile'ı yalnızca admin'e; "GELİŞTİRİCİ" → "TANILAMA"; `adaptiveRoute`. Debug "Test Crash" tile'ı admin'den bağımsız ayrı bloğa alındı. Migration `0054` GRANT — koşulması sende (#7). |

## Faz 1 — Temizlik ve tutarlılık altyapısı

| # | Durum | Not |
|---|---|---|
| 1.1 | ✅ (kısmi) | Silindi: `asset_detail_screen.dart`, `portfolio_detail_screen.dart`, `premium_gate.dart`, `PortfoyTakip.xcodeproj/`, `assets/images/sandik_original_circle.png` + `splash_icon.png` (Android kendi drawable kopyasını kullanıyor). `tools/` → `tool/` birleşti. `chart_interaction_parity_test` listesi güncellendi. **Bilerek bırakıldı:** `bar_interval_selector.dart` (kullanıcının son commit'i, bağlanması bekleniyor), `chart_downsample`/`series_downsample` (`TECHNICAL_DEBT.md` "ERTELENDİ" kaydı var), `store_listing/screenshots/orig+raw` (`build_screenshots.py` raw/ okuyor). |
| 1.2 | ✅ | 17 kök doküman → `docs/archive/` ("ARŞİV" başlığıyla), çapraz bağlantılar düzeltildi. `README.md` dizin oldu. `CLAUDE.md` yeniden yazıldı: sqflite/Provider/emülatör-ilk-kurulum kaldırıldı, kurallar (tasarım sistemi, para/tarih, hata, navigasyon, katmanlama, sunucu, gizli anahtar) tek yerde, Windows yolları "yerel makine notları" bölümünde. |
| 1.3 | ✅ | `lib/utils/sandik_snack.dart`: `sandikSnack(kind: neutral/success/warning/error, onUndo, action)` + `sandikSnackError` (friendlyError zorunlu). 30 `showSnackBar` sitesi + 12 ham `$e`/`e.toString()` sitesi geçirildi (profil, toplu ekleme, mevduat, temettü, hızlı işlem, ortaklık istekleri, alarm). Push teşhisi ham hatayı bilinçli koruyor (admin aracı). `test/sandik_snack_test.dart`: ham hata sızmaz, undo çalışır, kuyruk birikmez, `showSnackBar` yalnızca yardımcıda (ratchet). L7 şifre metni 8+harf+rakam ile hizalandı. Nav bar inset eklenmedi: dış Scaffold `extendBody` kullanmıyor, sekme Scaffold'u nav bar'ın üstünde bitiyor. |
| 1.4 | ✅ | `tr_format.dart`: `tryFormatter(digits, symbol)`, `qtyFormatter`, `fixedFormatter`, `dayKey`. 20 `NumberFormat.currency` + 13 `NumberFormat('#…')` kopyası bunlara bağlandı (ondalık sayısı çağıranda kaldı, locale/sembol tek yerde). 38 `DateTime(y,m,d)` → `dayKey`. 17 `toStringAsFixed` → `fmtNum` (leaderboard `12.5%` → `12,5%` TR ayracı düzeldi); kalan 5'i eksen sözleşmeli, bilinçli. `context.signColor(v)` eklendi, 5 satır içi kazanç/kayıp üçlüsü buna geçti. `test/tr_format_single_source_test.dart` ratchet. Kullanılmayan `intl` importları temizlendi. |
| 1.5 | ✅ | `lib/config/pref_keys.dart` (`PrefKeys`): 18 `pref_*` anahtarı tek yerde; `preferences_provider`, `notification_service`, `surface_theme` buna bağlandı. `test/pref_keys_single_source_test.dart`: literal PrefKeys dışında yazılamaz + benzersizlik. `sandik_*` (widget IPC) ve `retention_*` bilinçli kapsam dışı. |
| 1.6 | ✅ (silme ile) | `Asset.toMap()/fromMap()` lib+test'te SIFIR çağıran — "partner kod payload" yorumu bayattı. Alan paritesi kurmak yerine ölü çift SİLİNDİ; tek serileştirme şeması `toSupabase/fromSupabase`. |
| 1.7 | ⏳ | |
| 1.8 | ⏳ | |
| 1.9 | ⏳ | |
| 1.10 | ⏳ | |
| 1.11 | ⏳ | |
| 1.12 | ✅ | `FxRateMigrationService.runFor` kullanıcı başına günde bir kez (`PrefKeys.fxMigrationLastRunMs_<uid>`); yeniden deneme davranışı korunuyor. |

## Faz 2 — UX tutarlılığı ve modern UI
(henüz başlanmadı)

## Faz 3 — Ürün ve mimari
(henüz başlanmadı)
