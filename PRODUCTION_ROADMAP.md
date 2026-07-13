# sandık (PortfoyTakip) — Production Yol Haritası

**Tarih:** 2026-05-11
**Hazırlayan:** Senior Dev + UX Engineer Audit
**Hedef:** App Store + Google Play yayını
**Durum:** Bugün submit edilirse **6 noktadan otomatik reddedilir**

---

## YÖNETİCİ ÖZETİ

| Alan | Bulgu sayısı | Kritik |
|---|---|---|
| Güvenlik & veri güvenliği | 28 | 4 |
| Kod kalitesi & duplikasyon | 51 | P0: 6 |
| Crash potansiyeli | 25 | 10 |
| UX | 30 | 6 |
| Store hazırlığı | 50+ | 6 bloker |

**Bugün submit edersen reddedilme sebepleri:**

1. Release imzası yok (Play debug-imzalı AAB'yi reddeder)
2. `WRITE_SECURE_SETTINGS` izni (Play "restricted permissions" reddeder)
3. `PrivacyInfo.xcprivacy` yok (App Store ITMS-91053)
4. Privacy Policy URL yok (iki store da listing oluşturmaz)
5. Hesap silme akışı yok (Play 2024+, App Store 5.1.1(v))
6. iOS `aps-environment = development` (TestFlight dışında push çalışmaz)

**Tahminlenen yayın hazır olma süresi:** 4-6 hafta tam zamanlı çalışma.

---

## 1) GÜVENLİK & VERİ GÜVENLİĞİ AUDIT

### 1.1 KRİTİK Bulgular (4)

#### S1. WRITE_SECURE_SETTINGS izni
- **Konum:** `android/app/src/main/AndroidManifest.xml:3` + `MainActivity.kt:16`
- **Sorun:** `signature|privileged` seviye izin, third-party app'ler için yasaklı. Emülatör keyboard fix için eklenmiş; production'a sızmış.
- **Etki:** Play Console restricted permissions review → **otomatik ret**.
- **Çözüm:**
  ```xml
  <!-- AndroidManifest.xml — bu satırı sil -->
  <uses-permission android:name="android.permission.WRITE_SECURE_SETTINGS" />
  ```
  ```kotlin
  // MainActivity.kt — try/catch bloğunu sil
  ```

#### S2. Release imzası debug keystore ile
- **Konum:** `android/app/build.gradle.kts:35-39`
- **Sorun:** `release { signingConfig = signingConfigs.getByName("debug") }`
- **Etki:** Play Console debug-imzalı AAB'yi **reddeder** (Internal/Closed/Production hiçbir track).
- **Çözüm:**
  1. `keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
  2. `android/key.properties` dosyası (gitignore'lu):
     ```
     storePassword=...
     keyPassword=...
     keyAlias=upload
     storeFile=../upload-keystore.jks
     ```
  3. `build.gradle.kts`'e release `signingConfig` tanımla.
  4. Play App Signing aktive et.

#### S3. db_logs tablosu PII sızıntısı
- **Konum:** `lib/services/db_logger.dart` + `auth_service.dart:75,131`
- **Sorun:** Tüm DB istekleri (request body + response) Supabase'deki `db_logs` tablosuna yazılıyor. Auth flow'da email loglanıyor → KVKK'da kişisel veri.
- **Etki:** KVKK Madde 6 ihlali, App Store privacy review zorlaşır.
- **Çözüm:**
  ```dart
  // db_logger.dart başına:
  if (kReleaseMode) return;
  ```
  Veya hassas alanları (email, password, token, displayName) maskele.

#### S4. 25 .db dosyası repo root'unda
- **Konum:** Çalışma dizininde `db_5554.db`, `tmp_portfoy_5558_live.db`, `backup_portfoy_5554_before_restore.db` vb.
- **Sorun:** Test kullanıcı verisi içerebilir; gitignore'a alınmamışsa public repo'da exposed.
- **Çözüm:**
  ```gitignore
  *.db
  *.b64
  backup_*.db
  ```
  Mevcut dosyaları sil: `git rm --cached *.db && git commit -m "Remove dev databases"`.

### 1.2 YÜKSEK Öncelik (7)

| # | Konu | Konum | Çözüm |
|---|---|---|---|
| S5 | Code obfuscation yok | build script | `flutter build appbundle --obfuscate --split-debug-info=build/symbols` |
| S6 | ProGuard/R8 disabled | `build.gradle.kts:34` | `isMinifyEnabled = true`, `isShrinkResources = true` |
| S7 | Hardcoded Supabase URL/key | `lib/config/supabase_config.dart:3-4` | `String.fromEnvironment('SUPABASE_URL')` + `--dart-define` |
| S8 | Firebase config dosyaları yok | `google-services.json`, `GoogleService-Info.plist` | `flutterfire configure` |
| S9 | Certificate pinning yok | Network layer | `dio` + `dio_certificate_pinning` veya HttpClient interceptor |
| S10 | Biometric auth yok | Login flow | `local_auth` paketi, opsiyonel "Face ID ile gir" |
| S11 | Session timeout dokümante değil | `auth_provider.dart` | UI'da kalan süreyi göster |

### 1.3 KVKK/GDPR Uyumluluğu

**EKSİK:**
- KVKK Aydınlatma Metni
- Açık rıza checkbox'ı (register'da)
- Yurt dışı veri transferi (Supabase US) açık rıza
- Veri silme akışı (right to erasure)
- Veri export akışı (data portability)
- Kullanıcı haklarını listeleyen bölüm

**Çözüm:** Faz 1 → 2 hafta hukuki içerik + UI entegrasyonu.

---

## 2) KOD KALİTESİ & DUPLİKASYON AUDIT

### 2.1 P0 — Hemen Düzelt (6)

#### Q1. `state.requireValue` race condition crash
- **Konum:** `lib/providers/portfolio_provider.dart:160`
- **Sorun:** `updateManualPrice()` içinde state AsyncLoading olabilir → `StateError`.
- **Çözüm:**
  ```dart
  final s = state.valueOrNull;
  if (s == null) return;
  ```

#### Q2. `firstWhere` orElse'siz çağrılar
- **Konum:** `lib/screens/add_asset_screen.dart:947`
- **Çözüm:**
  ```dart
  _dovizOptions.firstWhere(
    (o) => o.label == _subCategory,
    orElse: () => _dovizOptions.first,
  );
  ```

#### Q3. fl_chart yInterval = 0 crash
- **Konum:** `portfolio_performance_screen.dart:362`, `portfolio_detail_screen.dart:234`
- **Çözüm:**
  ```dart
  final yInterval = ((maxY - minY) / 4).clamp(1.0, double.infinity);
  ```

#### Q4. JSON parse cast hataları
- **Konum:** `supabase_service.dart:202-204`
- **Çözüm:** `as String?` + null check, `try/catch` map içinde.

#### Q5. Empty list `partners[0].displayName[0]` crash
- **Konum:** `home_screen.dart:142,143`, `profile_screen.dart:492`
- **Çözüm:** `displayName.isNotEmpty ? displayName[0].toUpperCase() : '?'`

#### Q6. Supabase çağrılarında timeout YOK
- **Konum:** `supabase_service.dart` (tüm metotlar)
- **Çözüm:** Wrapper helper:
  ```dart
  Future<T> _withTimeout<T>(Future<T> f) =>
      f.timeout(const Duration(seconds: 15));
  ```

### 2.2 P1 — Bu Sprint İçinde (15)

| # | Konu | Etki |
|---|---|---|
| Q7 | `IndexedStack` ile tüm 5 ekran aynı anda mount | Battery + DB cost |
| Q8 | ProfileScreen `Timer.periodic(5sn)` her zaman çalışıyor | Polling sürekli |
| Q9 | `refreshPrices` race condition (provider cycle) | Infinite loop riski |
| Q10 | Login double-routing | UX bug |
| Q11 | 14 yerde NumberFormat duplikasyonu | DRY |
| Q12 | 122 BoxDecoration inline | Performance |
| Q13 | `_view!` non-null assertion | Crash riski |
| Q14 | Tüm ekranlarda hata mesajı `e.toString()` | UX + güvenlik |
| Q15 | StreamSubscription leak (Supabase realtime) | Memory |
| Q16 | `assets[0]` kontrolsüz | Crash |
| Q17 | `firstWhere` performance_screen tekrarlı build | Perf |
| Q18 | toTRY switch unknown currency 1:1 fallback | Yanlış değer |
| Q19 | DateFormat 'en_US' tutarsız | Localization |
| Q20 | `Future.then` mounted kontrolü eksik (1 yerde) | setState after dispose |
| Q21 | `_pollTimer` her build re-set | Resource churn |

### 2.3 Dead Code (~1100 LoC)

- Unused widgets: 4 dosya
- Unused service methods: ~12
- Eski theme constants: 30+
- Legacy `bronze`/`adacayi` color references

**Aksiyon:** `dart analyze --fatal-infos` + `flutter analyze` + manuel review → silinebilir.

### 2.4 Refactor Önerileri

1. **Helper modülü:** `lib/utils/formatters.dart` → tüm NumberFormat/DateFormat tek yer.
2. **Error helper:** `lib/utils/friendly_error.dart` → SocketException → "İnternet yok", vb.
3. **Decoration factory:** `Sandik.cardDecoration()`, `Sandik.glassDecoration()` (zaten var) — inline'ları taşı.
4. **Service base class:** `BaseService` ile timeout + error handling sarmalama.

---

## 3) CRASH POTANSİYELİ AUDIT

### 3.1 KRİTİK (10) — Faz 1'de fix

| # | Crash | Konum | Tetikleyici |
|---|---|---|---|
| C1 | `state.requireValue` StateError | `portfolio_provider.dart:160` | Refresh sırasında manuel fiyat update |
| C2 | `firstWhere` StateError | `add_asset_screen.dart:947` | Eski döviz kodu |
| C3 | fl_chart `assert(interval > 0)` | `portfolio_performance_screen.dart:362` | Tek nokta veri |
| C4 | JSON `as String` cast | `supabase_service.dart:202` | Bozuk timestamp |
| C5 | `displayName[0]` IndexOutOfRange | `home_screen.dart:143` | Boş displayName |
| C6 | Network timeout-free spin | `supabase_service.dart` (genel) | Zayıf bağlantı |
| C7 | `_view!` null assertion | `home_screen.dart:113` | Race condition |
| C8 | `IndexedStack` polling timer leak | `main_navigation_screen.dart:96` | App background |
| C9 | `Settings.Secure.putInt` SecurityException | `MainActivity.kt:16` | Production cihaz |
| C10 | `Navigator.pop(context)` ana sekmede | `charts_screen.dart:48` | Back button |

### 3.2 YÜKSEK (10) — Faz 2

Detay: kapsamlı liste [yukarıdaki bölümlerde](#2-kod-kalitesi--duplikasyon-audit) Q-prefixli maddelerle örtüşüyor.

---

## 4) UX AUDIT

### 4.1 KRİTİK UX (6)

#### U1. Hata mesajları teknik (`Exception: SocketException...`)
- **Konum:** `charts_screen.dart:108`, `home_screen.dart:86,91`, vb.
- **Çözüm:** `_friendlyError(e)` helper:
  ```dart
  String friendlyError(Object e) {
    if (e is SocketException) return 'İnternet bağlantını kontrol et';
    if (e is TimeoutException) return 'Sunucu yanıt vermedi, tekrar dene';
    return 'Bir şeyler ters gitti';
  }
  ```

#### U2. Error ekranlarında "Tekrar Dene" yok
- **Konum:** Tüm `error: (e, _) => Center(child: Text('Hata: $e'))` patterns
- **Çözüm:** `ErrorRetryView` widget — message + retry button.

#### U3. Onboarding YOK
- Yeni kullanıcı kayıt → boş ana ekran → ne yapacağını anlamaz.
- **Çözüm:** 3-step overlay tutorial: "Varlık ekle → Performansı izle → Ortakla paylaş".

#### U4. Hesap silme akışı YOK (Store bloker + KVKK)
- **Çözüm:** Profile → "Hesabımı Sil" → onay dialog → Supabase Edge Function `delete-account` → cascade delete.

#### U5. Settings ekranı YOK
- Eksik: Tema seçimi, bildirim yönetimi, para birimi, şifre değiştirme, e-posta değiştirme, destek/iletişim, disclaimer'ı tekrar görüntüleme, veri export.
- **Çözüm:** Profile altında "Ayarlar" subsection.

#### U6. Accessibility tamamen ihmal
- 2 yerde Semantics, çoğu IconButton tooltip'siz, color contrast WCAG fail.
- **Çözüm:** Audit + Semantics wrapping + tooltip + min 48x48 touch target.

### 4.2 YÜKSEK UX (10)

| # | Sorun | Çözüm |
|---|---|---|
| U7 | Empty state'lerde CTA yok | "Varlık Ekle" / "Davet Kodu Üret" butonları |
| U8 | Pull-to-refresh tutarsız (4 ekrandan 2'sinde yok) | Tümüne `RefreshIndicator` |
| U9 | Loading sırasında stale data + spinner karışık | "Güncelleniyor..." chip |
| U10 | Logout 4 farklı tasarım | Tek widget: `SandikLogoutButton` |
| U11 | Period toggle 3 farklı stil | Tek `PeriodTabs` widget |
| U12 | Snackbar/Dialog karışık (login Dialog, register Snackbar) | Tek pattern: `_showError()` helper |
| U13 | Form autofocus eksik | İlk field'a `autoFocus: true` |
| U14 | Validation submit-only | Real-time `onChanged` validation |
| U15 | "Bildirimler kapalı" uyarısı yok | Profile'da banner |
| U16 | Tarih lokalizasyonu tutarsız (en_US vs tr_TR) | Hepsi `tr_TR` |

### 4.3 ORTA UX (14)

Detay tabloları kaldırıldı (referans için orijinal audit raporuna bakın).

---

## 5) STORE HAZIRLIĞI AUDIT

### 5.1 Android (Google Play)

#### Bloker (5)
1. Release signing yok → keystore + key.properties (S2)
2. `WRITE_SECURE_SETTINGS` izni → sil (S1)
3. `applicationId` değişmeli mi? `com.portfoytakip.portfoy_takip` veya `com.sandik.app`? — **Marka kararı gerekli**
4. App label `portfoy_takip` → `sandık`
5. `RECEIVE_BOOT_COMPLETED` kullanılmıyor → sil

#### Önerilen
- Adaptive icon (mipmap-anydpi-v26 yok) → `flutter_launcher_icons` config update
- ProGuard/R8 → minify enable + keep rules
- `targetSdk = 35` explicit
- ABI splits + obfuscation

### 5.2 iOS (App Store)

#### Bloker (4)
1. **`PrivacyInfo.xcprivacy` yok** → ITMS-91053 ile ret. Gerekli kategoriler:
   - `NSPrivacyTracking = false`
   - `NSPrivacyAccessedAPITypes`: UserDefaults (CA92.1), FileTimestamp (C617.1), SystemBootTime (35F9.1), DiskSpace (E174.1)
2. `aps-environment = development` → `production`
3. `DEVELOPMENT_TEAM` set edilmemiş → Apple Developer Team ID
4. Distribution certificate yok → "iPhone Distribution"

#### Önerilen
- `CFBundleDisplayName = "sandık"` ve `CFBundleName = "sandik"` (ASCII)
- LaunchScreen.storyboard'a marka logo + dark background
- Universal Links (opsiyonel, partnership invite için faydalı)

### 5.3 Yasal Gereklilikler

| Madde | Durum | Öncelik |
|---|---|---|
| Privacy Policy URL | YOK | Bloker |
| Terms of Service | YOK | Yüksek |
| KVKK Aydınlatma Metni | YOK | Bloker |
| KVKK açık rıza checkbox (register) | YOK | Bloker |
| GDPR DSAR süreci | YOK | Yüksek |
| Hesap silme akışı | YOK | Bloker |
| Veri export | YOK | Yüksek |
| Yaş onay (17+) | YOK | Orta |
| Yatırım disclaimer | VAR ✓ | — |

### 5.4 Store Listing

| Asset | Durum |
|---|---|
| App icon (Android) | VAR ✓ (adaptive eksik) |
| App icon (iOS) | VAR ✓ |
| Screenshot setleri (Play + App Store) | YOK |
| Feature graphic 1024×500 | YOK |
| Short description | YOK |
| Long description | YOK |
| ASO keywords (App Store) | YOK |
| Age rating formu | YOK |

### 5.5 Production Engineering

| Sistem | Durum |
|---|---|
| Crash reporting (Firebase Crashlytics / Sentry) | YOK |
| Analytics | YOK (opsiyonel) |
| Remote Config / Kill switch | YOK |
| CI/CD (GitHub Actions / Codemagic) | YOK |
| Beta dağıtım (TestFlight + Play Internal) | YOK |
| Test coverage | Placeholder (`expect(true, isTrue)`) |

### 5.6 Performans

| # | Konu | Çözüm |
|---|---|---|
| P1 | `EnableImpeller = false` (manifest) | Sil — 2025'te default ve stable |
| P2 | google_fonts runtime download | Asset olarak local'e al, `allowRuntimeFetching = false` |
| P3 | Cold start sıralı await | `Future.wait` ile paralel init |
| P4 | `loading.gif` boyutu | Lottie veya optimize PNG sequence |

### 5.7 3rd Party Bağımlılıklar

- **Yahoo Finance API:** Unauthenticated kullanım TOS gri alan → IP ban riski. Faz 3'te paid alternative (Finnhub / Twelve Data / IEX Cloud) migration planlanmalı.

---

## 🗺️ YOL HARİTASI

### FAZ 1 — Yayın Bloker'ları (2 hafta)

**Hafta 1:**
- [ ] S1: WRITE_SECURE_SETTINGS sil + MainActivity temizle (1 saat)
- [ ] S2: Release signing setup (3 saat)
- [ ] S4: .db dosyalarını gitignore + sil (30 dk)
- [ ] Q1-Q6: P0 crash fix'leri (1 gün)
- [ ] U1: `friendlyError()` helper + tüm hata yerlerine uygula (4 saat)
- [ ] U2: `ErrorRetryView` widget (4 saat)
- [ ] iOS bloker: `PrivacyInfo.xcprivacy` (4 saat)
- [ ] iOS bloker: aps-environment production + APNs key (2 saat)
- [ ] iOS bloker: DEVELOPMENT_TEAM + distribution cert (3 saat — Apple Developer üyelik gerekli)
- [ ] Android: applicationId + label refactor (4 saat — marka kararı sonrası)
- [ ] Android: RECEIVE_BOOT_COMPLETED sil, targetSdk explicit (1 saat)

**Hafta 2:**
- [ ] U4: Hesap silme akışı (app içi + Edge Function) (2 gün)
- [ ] U5: Settings ekranı temel (tema + bildirim + disclaimer reshow + destek) (1 gün)
- [ ] Privacy Policy + ToS yazımı + hosting (3 gün — paralel hukuki)
- [ ] KVKK Aydınlatma Metni + register checkbox (1 gün)
- [ ] S3: db_logs production disable (1 saat)
- [ ] S7: Hardcoded secrets → dart-define (4 saat)
- [ ] S8: Firebase config dosyaları (`flutterfire configure`) (4 saat)
- [ ] Adaptive icon (foreground+background+monochrome) (3 saat)
- [ ] Store listing materyalleri: screenshot + feature graphic + açıklama + age rating (3-4 gün — paralel tasarım)

### FAZ 2 — Production Kalite (2-3 hafta)

- [ ] ProGuard/R8 + keep rules + mapping upload (1 gün)
- [ ] Firebase Crashlytics entegrasyonu (4 saat)
- [ ] Firebase Remote Config (min_version, kill_switch) (1 gün)
- [ ] CI/CD (GitHub Actions Android + Codemagic iOS) (2-3 gün)
- [ ] TestFlight + Play Internal Testing kurulum (1 gün)
- [ ] Q7-Q21: P1 kod kalitesi fix'leri (3-4 gün)
- [ ] U3: Onboarding (3-step tutorial) (2 gün)
- [ ] U6: Accessibility audit + Semantics + tooltip (2 gün)
- [ ] U8-U16: UX tutarlılık (period toggle, logout, snackbar pattern, vb.) (3 gün)
- [ ] Veri export (JSON download) (1 gün)
- [ ] Unit testler (auth, disclaimer, price parser) (2-3 gün)
- [ ] Integration test (golden path) + Firebase Test Lab (2 gün)
- [ ] P1-P4: Performans optimizasyonu (1 gün)
- [ ] LaunchScreen branding iOS (4 saat)

### FAZ 3 — Yayın Sonrası İyileştirmeler (3+ hafta)

- [ ] Yahoo Finance → Finnhub/Twelve Data migration (3-5 gün)
- [ ] Localization (EN, AR) — flutter_localizations + ARB (5-7 gün)
- [ ] Universal Links / Android App Links (2-3 gün)
- [ ] Tablet UX optimizasyonu (3-5 gün)
- [ ] Biometric auth (Face ID / Fingerprint) (1 gün)
- [ ] Certificate pinning (1 gün)
- [ ] Premium tier (StoreKit + Play Billing) — opsiyonel (2 hafta+)
- [ ] Apple Watch / Widget complication — vizyon

---

## ÖNCELİK MATRİSİ

```
                  YÜKSEK ETKİ
                       |
   S1 (izin sil)       |    Privacy Policy
   S2 (signing)        |    Hesap silme
   PrivacyInfo.xcprivacy    Onboarding
                       |
DÜŞÜK EFOR ────────────┼──────────────── YÜKSEK EFOR
                       |
   db_logs disable     |    CI/CD
   Impeller manifest   |    Localization
   targetSdk explicit  |    Yahoo migration
                       |
                  DÜŞÜK ETKİ
```

**Önce sol-üst kadrandakileri yap.** Sağ-üst kadran Faz 1+2'nin gövdesi. Sol-alt quick win. Sağ-alt Faz 3.

---

## SONRAKİ ADIM ÖNERİSİ

Bu plana göre sırayla:

1. **Önce marka kararı:** `applicationId` ve `bundleId` ne olacak? `com.sandik.app` mı `com.portfoytakip.portfoy_takip` mi? — Bu kararı verince refactor başlayabilir.
2. **Apple Developer üyelik açıldı mı?** ($99/yıl) — iOS bloker'larını çözmek için gerekli.
3. **Privacy Policy / ToS / KVKK yazımı** — Hukuki danışmanlık veya template ile başlat.

Bu üçü hazır olunca FAZ 1 implementasyona geçebiliriz. Hangi maddeden başlamak istersin?
