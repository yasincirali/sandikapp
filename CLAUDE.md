# Claude Development Guidelines - PortfoyTakip Project

## Project Overview
**Project**: PortfoyTakip (Portfolio Tracking Application)  
**Type**: Flutter Mobile Application (Cross-platform)  
**Status**: Active Development  
**Current Target**: Android Emulator Deployment

## Development Workflow Preferences

### 1. Automated Changes Policy
- **Make all changes automatically** without requesting approval for each modification
- Proceed with implementation decisions based on best practices
- Focus on delivering working solutions that achieve the stated goals

### 2. Review & Approval Process
- All changes will be made first, then presented for user review
- User will review results at the end of the implementation
- Feedback will be incorporated in subsequent iterations

### 3. Communication Style
- Provide clear summaries of what was changed and why
- Include technical details when relevant to understanding the changes
- Highlight any important decisions made during implementation

## Project Structure & Key Areas

### Core Application (lib/)
- **main.dart**: Application entry point and initialization
- **models/**: Data structures (Asset, AssetType)
- **providers/**: State management (PortfolioProvider using Provider package)
- **screens/**: UI screens (AddAssetScreen, AssetDetailScreen, HomeScreen)
- **services/**: Business logic (DatabaseService for sqflite, PriceService for real-time data)
- **widgets/**: Reusable components (AssetRowWidget, PortfolioSummaryWidget)

### Platform-Specific Code
- **android/**: Android configuration, Gradle build files, native integration
- **ios/**: iOS configuration (Swift, Xcode project)

### Testing
- **test/**: Widget and integration tests
- Need to ensure tests pass before deployment

## Current Development Context

### Active Tasks
1. Running application on Android emulator (API 35, emulator-5554)
2. Testing core functionality on mobile platform
3. Validating UI/UX on Android devices

### Build Configuration Status
- ✅ Flutter project initialized
- ✅ Android emulator created and running
- ✅ Android Gradle configuration in place
- ✅ Sqflite database support configured

### Deployment Target
- **Platform**: Android
- **Emulators**: pixel7_1 (emulator-5554) ve pixel7_2 (emulator-5556) — her ikisine deploy edilir
- **Development Mode**: Debug with hot reload/restart enabled

### Emülatör Dağıtımı — PUSH ÖNCESİ (her tur değil)

```bash
bash tool/deploy_emulators.sh
```

**Ne zaman koşulur (2026-08-11 kararı):** Tam paket + APK build iterasyonu
yavaşlattığı için feature/bugfix turlarında ATLANIR. Şu üç durumda koşulur:
- Push / commit öncesi (regresyon kapısı),
- Kullanıcı görsel doğrulama ya da "emülatöre at" istediğinde,
- Bir dizi değişikliğin sonunda, iş tamamlandığında.

**Feature turunda bunun yerine:** `flutter analyze` + yalnızca o turda
yazılan/etkilenen test dosyası (`flutter test test/<dosya>.dart`).
Testler yine YAZILIR — sadece tam paket her turda koşulmaz.

**flutter yolu:** `/c/flutter/bin/flutter` (PATH'te yok, Bash aracıyla çağır).

Betik sırayla: analyze → test → build → install (bağlı tüm emülatörlere)
→ başlat → çökme kontrolü. Herhangi bir adım kırılırsa **durur**; kırık APK
emülatöre gitmez.

**Emülatörler kapalıysa** önce:
`flutter emulators --launch pixel7_1` ve `... pixel7_2`

**⚠️ Bu emülatörler Flutter'ı RENDER EDEMİYOR.** Ekran görüntüsü tamamen
siyah gelir (doğrulandı 2026-08-09; süreç yaşıyor, Supabase init oluyor,
FATAL yok — yalnızca sunum katmanı okunamıyor). Betik **"çalışıyor mu"**
sorusunu yanıtlar, **"doğru görünüyor mu"** sorusunu yanıtlamaz.
Görsel doğrulama gerçek cihazda veya widget testiyle yapılır.

**⚠️ Disk dolması:** debug APK ~215 MB ve kurulum sırasında iki katı yer
ister. `/data` %90'ı geçince `INSTALL_FAILED_INSUFFICIENT_STORAGE` gelir.
`pm clear` ve `uninstall` yetmez — AVD'yi sıfırla:
```bash
adb -s emulator-5556 emu kill
"C:/Users/vasin/Android/sdk/emulator/emulator.exe" -avd pixel7_2 -wipe-data
```
Wipe sonrası `hw.keyboard = yes` korunur (doğrulandı).

**adb yolu:** `C:\Users\vasin\Android\sdk\platform-tools\adb.exe`

**Not:** pixel7_1 ve pixel7_2 AVD'lerinde `hw.keyboard = yes` 2026-05-09 tarihinde düzeltildi.

## Kod Belleği: codebase-memory-mcp

Proje `.mcp.json` üzerinden `codebase-memory-mcp` (v0.9.0) MCP sunucusuna bağlıdır.
Binary: `C:\Users\vasin\AppData\Local\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
Proje adı (graph içinde): `C-projects-PortfoyTakip`

Kurulum **sadece proje kapsamlıdır** — global `~/.claude.json`, hook veya skill kurulmadı.

### Kullanım kuralları
- Kod keşfinde önce graph sorgusu yap (`search_graph`, `query_graph`, `trace_path`,
  `get_architecture`), geniş `Grep`/`Glob` taramalarına sonra düş. Token maliyeti çok daha düşük.
- Mimari kararlar `manage_adr` içinde saklanır — oturumlar arası kalıcıdır.
  Mimari bir karar değiştiğinde `manage_adr --mode update` ile güncelle.
- Büyük değişikliklerden sonra indeksi tazele:
  `codebase-memory-mcp cli index_repository --repo-path "c:\projects\PortfoyTakip"`
- `detect_changes` commit edilmemiş değişiklikleri etkilenen sembollere eşler.

### CLI notları
- Ham JSON argümanı **deprecated** — flag kullan (`--repo-path`, `--project`, `--mode`).
  Uzun/Türkçe içerik için `--args-file <path.json>`.
- `cli` modu daemon başlatmaz; tek seferlik sorgular için güvenlidir.
- PowerShell'de stderr'deki `level=info` logları NativeCommandError olarak görünür; zararsızdır.

### Bilinen kapsam notu
Repo kökündeki `PortfoyTakip/*.swift` dosyaları eski SwiftUI prototipidir ve indekse dahil olur.
Aktif kod `lib/` altındadır.

## UI/UX Referans: ui-ux-pro-mcp

Proje `.mcp.json` üzerinden `ui-ux-pro-mcp` (npm global) MCP sunucusuna bağlıdır.
Binary: `C:\Users\vasin\AppData\Roaming\npm\ui-ux-pro-mcp.cmd` (global install).

**İçerik (sunucunun başlangıçta raporladığı indeksler):** 103 style, 119 renk,
74 tipografi, 36 chart, 170 UX guideline, 175 ikon, 75 landing pattern,
116 ürün, 39 prompt, 12 stack, 2 platform (iOS HIG + Android Material 3).
Her platform pattern'i Flutter + React Native eşdeğerlerini içerir.

### Kullanım kuralları
- Yeni ekran/komponent tasarlarken önce ilgili MCP tool'unu (`search_ui`,
  `get_platform_guidelines` vb.) sorgula. Marka rengini/tonunu koru,
  yerleşim + hierarchy önerilerini adapte et.
- iOS TestFlight için özel deneyim değişiklikleri istendiğinde HIG'e bak;
  bir Sandık ekranı hem iOS'ta hem Android'de doğal hissetsin diye
  cross-platform equivalents'a başvur.
- Bu MCP jenerik design bilgisi verir — Sandık marka renkleri
  (amber/gold/gain/loss/surface) ve DM Sans typography ayrıştırılmalı;
  MCP'nin verdiği renk paletlerini olduğu gibi almayın.

## Dart/Flutter Araçları: dart MCP

Proje `.mcp.json` üzerinden resmî Dart MCP sunucusuna bağlıdır:
`dart mcp-server --force-roots-fallback`

Statik analiz, test çalıştırma, pub işlemleri ve Dart-farkındalıklı düzenlemeler
için kullanılır. `flutter analyze` / `flutter test` çıktısını ham kabuk komutu
olarak ayrıştırmak yerine bu sunucunun tool'larını tercih et — sonuçlar yapılandırılmış
gelir ve dosya/satır referansları doğrudan kullanılabilir.

**Not:** `--force-roots-fallback` bayrağı, istemci workspace root'larını
bildirmediğinde sunucunun proje kökünü kendi bulabilmesi için gereklidir; kaldırma.

## Teknik Borç Defteri

Ertelenmiş **kod** kararları `TECHNICAL_DEBT.md`'de tutulur — neden ertelendi,
ertelemenin maliyeti ne, ne zaman ele alınmalı. Yeni bir borç ertelendiğinde
oraya yaz; kapandığında "KAPANDI" tablosuna commit hash'iyle taşı.

Kullanıcının elden yapacağı işler (store formları, keystore, hukuki adımlar)
oraya DEĞİL, `YAPMAN_GEREKENLER.md`'ye gider.

## Areas for Automated Improvements

### Code Quality
- Apply Dart formatting (dartfmt)
- Run Dart analysis for code issues
- Implement proper error handling
- Add meaningful comments for complex logic

### Functionality
- Ensure all CRUD operations work correctly
- Validate data persistence in local database
- Test portfolio calculations
- Verify price update mechanisms

### UI/UX
- Responsive design for different screen sizes
- Proper state management and updates
- Error message displays to users
- Loading states during data operations

### Testing
- Create/update widget tests for components
- Add integration tests for workflows
- Ensure test coverage for critical features

## Approval Thresholds

### No Approval Needed (Go Ahead Automatically)
- Code formatting and linting fixes
- Bug fixes and error handling improvements
- Documentation updates
- Comments and code clarity enhancements
- Refactoring for better code organization
- Adding/updating tests
- Performance optimizations
- Dependency updates (minor/patch versions)

### Review Recommended (But You Can Proceed)
- New feature implementation
- Major refactoring that changes architecture
- API/service integration changes
- Database schema modifications
- Breaking changes to existing functionality
- Major dependency upgrades

### Critical Review (Proceed But Flag It)
- Removing core functionality
- Changing database structure significantly
- Modifying authentication/security logic
- Large-scale architectural changes

## Success Criteria for Current Phase
1. ✅ App successfully builds and deploys to Android emulator
2. App launches without crashes
3. Core features (add asset, view portfolio, see summary) work correctly
4. Data persists correctly in database
5. UI displays properly on Android screen

## Development Notes
- Prefer using Flutter best practices and official documentation
- Maintain consistency with existing code style
- Keep components as simple and reusable as possible
- Ensure proper state management throughout the app
- Add descriptive commit messages for any version control changes

---
**Last Updated**: April 13, 2026  
**Created For**: Automated Development Workflow with Review-Based Approval
