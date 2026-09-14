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
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
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
