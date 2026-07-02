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

### Emülatör Başlatma Prosedürü
"Emülatörde ayağa kaldır" istendiğinde bu adımları izle:
1. `flutter emulators --launch pixel7_1` ve `flutter emulators --launch pixel7_2`
2. Her AVD config.ini dosyasında `hw.keyboard = yes` olduğunu doğrula (aksi halde klavye çalışmaz)
   - Config yolu: `C:\Users\vasin\.android\avd\<name>.avd\config.ini`
   - `no` ise: `adb -s <id> emu kill` → config düzelt → yeniden başlat
3. `flutter build apk --debug`
4. `flutter install --device-id emulator-5554 --debug`
5. `flutter install --device-id emulator-5556 --debug`

**adb yolu:** `C:\Users\vasin\Android\sdk\platform-tools\adb.exe`

**Not:** pixel7_1 ve pixel7_2 AVD'lerinde `hw.keyboard = yes` 2026-05-09 tarihinde düzeltildi.

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
