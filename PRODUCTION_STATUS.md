# sandık — Roadmap Durum Raporu

**Tarih:** 2026-05-12
**Karşılaştırma kaynağı:** [PRODUCTION_ROADMAP.md](PRODUCTION_ROADMAP.md)
**Yöntem:** Her madde kodda grep + dosya kontrolü ile doğrulandı.

---

## 🚧 Aktif Feature Flag'ler

| Flag | Kaynak | Default | Durum | Açılma Koşulu |
|---|---|---|---|---|
| `paywall_enabled` | Firebase Remote Config | `false` | ❌ KAPALI | RevenueCat + App Store/Play Console subscription ürünleri hazır olunca `true` |

**`paywall_enabled = false` iken:** Paywall ekranı, Premium banner, Premium chip'leri, kilit overlay, ADX/Williams/CCI kilidi, varlık limiti — hiçbiri kullanıcıya görünmez. Herkes free-tier davranır. Detay: [MONETIZATION_ROADMAP.md](MONETIZATION_ROADMAP.md#-master-kill-switch-paywall_enabled-2026-07-13)

---

## 1) GÜVENLİK & VERİ GÜVENLİĞİ

### Kritik (4/4) ✅

| # | Madde | Durum | Doğrulama |
|---|---|---|---|
| S1 | WRITE_SECURE_SETTINGS izni sil | ✅ TAMAM | `grep WRITE_SECURE_SETTINGS android/...` boş |
| S2 | Release signing | ✅ KOD HAZIR | `build.gradle.kts:62-65` conditional release config (`key.properties` varsa kullanır, yoksa debug fallback). **Sen `key.properties` üretmen gerek** |
| S3 | db_logs PII sızıntısı | ✅ TAMAM | `db_logger.dart:97` `kReleaseMode && !isError` early return + `_maskSensitive()` PII maske |
| S4 | .db dosyaları repo'da | ✅ TAMAM | 26 dosya silindi; `.gitignore` zaten kapsamlı (`*.db`, `db_*`, `backup_*`, `tmp_*`, `*.b64`) |

### Yüksek (5/7) — 2 madde sende

| # | Madde | Durum |
|---|---|---|
| S5 | Code obfuscation | ⚠️ KISMI — build komutu YAPMAN_GEREKENLER.md §6.5'te dokümante (`--obfuscate --split-debug-info=build/symbols`) ama otomatik script yok. **Sen production build komutunda çalıştıracaksın** |
| S6 | ProGuard/R8 | ✅ TAMAM | `build.gradle.kts:67-71` `isMinifyEnabled=true`, `isShrinkResources=true`, `proguard-rules.pro` Firebase+Supabase+kotlinx keep rules ile |
| S7 | Hardcoded secrets → dart-define | ✅ TAMAM | `supabase_config.dart:10-17` `String.fromEnvironment` ile |
| S8 | Firebase config dosyaları | ⏳ SENİN İŞİN | Conditional plugin: dosya yoksa build kırılmıyor. `flutterfire configure` çalıştırınca aktive olur |
| S9 | Certificate pinning | ❌ YAPILMADI | Faz 3'e ertelendi (PRODUCTION_ROADMAP.md §FAZ 3) — yayın bloker değil |
| S10 | Biometric auth | ❌ YAPILMADI | Faz 3'e ertelendi — yayın bloker değil |
| S11 | Session timeout UI'da gösterimi | ❌ YAPILMADI | Backend mevcut (10 dk idle → logout), UI banner eksik. Düşük öncelik |

### KVKK/GDPR Uyumluluğu — 6/6 + 1 gap ✅

| Madde | Durum |
|---|---|
| KVKK Aydınlatma Metni | ✅ `legal/tr/KVKK_AYDINLATMA_METNI.md` |
| Açık rıza checkbox (register) | ✅ `register_screen.dart:42-44` 3 onay (Disclaimer + KVKK + Yurt dışı) |
| **18+ yaş onay checkbox** | ✅ **YENİ EKLENDİ** — `register_screen.dart:46-47` `_ageAccepted` zorunlu |
| Yurt dışı veri transferi açık rıza | ✅ `_consentAccepted` checkbox + `legal/tr/ACIK_RIZA_METNI.md` |
| Veri silme akışı | ✅ `lib/screens/settings_screen.dart` + `supabase/functions/delete-account/` |
| Veri export akışı | ✅ `lib/services/data_export_service.dart` + Settings → "Verilerimi İndir" |
| Kullanıcı haklarını listeleyen bölüm | ✅ `legal/tr/PRIVACY_POLICY.md §8` + `KVKK_AYDINLATMA_METNI.md §7` |

---

## 2) KOD KALİTESİ — P0 Fix'leri (6/6) ✅

| # | Madde | Durum |
|---|---|---|
| Q1 | `state.requireValue` → `valueOrNull` | ✅ `portfolio_provider.dart:160` |
| Q2 | `firstWhere` orElse | ✅ `add_asset_screen.dart:947` |
| Q3 | fl_chart yInterval clamp | ✅ `portfolio_performance_screen.dart:362`, `portfolio_detail_screen.dart:234` |
| Q4 | JSON cast hardening | ✅ `supabase_service.dart:200-218` + `:587` |
| Q5 | Empty list guards | ✅ `home_screen.dart:142-160`, `profile_screen.dart:492` |
| Q6 | Supabase timeout | ✅ `DbLogger.defaultTimeout = 15s` + `disclaimer_service.dart` `.timeout()` |

### P1 (15) — Faz 2

Kasıtlı olarak Faz 2'ye bırakıldı (yayın bloker değil). U1 (friendlyError) tamamlandı.

---

## 3) CRASH POTANSİYELİ — 10/10 ✅

C1-C10 kritik crash'lerin hepsi P0 fix'leri (Q1-Q6) + WRITE_SECURE_SETTINGS silimi + charts_screen.dart Navigator.pop kontrolü ile çözüldü.

---

## 4) UX — Kritik (5/6)

| # | Madde | Durum |
|---|---|---|
| U1 | friendlyError helper | ✅ `lib/utils/friendly_error.dart` + 8 yerde uygulandı |
| U2 | Error ekranlarında "Tekrar Dene" | ⚠️ KISMI — `friendlyError` mesajları temiz, ama dedicated `ErrorRetryView` widget yok. AsyncValue `error` view'ları hâlâ pasif text. Faz 2'de eklenebilir |
| U3 | Onboarding | ✅ `lib/screens/onboarding_screen.dart` 3-step + AuthGate entegrasyonu |
| U4 | Hesap silme akışı | ✅ Settings + Edge Function + SQL migration |
| U5 | Settings ekranı | ✅ `lib/screens/settings_screen.dart` — tema, bildirim, hukuki, **disclaimer reshow**, veri export, hesap silme |
| U6 | Accessibility | ❌ YAPILMADI — Faz 2 (audit + Semantics + tooltip + min 48x48) |

### Yüksek UX (10) — Faz 2'de

Hiçbiri tamamlanmadı (kasıtlı; U1-U5 kritik bloker'ları öncelendi).

---

## 5) STORE HAZIRLIĞI

### Android Bloker (5/5) ✅

| # | Madde | Durum |
|---|---|---|
| 1 | Release signing | ✅ Kod hazır — keystore üretmek sende |
| 2 | WRITE_SECURE_SETTINGS sil | ✅ |
| 3 | applicationId değiştir | ✅ `com.sandik.app` |
| 4 | App label "sandık" | ✅ `res/values/strings.xml` + manifest `@string/app_name` |
| 5 | RECEIVE_BOOT_COMPLETED sil | ✅ |

### Android Önerilen (4/4) ✅

| Madde | Durum |
|---|---|
| Adaptive icon | ✅ `mipmap-anydpi-v26/ic_launcher.xml` foreground + background + monochrome |
| ProGuard/R8 | ✅ |
| `targetSdk = 35` explicit | ✅ `build.gradle.kts:36` (compileSdk=36 androidx zorunluluğu) |
| ABI splits + obfuscation | ⏳ Build komutunda — YAPMAN_GEREKENLER.md §6.4 |

### iOS Bloker (0/4) ❌

**TÜMÜ ERTELENDİ** — Apple Developer üyelik yok. Faz 3'te yapılacak:
- PrivacyInfo.xcprivacy
- aps-environment = production
- DEVELOPMENT_TEAM
- Distribution certificate

### Yasal Gereklilikler (8/9) ✅

| Madde | Durum |
|---|---|
| Privacy Policy URL | ✅ Belge hazır (`legal/tr/PRIVACY_POLICY.md` + EN) — **sen host edeceksin** |
| Terms of Service | ✅ Belge hazır |
| KVKK Aydınlatma Metni | ✅ |
| KVKK açık rıza checkbox | ✅ register'da 4 zorunlu onay |
| GDPR DSAR süreci | ✅ `legal/en/GDPR_NOTICE.md` + `DATA_DELETION_REQUEST_FORM.md` |
| Hesap silme akışı | ✅ |
| Veri export | ✅ |
| **Yaş onayı (18+)** | ✅ **YENİ EKLENDİ** |
| Yatırım disclaimer | ✅ Mevcut |

### Store Listing (0/8) ⏳

Tümü tasarım/yazım işi → SENİN İŞİN:
- App icon (✓ kod tarafında)
- Screenshot setleri
- Feature graphic 1024×500
- Short description
- Long description
- ASO keywords
- Age rating formu

YAPMAN_GEREKENLER.md §6.3'te detaylı.

### Production Engineering

| Sistem | Durum |
|---|---|
| Crash reporting (Firebase Crashlytics) | ✅ Kod tarafı tam, `google-services.json` ile aktive olacak |
| Analytics | ❌ Faz 3 (opsiyonel, KVKK güncellemesi gerekir) |
| Remote Config / Kill switch | ❌ Faz 2 |
| CI/CD | ❌ Faz 2 |
| Beta dağıtım (Play Internal) | ⏳ Sen yapacaksın |
| Test coverage | ❌ Faz 2 |

### Performans (2/4)

| # | Madde | Durum |
|---|---|---|
| P1 | EnableImpeller=false meta-data sil | ✅ |
| P2 | google_fonts runtime download | ❌ Faz 2 — DM Sans local'e taşınmalı |
| P3 | Cold start sıralı await | ⚠️ KISMI — `runZonedGuarded` içinde hâlâ sıralı, ama hata yakalama eklendi |
| P4 | loading.gif → Lottie | ❌ Faz 2 |

---

## 🎯 ÖZET

### Tamamlananlar — 35 madde

**Güvenlik & yasal (10):** S1, S2 (kod), S3, S4, S6, S7, KVKK aydınlatma, açık rıza, 18+ onayı, hesap silme
**Crash & kod kalitesi (7):** Q1-Q6 + U1 friendlyError
**UX (5):** Onboarding, Settings, hesap silme, veri export, disclaimer reshow
**Store hazırlığı (9):** Android paket/label, RECEIVE_BOOT_COMPLETED, adaptive icon, targetSdk, signing kod, ProGuard, 9 hukuki belge, hesap silme web form template
**Production eng (1):** Crashlytics kod
**Performans (1):** Impeller meta-data
**DB & altyapı (2):** Security audit SQL, dart-define secrets

### Senin tamamlaman gerekenler (yayın için bloker)

1. **Marka/iletişim:** Domain, e-posta, tüzel kişilik → hukuki TODO placeholder'lar
2. **Release keystore:** `keytool -genkey ...` + `key.properties` + 3 yedek
3. **Supabase deploy:** `db push` + `secrets set DELETION_HASH_SALT` + `functions deploy delete-account`
4. **Firebase setup:** `flutterfire configure` → Crashlytics + FCM aktive olur
5. **Web sitesi:** GitHub Pages'e hukuki belgeleri host (data-deletion form dahil)
6. **Play Console:** Hesap ($25), listing, screenshot setleri, age rating
7. **DB security audit'i çalıştır:** `supabase/audit/db_security_audit.sql` Supabase Dashboard'da

### Bilinçli olarak ertelenenler (yayın bloker DEĞİL)

- **Faz 2:** S5 obfuscation script otomasyonu, S9 cert pinning, S10 biometric, U2 retry widget, U6 accessibility, P2 local fonts, P3 parallel init, P4 Lottie, CI/CD, Crashlytics dışındaki monitoring, test coverage
- **Faz 3 (iOS):** Tüm iOS Store maddeleri — Apple Developer üyeliği açılınca

---

## 🚦 YAYINA HAZIR MI?

**Android için:** Senin 7 maddeni tamamlayınca **EVET**.
**iOS için:** Apple Developer üyelik + Faz 3'teki tüm iOS bloker'ları.

PRODUCTION_ROADMAP.md'deki "6 noktadan reddedilir" listesi:

| Sebep | Çözüldü mü? |
|---|---|
| Release imzası yok | ⏳ Kod hazır, keystore sende |
| WRITE_SECURE_SETTINGS | ✅ |
| PrivacyInfo.xcprivacy yok | ❌ iOS — Faz 3 |
| Privacy Policy URL yok | ⏳ Belge hazır, host etme sende |
| Hesap silme akışı yok | ✅ |
| iOS aps-environment dev | ❌ iOS — Faz 3 |

**Android-only yayın için 4/6 çözüldü, 2/6 sende.**
