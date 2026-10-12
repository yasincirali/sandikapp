package com.sandik.app

import android.os.Bundle
import android.view.WindowManager
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

// FlutterFragmentActivity: local_auth (biyometrik kilit) FragmentActivity ister.
class MainActivity : FlutterFragmentActivity() {
    private var flutterReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { !flutterReady }
        super.onCreate(savedInstanceState)
        firebaseArkaPlanKaydiniSil()
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }

    /**
     * Eski sürümün kaydettiği FCM arka plan işleyicisini siler.
     *
     * Dart tarafı artık `onBackgroundMessage` kaydetmiyor (main.dart,
     * 2026-10-12): kayıtlıyken her arka plan push'u başsız bir Flutter
     * motoru açıyordu, işleyici ise boştu. Ama firebase_messaging kaydı
     * kendi SharedPreferences dosyasında SAKLAR ve güncellemeden sonra da
     * kullanmaya devam ederdi. Anahtarlar eklentinin iç adlarıdır
     * (firebase_messaging 16.2.1, `FlutterFirebaseMessagingUtils
     * .SHARED_PREFERENCES_KEY`); ileride değişirse bu silme yalnızca etkisiz
     * kalır, bir şey bozmaz.
     */
    private fun firebaseArkaPlanKaydiniSil() {
        try {
            getSharedPreferences("io.flutter.firebase.messaging.callback", MODE_PRIVATE)
                .edit()
                .remove("callback_handle")
                .remove("user_callback_handle")
                .apply()
        } catch (e: Exception) {
            // Yalnızca verim: silinemezse eski davranış sürer.
        }
    }

    // onFlutterUiDisplayed() FlutterActivity'nin metodu; FlutterFragmentActivity'de
    // YOK (o yalnızca FlutterEngineProvider + FlutterEngineConfigurator implement
    // eder). İlk kare sinyali bu sınıfta renderer'ın listener'ından alınır.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val renderer = flutterEngine.renderer
        // Listener, renderer çizmeye BAŞLADIKTAN sonra eklenirse hiç çağrılmaz
        // (FlutterUiDisplayListener sözleşmesi) — splash sonsuza dek açık kalırdı.
        if (renderer.isDisplayingFlutterUi) {
            flutterReady = true
            return
        }

        renderer.addIsDisplayingFlutterUiListener(
            object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    flutterReady = true
                    renderer.removeIsDisplayingFlutterUiListener(this)
                }

                override fun onFlutterUiNoLongerDisplayed() = Unit
            }
        )
    }
}
