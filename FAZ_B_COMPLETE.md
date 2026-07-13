# Faz B — Yayın Sonrası 30 Gün Tamamlandı

**Tarih:** 2026-05-13  
**Build durumu:** ✅ `flutter analyze` — 0 warning/error · `flutter build apk --debug` başarılı

---

## 🔒 Güvenlik (7 madde)

### B2: Persistent Rate Limit
**Önce:** `Map<String, List<DateTime>>` in-memory — uygulama kapanınca sıfırlanıyordu  
**Sonra:** `SharedPreferences` backing — her deneme timestamp olarak kaydediliyor, uygulama yeniden başlasa da 10 dakikalık pencere korunuyor. Key: `rl_attempts_{userId.hashCode}`

### B3: Email Confirmation Server-Side Check
**Önce:** `signInWithPassword` başarılı olursa her kullanıcı giriş yapabiliyordu  
**Sonra:** [auth_service.dart](lib/services/auth_service.dart) — `response.user!.emailConfirmedAt == null` ise `signOut` + `AuthException` atılıyor

### E1+E2: friendlyError Heuristic Kaldırıldı
**Önce:** `_authMessage` ve `_humanize` içinde `RegExp(r'[ğüşıöçĞÜŞİÖÇ]')` heuristic — İngilizce teknik mesaj içinde Türkçe karakter bulunursa olduğu gibi gösteriliyordu  
**Sonra:**
- `_authMessage` → her branch deterministik Türkçe mesaj döndürür, fallback `'Giriş işlemi başarısız oldu.'`
- `_humanize` → sadece kendi `AuthException` mesajlarımız (Türkçe) geçirilir; İngilizce teknik mesajlar generic fallback'e düşer
- E2: [settings_screen.dart](lib/screens/settings_screen.dart) `'Beklenmedik hata: $e'` → `showAppError(context, e)`

### E5: FLAG_SECURE
**Önce:** Ekran içeriği recents menüsünde ve screenshot'larda görünüyordu  
**Sonra:** [MainActivity.kt](android/app/src/main/kotlin/com/sandik/app/MainActivity.kt) — `window.setFlags(FLAG_SECURE, FLAG_SECURE)` `onCreate`'te eklendi

### E6: Crashlytics PII Sanitize
**Önce:** `recordError` raw exception string gönderiyordu — email, UUID, JWT loglara düşebilirdi  
**Sonra:** [main.dart](lib/main.dart) — `DbLogger.sanitize()` her `recordError` çağrısından önce uygulanıyor. `DbLogger.sanitize` `static` olarak açıldı

### G1: Clipboard Sadece Kısa Kod
**Önce:** `Share.share(_generatedCode!)` — timestamp'li tam payload paylaşılıyordu  
**Sonra:** [profile_screen.dart](lib/screens/profile_screen.dart) — paylaşım `code.split(':')[0]` kısa kodu kullanıyor; clipboard'a da sadece kısa kod yazılıyor

### H2: Account Enumeration Fix
**Önce:** `'Bu e-posta zaten kayıtlı.'` — saldırgan hangi email'in sistemde olduğunu öğrenebiliyordu  
**Sonra:** [auth_service.dart](lib/services/auth_service.dart) — `'Kayıt işlemi tamamlandı. E-posta adresinizi kontrol edin.'` (hem kayıtlı hem yeni kullanıcı için aynı mesaj)

---

## 🎨 UX (7 madde)

### UK1: Bakiye Gizleme Toggle
**Sonra:**
- [preferences_provider.dart](lib/providers/preferences_provider.dart) — `balanceHiddenProvider` (`_BoolPrefNotifier`, SharedPreferences kalıcı)
- [home_screen.dart](lib/screens/home_screen.dart) — AppBar'a `_BalanceToggleButton` (göz ikonu, aktifken amber renk)
- `PortfolioSummaryWidget` — `hideBalance: true` iken `••••••` gösterir
- Mini kartlar ve işlem listesi de maskelenir

### UD1: SandikErrorView Widget
**Sonra:** [widgets/sandik_error_view.dart](lib/widgets/sandik_error_view.dart) — `error` + opsiyonel `onRetry` butonu. Tüm ekranlardaki `Center(child: Text(friendlyError(e)))` → `SandikErrorView(error: e, onRetry: ...)` ile değiştirildi:
- `home_screen.dart`, `charts_screen.dart`, `portfolio_performance_screen.dart`, `portfolio_detail_screen.dart`, `profile_screen.dart`

### UB1: showAppError() Helper
**Sonra:** [utils/friendly_error.dart](lib/utils/friendly_error.dart) — `showAppError(context, error)` → floating SnackBar, `hideCurrentSnackBar()` ile öncekini kapatır. Login, register, settings genelinde kullanılıyor

### UC2: Disabled Submit Button Hint
**Sonra:** [register_screen.dart](lib/screens/register_screen.dart) — `_canSubmit` false iken butona tıklanınca `showAppError` ile "tüm yasal koşulları kabul etmelisin" mesajı gösterilir (buton artık `null` değil)

### UC3: LoginScreen Inline Spinner
**Önce:** `if (_loading) return const SandikLoadingScreen()` — tüm ekran değişiyordu  
**Sonra:** [login_screen.dart](lib/screens/login_screen.dart) — buton içinde `CircularProgressIndicator`, ekran sabit kalıyor

### UG1+UG2: Davet Akışı İyileştirme
**UG1:** [profile_screen.dart](lib/screens/profile_screen.dart) — paylaş butonu hem clipboard'a kopyalar hem `Share.share('sandık ortak kodum: $shortCode')` çağırır (tek akış)  
**UG2:** Kod input alanı `keyboardType: TextInputType.number` → `TextInputType.text` + `textCapitalization: TextCapitalization.characters`

### UI4: url_launcher
**Önce:** Legal link'ler dialog'da `SelectableText` olarak gösteriliyordu  
**Sonra:** [settings_screen.dart](lib/screens/settings_screen.dart) — `launchUrl(uri, mode: LaunchMode.externalApplication)` ile tarayıcıda açılıyor. `url_launcher: ^6.3.1` pubspec'e eklendi

---

## 📦 Yeni / Değişen Dosyalar

### Yeni dosyalar
- `lib/widgets/sandik_error_view.dart`
- `FAZ_B_COMPLETE.md` (bu dosya)

### Değişen dosyalar
- `lib/providers/preferences_provider.dart` — `balanceHiddenProvider`
- `lib/widgets/portfolio_summary_widget.dart` — `hideBalance` parametresi
- `lib/screens/home_screen.dart` — bakiye gizleme, SandikErrorView, import temizleme
- `lib/screens/charts_screen.dart` — SandikErrorView
- `lib/screens/portfolio_performance_screen.dart` — SandikErrorView, unused import fix
- `lib/screens/portfolio_detail_screen.dart` — SandikErrorView, unused `fmt` kaldırıldı
- `lib/screens/profile_screen.dart` — SandikErrorView, davet paylaşımı, klavye tipi
- `lib/screens/login_screen.dart` — inline spinner, showAppError, SandikLoadingScreen kaldırıldı
- `lib/screens/register_screen.dart` — UC2 hint, showAppError, import temizleme
- `lib/screens/settings_screen.dart` — url_launcher, showAppError, raw exception fix
- `lib/services/auth_service.dart` — B2 persistent rate limit, B3 email confirmation, H2 enumeration fix
- `lib/services/db_logger.dart` — `sanitize()` static method
- `lib/services/history_service.dart` — unused `todayNorm` kaldırıldı
- `lib/utils/friendly_error.dart` — `showAppError()`, heuristic kaldırıldı
- `lib/main.dart` — E6 Crashlytics sanitize
- `android/app/src/main/kotlin/com/sandik/app/MainActivity.kt` — FLAG_SECURE
- `pubspec.yaml` — `url_launcher: ^6.3.1`

---

## 📋 Faz C — Sıradaki (İyileştirme)

UA3 onboarding key user-bazlı, UB2-UB6 tutarsızlık, UC5 add asset disabled pattern, UD2 empty CTA, UD3 offline mode, UE1 lazy notification permission, UI1 bottom nav redundancy, UI3 back button tab, UJ1 brand voice, UK2 manuel fiyat banner

**Sonuç:** Faz B tamamlandı. 0 warning/error, build temiz. Supabase deploy (Faz A'dan bekleyen) yapılırsa Play Store internal testing'e gönderilebilir.
