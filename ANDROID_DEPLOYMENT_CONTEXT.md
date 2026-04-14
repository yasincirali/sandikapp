# Android Deployment Context

## Project Overview
**Project Name**: PortfoyTakip  
**Type**: Flutter Mobile Application  
**Platform**: Cross-platform (iOS & Android)  
**Purpose**: Portfolio tracking and asset management application

## Project Structure

### Core Directories
- **lib/**: Main Flutter application source code
  - `main.dart`: Application entry point
  - `models/`: Data models (Asset, AssetType)
  - `providers/`: State management (PortfolioProvider)
  - `screens/`: UI screens (AddAssetScreen, AssetDetailScreen, HomeScreen)
  - `services/`: Business logic (DatabaseService, PriceService)
  - `widgets/`: Reusable UI components (AssetRowWidget, PortfolioSummaryWidget)

- **android/**: Android-specific configuration and native code
  - `app/`: Main Android app module with build configuration
  - `gradle/`: Gradle wrapper and build tools
  - Build files: `build.gradle.kts`, `settings.gradle.kts`

- **ios/**: iOS-specific configuration
- **test/**: Widget and integration tests

## Key Models & Services

### Asset Models
- **AssetType**: Enum for asset categories (stock, crypto, real estate, etc.)
- **Asset**: Main asset model with properties like symbol, quantity, purchase price

### Services
- **DatabaseService**: Handles local data persistence (SQLite via sqflite)
- **PriceService**: Fetches real-time price data for assets

### State Management
- **PortfolioProvider**: Manages portfolio state and business logic

## Android Configuration

### Target Platform
- **Android API Level**: 35 (Android 15)
- **Device**: Google Pixel 8 (emulator)
- **ABI**: x86_64

### Build Configuration
- Gradle 8.x with Kotlin DSL
- Android Gradle Plugin
- Flutter integration via Android plugin registry

### Dependencies
- SQLite support (sqflite_android)
- Flutter android bindings
- Native asset support

## Deployment Strategy

### Development Environment
1. Android Emulator: `sdk gphone64 x86 64` (API 35)
2. Device ID: `emulator-5554`
3. Hot reload/restart enabled for rapid development

### Testing Points
- Asset creation and CRUD operations
- Portfolio summary calculations
- Price updates and data synchronization
- Database persistence
- UI responsiveness across different screen sizes

## Common Development Tasks

### Running the App
```bash
flutter run -d emulator-5554
```

### Building APK for Distribution
```bash
flutter build apk --release
```

### Building App Bundle for Google Play
```bash
flutter build appbundle --release
```

### Debugging
- Use Android Studio/VS Code debugger
- Check logs with: `flutter logs`
- Use DevTools at: `http://localhost:9100`

## Dependencies to Monitor
- **sqflite**: Local database (Android support via sqflite_android)
- **provider**: State management
- **http**: Network requests for price service
- Any platform-specific permissions needed for Android

## Known Issues & Considerations
- Ensure Android SDK is properly installed and configured
- May need to accept Android SDK licenses
- Emulator startup time can be significant on first launch
- Hot reload works best with stateless changes; use hot restart for state changes

## Next Steps for Enhancement
1. Implement proper error handling and user feedback
2. Add data validation for asset inputs
3. Implement refresh mechanisms for price updates
4. Add offline capability with sync when online
5. Optimize database queries for large portfolios
