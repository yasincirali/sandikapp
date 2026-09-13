# Yol Haritası İlerleme Defteri

Kaynak plan: `DEGERLENDIRME_VE_YOL_HARITASI_2026_09.md` §8.
Bu dosya her adımda güncellenir; **son kalınan yer** en üstte.

> ✅ Flutter 3.47.2 bu oturumda `/opt/flutter-sdk` altına kuruldu (2026-09-13,
> Faz 1 sonunda). O andan itibaren her commit öncesi `flutter analyze lib/ test/`
> ve tam `flutter test` koşuldu. Faz 0–1 değişikliklerinin tümü doğrulandı:
> analyzer 0 sorun, 1.665+ test geçiyor. `deno` hâlâ yok — edge function
> değişiklikleri yalnızca okunarak incelendi; `ci.yml` deno job'ı ilk PR'da
> gerçek sonucu verecek.

## Son kalınan yer
Faz 0 ve Faz 1 tamam. Faz 2: 2.1, 2.2, 2.3, 2.4(kısmi), 2.6(kısmi), 2.7, 2.8, 2.9, 2.13(kısmi) tamam.
**Kalan Faz 2 kalemleri** (görsel doğrulama isteyen, cihazsız yapılmaması daha doğru):
2.5 tek SandikAppBar, 2.10 varlık silmede undo (sunucu tarafı kalıcı silme — soft-delete ister),
2.11 grafik etkileşim paritesi, 2.12 SegmentedButton geçişi, 2.14 Hero geçişi, 2.13'ün
`Size.zero` buton kısmı (20 site), 2.6'nın `en_US` kaldırma + emoji/başlık kasası taraması.
Sıradaki: bunlardan biri ya da Faz 3.

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
| 1.7 | ✅ (auth kapsamı) | `lib/services/crash_reporter.dart`: `CrashReporter.report(e, st, reason:)` — sanitize + non-fatal + Firebase yoksa no-op. `auth_service`'teki 7 jenerik `catch (e)` buna bağlandı ve kullanıcı mesajı `friendlyError(e)` üzerinden. `remote_push_service` breadcrumb'ında tam UUID yerine ilk 8 karakter (M6). Diğer servislerdeki bilinçli `catch (_)` blokları (yorum gerekçeli) dokunulmadı. |
| 1.8 | ✅ (kısmi) | Kayıt hatası artık hesap varlığını doğrulamıyor (M4). Şifre sıfırlama OTP'sinde 6 hane kontrolü. **Login/OTP sunucu tarafı throttle (M12) yapılmadı**: istemci sayacı güvenlik sınırı değil (S1 dersi); doğru yer GoTrue rate limit ayarları — `YAPMAN_GEREKENLER.md` #10. |
| 1.9 | 🟡 kısmi | `flutter_launcher_icons` → `dev_dependencies`. **Ertelendi:** `google_fonts` kaldırma (35 kullanım + `bundled_font_test` google_fonts API'sine bağlı) ve `flutter_lints` 4→6 + strict — ikisi de analyzer koşmadan güvenli değil; `TECHNICAL_DEBT.md`'ye yazıldı. |
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
| 2.5 | ⏳ | |
| 2.6 | 🟡 kısmi | Onay dialogları ve 4 UI metni `sen` kipine çekildi. Yasal metinler (`legal_doc_screen`, `disclaimer_service`) bilinçli `siz`. `en_US` kaldırma ve emoji/başlık kasası taraması bekliyor. |
| 2.7 | ✅ | (1) OTP doğrulaması sonrası sorumluluk reddi kaydı otomatik düşülüyor — kayıt ekranındaki 'Yasal Koşullar' onayı zaten disclaimer'ı içeriyordu; `DisclaimerAcceptanceScreen` artık yalnızca eski/kaydı olmayan hesaplara çıkar. (2) **'Belgeyi açıp sonuna kadar kaydır' kapısı kaldırıldı** — kutu doğrudan işaretlenir, belge bağlantısı bir dokunuş uzakta. ⚠️ Hukuki tarafta bilinçli karar: KVKK açık rıza 'bilgilendirilmiş' olmayı ister, 'sonuna kadar kaydırılmış' olmayı değil; itiraz edersen `_LegalConsentBox.onTap` tek satırla eski davranışa döner. (3) Turda 'Atla' zaten vardı; Ayarlar → Destek'e 'Tanıtım turunu yeniden izle' eklendi. |
| 2.8 | ✅ (boş durum) | Ana ekranda kendi görünümü + sıfır varlık = `_EmptyPortfolioCta` özetin hemen altında; şeritler, kişi kartları, filtre çipleri ve iki boş başlık gizli. Tür filtresi boşken aynı bileşen 'Bu türde varlık yok' diliyle. **3 şeridi tek yatay karta toplama yapılmadı** — şeritler zaten kendi kendini gizliyor; dolu portföyde katlama üstü sorunu ölçülmeden yeniden düzenlemek erken. |
| 2.9 | ✅ (adlar) | `charts_screen.dart`/`ChartsScreen` → `portfolio_screen.dart`/`PortfolioScreen`; `performance_screen.dart`/`PerformanceScreen` → `asset_detail_screen.dart`/`AssetDetailScreen`. 73 dosya (lib, test kaynak-metin yolları, CLAUDE.md, TECHNICAL_DEBT.md) tek geçişte; arşiv dokümanlar eski adla kaldı. **Geri tuşu sekme geçmişi ve predictive back yapılmadı** — `PopScope(canPop:false)` çıkış onayıyla iç içe; ayrı bir tasarım kararı. |
| 2.10 | ⏳ | |
| 2.11 | ⏳ | |
| 2.12 | ⏳ | |
| 2.13 | 🟡 kısmi | `ZoomableChart.semanticLabel` (varsayılan 'Fiyat grafiği'; `PercentComparisonChart` seri sayısı + gün ile dolduruyor, takip grafiği ondan miras alıyor). Sparkline dekoratif olarak bilinçli sessiz (kaynakta gerekçeli). **Yapılmadı:** 20 `minimumSize: Size.zero` butonun 44pt'ye çıkarılması; settings/add_asset Semantics; kompakt yüzeylerde ok glifi. |
| 2.14 | ⏳ | |

## Faz 3 — Ürün ve mimari
(henüz başlanmadı)
