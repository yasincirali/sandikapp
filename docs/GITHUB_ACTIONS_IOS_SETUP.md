# iOS TestFlight — GitHub Actions Kurulum Rehberi

> Codemagic'ten GitHub Actions'a geçiş. Windows'ta yaşayan geliştirici için: Mac gerekmez, tüm build GitHub'ın macOS runner'ında olur.

## Genel akış

1. **Match cert repo aç** (bir kere)
2. **GitHub secrets doldur** (bir kere, 10 tane)
3. **Setup-match workflow tetikle** (bir kere → sertifika + profil üretilir)
4. **Sonraki her push** → otomatik TestFlight upload

---

## 1. Cert Repo Oluştur

GitHub'da yeni **private** repo aç:
- Ad: `sandikapp-ios-certs`
- Visibility: **Private** (kritik — sertifikalar burada şifreli tutulacak)
- README eklemene gerek yok, boş bırak

URL'i not al: `https://github.com/yasincirali/sandikapp-ios-certs.git`

## 2. GitHub Personal Access Token (Match için)

Bu token cert repo'ya yazma yetkisi verir.

1. github.com → Sağ üstte profil → **Settings**
2. Sol menü en altta → **Developer settings**
3. **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**
4. Ayarlar:
   - Note: `sandikapp match cert repo access`
   - Expiration: `No expiration` (veya 1 yıl)
   - Scopes: sadece `repo` (tümü)
5. **Generate token** → **kopyala, kaybolursa bir daha görüntülenmez**

Ardından base64 encode et — Windows PowerShell'de:

```powershell
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("x-access-token:GITHUB_PAT_BURAYA"))
```

Çıkan uzun string'i `MATCH_GIT_BASIC_AUTH` secret'ı olarak kullanacaksın.

## 3. Match Password (şifreleme parolası)

Sertifikalar cert repo'ya bu parolayla şifreli yazılır. Güçlü rastgele bir string üret (min 20 karakter). **Kaybedersen sertifikalar açılamaz** — parola yöneticine kaydet.

## 4. App Store Connect API Key

Elinde `.p8` dosyası zaten var (dedin). Üç değeri hazırla:

- **ASC_KEY_ID**: `.p8` dosya adının içindeki 10 karakterlik ID (örn. `AuthKey_ABC1234567.p8` → `ABC1234567`)
- **ASC_ISSUER_ID**: App Store Connect → Users and Access → Integrations → App Store Connect API sayfasının üstünde, UUID formatında
- **ASC_KEY_CONTENT**: `.p8` dosyasının tam içeriği (BEGIN/END PRIVATE KEY dahil, tırnaksız düz metin)

**Dikkat:** GitHub secret'a yazarken newline'lar korunmalı. GitHub UI çok satırlı secret'ı doğru saklıyor — sadece dosyayı bir editorde aç, `Ctrl+A`, `Ctrl+C`, GitHub secret input'una yapıştır.

## 5. Apple Kimlikleri

- **APPLE_ID**: `sandikapp.destek@gmail.com` (App Store Connect login e-posta)
- **APPLE_TEAM_ID**: Apple Developer üyeliğinden gelen 10 karakterlik team ID. developer.apple.com → Membership sayfasında görünür.
- **ITC_TEAM_ID**: App Store Connect team ID. Genelde APPLE_TEAM_ID ile aynı ama farklı olabilir. Fastlane spaceship ile bakabilir; şimdilik APPLE_TEAM_ID ile aynısını dene, farklıysa hata mesajı doğrusunu söyler.

## 6. Supabase Kimlikleri

- **SUPABASE_URL**: `.env.local` içindeki değer
- **SUPABASE_ANON_KEY**: `.env.local` içindeki değer

## 7. Firebase Config

- **GOOGLE_SERVICE_INFO_PLIST_BASE64**: `ios/Runner/GoogleService-Info.plist` dosyasının base64'ü. Windows PowerShell:

  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("ios\Runner\GoogleService-Info.plist"))
  ```

  Çıkan tek satır uzun string'i secret'a yapıştır.

## 8. Tüm Secrets Listesi (GitHub → repo → Settings → Secrets and variables → Actions)

| Secret adı | İçerik |
|---|---|
| `APPLE_ID` | sandikapp.destek@gmail.com |
| `APPLE_TEAM_ID` | Apple Developer team ID (10 char) |
| `ITC_TEAM_ID` | App Store Connect team ID (genelde aynı) |
| `ASC_KEY_ID` | .p8 dosya ID (10 char) |
| `ASC_ISSUER_ID` | ASC API Issuer UUID |
| `ASC_KEY_CONTENT` | .p8 dosya içeriği (BEGIN/END dahil) |
| `MATCH_GIT_URL` | https://github.com/yasincirali/sandikapp-ios-certs.git |
| `MATCH_GIT_BASIC_AUTH` | base64("x-access-token:GITHUB_PAT") |
| `MATCH_PASSWORD` | senin güçlü parolan (min 20 char) |
| `SUPABASE_URL` | .env.local'daki url |
| `SUPABASE_ANON_KEY` | .env.local'daki key |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | plist dosyasının base64'ü |

Toplam: **12 secret**.

## 9. Setup Match'i Tetikle (bir kere)

Tüm secret'lar dolduysa:

1. github.com/yasincirali/sandikapp → **Actions** sekmesi
2. Sol listede **iOS — Setup Match Certificates (one-time)** workflow'unu seç
3. Sağ üstte **Run workflow** → main branch → yeşil **Run workflow** butonu
4. 3-5 dk sürer. Yeşil ✓ olursa:
   - Cert repo'ya bak (`sandikapp-ios-certs`) — `certs/distribution/` ve `profiles/appstore/` klasörleri oluşmuş olmalı
   - App Store Connect → Certificates, IDs & Profiles'da yeni "iOS Distribution" sertifikası ve `com.sandik.app` için provisioning profile görünür

## 10. Test Push

Her şey hazır. Herhangi bir küçük değişiklik yap (örn. `version: 1.1.3+7`) ve push et:

```bash
git commit --allow-empty -m "test: trigger ios-testflight workflow"
git push
```

**Actions** sekmesinde **iOS — TestFlight** workflow'u koşacak. 15-25 dk sonra:
- Yeşilse → App Store Connect → TestFlight → yeni build "1.1.3 (7)" görünür (5-10 dk processing sonrası)
- Kırmızıysa → workflow log'una bak, hatanın 90%'i secret eksikliği veya newline sorunu

## 11. Codemagic'i Kapat

Her şey çalıştığından emin olduktan sonra:

1. codemagic.io → App settings → **Delete application**
2. Aboneliği durdur (varsa)
3. Bu turda `codemagic.yaml` zaten silindi

## Bakım

- **Sertifika 1 yıl sonra expire olur.** Notification alırsan bu rehberin 9. adımını (setup-match tekrar tetikle) çalıştır. `MATCH_READONLY: "false"` olduğu için match yeni cert üretip repo'ya push eder.
- **ASC API key expire olmaz** ama revoke edebilirsin. Ederse yenisini oluştur, `ASC_KEY_*` secret'larını güncelle.
- **CocoaPods versiyonu** — Gemfile'da `cocoapods 1.15+` diyor. Sürüm bump edeceksen orada değiştir; workflow otomatik uyar.

## Troubleshooting

**"No matching profiles found"** → Setup match tekrar tetikle. Muhtemelen Apple Developer console'da capability eklendi (Push Notifications, App Groups vs.) → mevcut profil eski. `readonly: false` ile match yenisini üretir.

**"Value already used"** (build number) → Fastlane `latest_testflight_build_number` çağırıyor. Genelde bu hata `pubspec.yaml`'daki `+N` sayısıyla ASC'nin son build number'ı çakışırsa çıkar. Fix: pubspec'te build number'ı ASC'nin son build number'ından yüksek yap (örn. ASC'de son 12 ise pubspec'te `+13`).

**"Match password incorrect"** → Cert repo'daki dosyalar farklı bir parolayla şifrelendi. Ya doğru parolayı bul ya cert repo'yu boşalt + setup-match tekrar çalıştır.

**"Codesigning error: no valid signing certs found"** → Cert repo'da sertifika yok. Setup match hiç çalışmadı ya da başarısız oldu. Adım 9'a dön.
