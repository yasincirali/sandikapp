package com.sandik.app

import android.os.Bundle
import android.view.WindowManager
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterFragmentActivity

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

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        flutterReady = true
    }
}
