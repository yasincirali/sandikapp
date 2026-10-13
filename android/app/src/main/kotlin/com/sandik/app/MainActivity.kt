package com.sandik.app

import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.WindowManager
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

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
        ocrKanaliniKur(flutterEngine)

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

    /**
     * Ekran görüntüsünden metin satırları → Dart (`ekran_okuyucu.dart`,
     * bayrak `ekran_goruntusu_maliyet`, 2026-10-13). ML Kit Latin modeli
     * (Play hizmetleri), görüntü cihazdan çıkmaz. iOS karşılığı
     * `AppDelegate.swift` `OcrChannel`; dönen biçim aynı: satır metni `t`,
     * kutu `l/u/r/b` (piksel, sol üst başlangıç), kelimeler `k`.
     */
    private fun ocrKanaliniKur(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sandik.app/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "oku") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bayt = call.arguments as? ByteArray
                val gorsel = bayt?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                if (gorsel == null) {
                    result.error("gorsel", null, null)
                    return@setMethodCallHandler
                }
                val tanici = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                tanici.process(InputImage.fromBitmap(gorsel, 0))
                    .addOnSuccessListener { metin ->
                        val satirlar = ArrayList<Map<String, Any>>()
                        for (blok in metin.textBlocks) {
                            for (satir in blok.lines) {
                                val k = satir.boundingBox ?: continue
                                val kelimeler = ArrayList<Map<String, Any>>()
                                for (e in satir.elements) {
                                    val ek = e.boundingBox ?: continue
                                    kelimeler.add(
                                        mapOf(
                                            "t" to e.text,
                                            "l" to ek.left.toDouble(),
                                            "u" to ek.top.toDouble(),
                                            "r" to ek.right.toDouble(),
                                            "b" to ek.bottom.toDouble(),
                                        )
                                    )
                                }
                                satirlar.add(
                                    mapOf(
                                        "t" to satir.text,
                                        "l" to k.left.toDouble(),
                                        "u" to k.top.toDouble(),
                                        "r" to k.right.toDouble(),
                                        "b" to k.bottom.toDouble(),
                                        "k" to kelimeler,
                                    )
                                )
                            }
                        }
                        tanici.close()
                        result.success(satirlar)
                    }
                    .addOnFailureListener {
                        tanici.close()
                        // Model henüz inmemiş olabilir; Dart "okunamadı" der.
                        result.error("ocr", null, null)
                    }
            }
    }
}
