import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase pluginleri — yalnızca google-services.json varsa apply edilir.
// Setup henüz yapılmadıysa build kırılmaz; sen `flutterfire configure`
// komutunu çalıştırınca otomatik aktive olurlar.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.sandik.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.sandik.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties YOKSA RELEASE BUILD KIRILIR. Eski davranış debug
            // anahtarına sessizce düşmekti: `flutter build apk --release`
            // herkesin bildiği debug anahtarıyla imzalı, dağıtılabilir bir APK
            // üretiyordu ve hiçbir uyarı vermiyordu. Yerelde release denemek
            // için android/key.properties oluştur (bkz. YAPMAN_GEREKENLER §6).
            //
            // Denetim EXECUTION aşamasında (doFirst): configuration aşamasında
            // atılan exception `assembleDebug`'ı da kırar, çünkü Gradle hangi
            // görev istenirse istensin TÜM buildTypes bloğunu değerlendirir.
            // Bu hâliyle debug build key.properties'siz ortamlarda (CI, yeni
            // klon) çalışır; yalnızca release imzalanırken durur.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

// Release imzalama kapısı — yukarıdaki release bloğunun execution ayağı.
// Görev GERÇEKTEN koşarken denetler, yapılandırma okunurken değil.
tasks.matching { it.name.contains("Release") && it.name.startsWith("package") }
    .configureEach {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "android/key.properties bulunamadı — release build debug " +
                    "anahtarıyla imzalanmaz. Keystore'u kur ya da debug build al."
                )
            }
        }
    }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-splashscreen:1.0.1")
}
