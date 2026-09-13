# Yol Haritası İlerleme Defteri

Kaynak plan: `DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §8.
Bu dosya her adımda güncellenir; **son kalınan yer** en üstte.

> ⚠️ Bu ortamda `flutter`/`dart`/`deno` YOK. Dart değişiklikleri analiz
> edilmeden commit'lendi; ilk `flutter analyze` + `flutter test` koşusu
> (yeni `ci.yml` PR'da otomatik) kırık bir şey bulursa önce onu düzelt.
> Değişiklikler bilinçli olarak küçük ve mekanik tutuldu.

## Son kalınan yer
**Faz 0 tamam** (kod tarafı). Sıradaki: Faz 1.1 (ölü kod silme).

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
(henüz başlanmadı)

## Faz 2 — UX tutarlılığı ve modern UI
(henüz başlanmadı)

## Faz 3 — Ürün ve mimari
(henüz başlanmadı)
