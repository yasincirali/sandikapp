# Google ile giriş — kurulum rehberi (devir belgesi)

**Yazıldı:** 2026-09-27 · **Durum:** kod hazır, yapılandırma yok → düğme iki
platformda da **görünmüyor**. **Hedef:** Android + iOS'ta çalışan Google ile
giriş, kapalı testin 14 günü içinde (sayaç sıfırlanmaz, testçiler güncelleme
alır).

Bu belge bir sonraki oturumun sıfırdan keşif yapmaması için yazıldı. Her adım
**[SEN]** (kullanıcının hesabını/tarayıcısını ister) veya **[CLAUDE]** (repo +
CLI) diye işaretli. Sırayla git; bir adım bitmeden sonrakine geçme.

---

## 0. Neden şimdiye kadar kapalıydı

Android'de Google girişi, uygulamayı imzalayan anahtarların **SHA-1**'lerini
ister ve üçü de Google Cloud'daki Android istemcisine kayıtlı olmalıdır:

| Anahtar | Nerede | Kullanıldığı yer |
|---|---|---|
| debug | `~/.android/debug.keystore` | `flutter run` |
| upload | `upload-keystore.jks` (repo kökü, gitignore'da) | CI'ın ürettiği AAB |
| **Play App Signing** | Google'da; **ilk AAB Play'e yüklenince oluşur** | Play'den inen uygulama — testçiler ve kullanıcılar |

2026-09-14'te üçüncüsü yoktu (uygulama Play'de değildi). Eksik SHA-1 ile
açılsaydı iOS'ta çalışıp Play'den inen Android'de `DEVELOPER_ERROR` verirdi.
Kod bu yüzden kimlik verilmeden düğmeyi çizmiyor — yarım özellik görünmüyor.

## 1. Kodda hazır olanlar (dokunma, yalnızca bil)

| Dosya | Ne yapıyor |
|---|---|
| `lib/config/supabase_config.dart` | `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` — `String.fromEnvironment`, fallback yok |
| `lib/services/social_auth_service.dart` | `google_sign_in` 7.x: `initialize(serverClientId: web, clientId: ios)` → `authenticate()` → idToken. `availableProviders`: web ID boşsa Google düğmesi yok |
| `lib/services/auth_service.dart` | `loginWithSocial` → `signInWithIdToken(provider: google, idToken)`; `deleteAccount` sosyal hesapta taze kimliği yine buradan alır |
| `lib/widgets/social_sign_in_buttons.dart` | Giriş ve kayıt ekranlarının altındaki düğmeler |
| `.github/workflows/android-release.yml`, `ios-testflight.yml`, `mobsf-scan.yml` | İki kimliği **GitHub secret'ından** `--dart-define` ile verir; secret yoksa boş kalır, build kırılmaz |
| `test/social_sign_in_test.dart` | Düğme görünürlük kuralı |

**Eksik tek kod parçası:** iOS `Info.plist` → `CFBundleURLTypes`'ta iOS
istemcisinin **ters** kimliği (adım 6).

## 2. Ön koşul

- [ ] **[SEN]** İlk AAB (`tmp/android-release-v1/app/outputs/bundle/release/app-release.aab`,
      1.1.6+7) Play Console'da **kapalı teste yüklendi**. Bu olmadan Play App
      Signing SHA-1'i yok → adım 3 yapılamaz.

## 3. SHA-1'leri topla

- [ ] **[SEN]** Play Console → sandık → **Test edin ve yayınlayın → Kurulum →
      Uygulama bütünlüğü → Uygulama imzalama** (ya da "Uygulama imzalama
      anahtarı sertifikası"). İki SHA-1'i kopyala:
      **Uygulama imzalama anahtarı** ve **Yükleme anahtarı**.
- [ ] **[CLAUDE]** Debug SHA-1 (şifresi herkesçe bilinen `android`):
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey \
    -storepass android -keypass android | grep SHA1
  ```
  (Windows'ta `~` = `C:/Users/vasin`. keytool PATH'te yoksa Android Studio'nun
  `jbr/bin/keytool.exe`'si.) Upload SHA-1'ini Play'den okumak yeter; keystore
  şifresini komut satırına yazmaya gerek yok.

## 4. Google Cloud — OAuth izin ekranı + 3 istemci

Proje: **Firebase'in bağlı olduğu Google Cloud projesi** (aynı proje →
`google-services.json` ile tutarlı). console.cloud.google.com → üstten o
projeyi seç.

- [ ] **[SEN] OAuth izin ekranı** (APIs & Services → OAuth consent screen /
      "Google Auth Platform"):
  - Kullanıcı türü **Harici (External)**, uygulama adı `sandık`, destek
    e-postası `sandikapp.destek@gmail.com`
  - Ana sayfa `https://yasincirali.github.io/sandikapp`, gizlilik
    `…/sandikapp/privacy`, koşullar `…/sandikapp/terms`
  - Yetkili alan adı: `yasincirali.github.io` ve `supabase.co`
  - Kapsamlar: yalnızca `openid`, `email`, `profile` (hassas değil → Google
    doğrulaması gerekmez)
  - **Yayınla (In production)**. "Testing" durumunda yalnızca test
    kullanıcıları girebilir — testçiler takılır.
- [ ] **[SEN] Web istemcisi** (Credentials → Create credentials → OAuth
      client ID → **Web application**), ad `sandik-web (Supabase)`:
  - Authorized redirect URI: `https://<SUPABASE_PROJECT_REF>.supabase.co/auth/v1/callback`
  - Çıktı: **Client ID** + **Client secret** → ikisini de not al
- [ ] **[SEN] Android istemcisi** — **Android**, paket `com.sandik.app`,
      SHA-1: **Play App Signing**. Aynı paketle **iki istemci daha** aç:
      upload SHA-1 ve debug SHA-1 (Google Cloud her Android istemcisine tek
      SHA-1 alıyor). Android istemcilerinin Client ID'si kodda **kullanılmaz** —
      yalnızca var olmaları gerekir (`google_sign_in` 7 Android'de Credential
      Manager ile `serverClientId` = Web ID kullanır).
- [ ] **[SEN] iOS istemcisi** — **iOS**, bundle ID `com.sandik.app`,
      App Store ID `6786837699`. Çıktı: **Client ID** + "iOS URL scheme"
      (`com.googleusercontent.apps.XXXX` — ters kimlik).

## 5. Supabase — Google sağlayıcısı

- [ ] **[SEN]** Dashboard → Authentication → Sign In / Providers → **Google**:
  - Enable
  - **Client IDs**: Web ID, iOS ID ve üç Android ID'yi **virgülle** yaz
    (Web ID ilk sırada). Eksik olan platformun token'ı `aud` uyuşmazlığıyla 400 döner.
  - **Client Secret**: Web istemcisinin secret'ı
  - **Skip nonce check: AÇIK.** iOS Google SDK token'a kendi nonce'unu koyar,
    istemci ham hâlini bilmez; kapalıyken iOS'ta giriş "nonce mismatch" ile
    düşer. (Apple girişi kendi nonce'unu yolluyor, etkilenmez.)
  - Kaydet.
- [ ] **[SEN]** Authentication → **URL Configuration**'da bir şey değiştirme
      (native akış redirect kullanmaz).

## 6. Repo — iOS URL şeması + secret'lar

- [ ] **[CLAUDE]** `ios/Runner/Info.plist` → `CFBundleURLTypes` dizisine
      **ikinci** bir `dict` ekle (mevcut `sandik` şemasına dokunma):
  ```xml
  <dict>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>CFBundleURLName</key>
      <string>com.sandik.app.google</string>
      <key>CFBundleURLSchemes</key>
      <array>
          <string>com.googleusercontent.apps.XXXX</string>
      </array>
  </dict>
  ```
  **Karar:** eski not (`YAPMAN_GEREKENLER` #16-d) "repoya kimlik yazmamak için
  elle ekle" diyordu. Ama TestFlight build'i CI'da repodan üretiliyor — elle
  eklenen satır CI'a gitmez, iOS'ta giriş dönüşü kırılır. Ters kimlik gizli
  değildir (her iOS ikilisinin Info.plist'inde açıkça durur); commit'le.
  Gizli olan yalnızca **Web client secret** — o repoya da secret'a da girmez,
  yalnızca Supabase panelinde durur.
- [ ] **[SEN]** GitHub secret'ları (auto mode secret yazmayı engeller — komutu sen koş):
  ```bash
  cd /c/projects/PortfoyTakip
  gh secret set GOOGLE_WEB_CLIENT_ID --body "<web>.apps.googleusercontent.com"
  gh secret set GOOGLE_IOS_CLIENT_ID --body "<ios>.apps.googleusercontent.com"
  gh secret list | grep GOOGLE_
  ```

## 7. Yerel doğrulama (debug, emülatör ya da cihaz)

- [ ] **[CLAUDE]** `flutter analyze lib/ test/` + `flutter test test/social_sign_in_test.dart`
- [ ] **[CLAUDE/SEN]** Debug çalıştırma — debug SHA-1 kayıtlı olduğu için yerelde de çalışmalı:
  ```bash
  /c/flutter/bin/flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
    --dart-define=GOOGLE_WEB_CLIENT_ID=<web> --dart-define=GOOGLE_IOS_CLIENT_ID=<ios>
  ```
  Emülatörler Flutter'ı çizemiyor (CLAUDE.md) — dokunma testi gerçek
  Android cihazda. Kontrol listesi:
  1. Giriş ekranında "Google ile devam et" görünüyor
  2. Yeni Google hesabıyla giriş → onboarding → ana ekran
  3. **Aynı e-postayla önceden şifreli hesabı olan kullanıcı** Google ile
     girince yeni boş hesap mı açılıyor, yoksa mevcut hesaba mı bağlanıyor?
     (Supabase doğrulanmış aynı e-postayı otomatik bağlar; bağlamıyorsa bu
     **veri kaybı gibi görünür** — kullanıcıya boş portföy çıkar. Sonucu
     buraya yaz.)
  4. Çıkış → tekrar giriş: hesap seçici yeniden soruyor (`signOutGoogle`)
  5. Google hesabıyla **Hesabımı Sil** akışı taze kimlik istiyor ve siliyor

## 8. Sürüm

- [ ] **[CLAUDE]** CLAUDE.md "Yenilikler / tanıtım" kuralı — giriş ekranı
      değişiyor: `lib/config/surum_notlari.dart` başına not (`surum` =
      yayınlanacak sürüm, `onemli: false` — ana yüzey değil). Tur adımı
      giriş ekranını anlatmıyorsa "tur etkilenmedi" diye özette yaz.
- [ ] **[SEN]** `main`'e push → iOS TestFlight (fastlane sürümü kendisi artırır).
- [ ] **[SEN]** `gh workflow run android-release.yml --ref main` (auto mode bunu
      "Production Deploy" sayıp engelliyor) → **[CLAUDE]** koşuyu izle, AAB'yi
      `tmp/` altına indir → **[SEN]** kapalı teste **yeni sürüm** olarak yükle.
  - ⚠️ **[CLAUDE] Koşudan ÖNCE versionCode.** Doğrulandı (2026-09-27):
    `android-release.yml` build numarası vermiyor, `build.gradle.kts`
    `versionCode = flutter.versionCode` → pubspec'in `+N`'si. İlk AAB **7**
    ile yüklendi; ikinci AAB de 7 çıkar ve Play "bu sürüm kodu zaten
    kullanıldı" diye **reddeder**. iOS'ta fastlane artırıyor, Android'de
    karşılığı yok. Çözüm (karar yeni oturumun): `flutter build appbundle`
    satırına `--build-number=$((100 + GITHUB_RUN_NUMBER))` gibi tekdüze
    artan bir değer ver (7'den büyük başlamalı; iOS ile çakışması sorun
    değil, mağazalar ayrı sayar) — pubspec'i elle bump etme kuralını bozmaz.
- [ ] **[SEN]** Play'den inen sürümde (testçi hesabıyla) Google girişini dene —
      Play App Signing SHA-1'inin doğru girildiğinin **tek** kanıtı budur.
- [ ] **[SEN]** Çalıştığı doğrulanınca Play ve App Store açıklamalarına
      `Google ile giriş` ifadesini **geri ekle** (2026-09-27'de bu yüzden çıkarıldı).
- [ ] **[CLAUDE]** `YAPMAN_GEREKENLER.md` #16'yı KAPANDI yap, bu belgeye sonucu yaz.

## Hata → neden tablosu

| Belirti | Neden |
|---|---|
| Android `DEVELOPER_ERROR` / `[16] Account reauth failed` | O yüklemenin SHA-1'i Android istemcilerinde yok (en sık: Play App Signing unutulmuş) |
| Supabase 400 `Unacceptable audience` | Token'ın `aud`'u Supabase Client IDs listesinde yok |
| iOS `nonce mismatch` / `Passed nonce and nonce in id_token should either both exist or not` | Skip nonce check kapalı |
| iOS'ta Google sayfası açılıp uygulamaya dönmüyor | Info.plist'te ters kimlik yok ya da yanlış |
| "Bu uygulama doğrulanmadı" ekranı / yalnızca bazı hesaplar girebiliyor | OAuth izin ekranı hâlâ "Testing" durumunda |
| Düğme hiç görünmüyor | `GOOGLE_WEB_CLIENT_ID` derlemeye verilmemiş (secret yok ya da build secret'tan önce koştu) |

---

## Yeni oturuma yapıştırılacak başlangıç mesajı

```
docs/GOOGLE_GIRIS_KURULUM.md'yi oku ve Google ile giriş kurulumunu benimle
adım adım tamamla. Her adımda bana tek iş ver, "yaptım" deyince sonrakine geç.
[SEN] adımlarında Google Cloud / Supabase / Play Console ekranında neye
tıklayacağımı söyle; ekran görüntüsü atarsam ona göre yönlendir. [CLAUDE]
adımlarını kendin yap. Durum: ilk AAB kapalı teste yüklendi mi → <evet/hayır>.
```
