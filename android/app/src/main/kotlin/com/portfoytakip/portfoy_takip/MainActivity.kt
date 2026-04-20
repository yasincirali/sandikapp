package com.portfoytakip.portfoy_takip

import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Show soft keyboard even when hardware keyboard is present (emulator fix)
        try {
            Settings.Secure.putInt(contentResolver, "show_ime_with_hard_keyboard", 1)
        } catch (_: Exception) {}
    }
}
