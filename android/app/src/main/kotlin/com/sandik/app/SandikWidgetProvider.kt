package com.sandik.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

/**
 * Ana ekran widget'ı — portföy özeti.
 *
 * Veriyi Flutter tarafı yazar (`HomeWidgetService`), burada yalnızca okunur.
 * `HomeWidgetPlugin.getData` paketin paylaşımlı `SharedPreferences`'ını verir;
 * anahtar adları Dart tarafındaki sabitlerle BİREBİR aynı olmalıdır.
 *
 * Widget kendi başına ağa çıkmaz ve fiyat çekmez: veri yalnızca uygulama
 * açıkken tazelenir. Bu yüzden son güncelleme saati gösterilir — kullanıcı
 * baktığı sayının ne kadar taze olduğunu bilmeli.
 */
class SandikWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // Receiver içinde atılan HERHANGİ bir istisna "Unable to start
        // receiver" ile TÜM UYGULAMAYI düşürür — kullanıcı widget yüzünden
        // uygulamanın çöktüğünü görür. Widget ikincil bir yüzeydir; hata
        // durumunda sessizce eski görünümü koruması doğrusudur.
        try {
            renderAll(context, appWidgetManager, appWidgetIds)
        } catch (e: Exception) {
            // Yutulur: bir sonraki güncellemede yeniden denenir.
        }
    }

    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val data = HomeWidgetPlugin.getData(context)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sandik_widget)

            val hasData = data.getBoolean("sandik_has_data", false)

            if (hasData) {
                val total = data.getString("sandik_total", "") ?: ""
                val change = data.getString("sandik_change", "") ?: ""
                val isPositive = data.getBoolean("sandik_is_positive", true)
                val updatedAt = data.getString("sandik_updated_at", "") ?: ""

                views.setTextViewText(R.id.widget_total, total)
                views.setTextViewText(R.id.widget_change, change)
                views.setTextViewText(R.id.widget_updated, updatedAt)

                // Kâr/zarar rengi — moda duyarlı kaynaklardan okunur.
                val changeColor = if (isPositive) {
                    context.getColor(R.color.widget_gain)
                } else {
                    context.getColor(R.color.widget_loss)
                }
                views.setTextColor(R.id.widget_change, changeColor)

                // Gün içi grafik. Flutter tarafı PNG'yi diske yazar ve yolunu
                // paylaşımlı depoya koyar; iki noktadan az veri varsa çizim
                // yapılmaz (tek noktalı "çizgi" yanıltıcı olurdu) ve alan
                // tamamen gizlenir — boş bir kutu bırakmak kartı bozardı.
                val sparkPath = data.getString("sandik_sparkline", null)
                val sparkPoints = data.readIntCompat("sandik_spark_points")
                val bitmap = if (sparkPoints >= 2 && sparkPath != null) {
                    decodeIfExists(sparkPath)
                } else {
                    null
                }
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.widget_spark, bitmap)
                    views.setViewVisibility(R.id.widget_spark, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_spark, View.GONE)
                }
            } else {
                // Oturum yok / veri temizlenmiş: bakiye YERİNE yönlendirme.
                // Boş bırakmak "portföyüm sıfırlandı" gibi okunuyordu.
                views.setTextViewText(
                    R.id.widget_total,
                    context.getString(R.string.widget_empty)
                )
                views.setTextViewText(R.id.widget_change, "")
                views.setTextViewText(R.id.widget_updated, "")
                views.setViewVisibility(R.id.widget_spark, View.GONE)
            }

            // Widget'a dokunmak uygulamayı açar.
            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
            if (launch != null) {
                val pending = PendingIntent.getActivity(
                    context,
                    0,
                    launch,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_total, pending)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Sparkline PNG'sini okur. Dosya yoksa/bozuksa null döner.
     *
     * Dosya yolu Flutter tarafından yazılır ama widget güncellemesi ile
     * dosyanın diske inmesi arasında yarış olabilir (ya da uygulama verisi
     * temizlenmiş olabilir); bu yüzden varlık kontrolü ve decode hatası
     * ayrı ayrı ele alınır. Grafik ikincildir — çizilemezse widget yine
     * tutarı gösterir.
     */
    private fun decodeIfExists(path: String): Bitmap? = try {
        val file = File(path)
        if (file.exists()) BitmapFactory.decodeFile(path) else null
    } catch (e: Exception) {
        null
    }
}

/**
 * Sayısal bir değeri tipten bağımsız okur.
 *
 * **Neden gerekli:** `home_widget` Dart tarafındaki `saveWidgetData<int>`
 * çağrısını Android'de `Integer` olarak yazar. Burada `getLong` çağırmak
 * `ClassCastException` fırlatır ve bu bir BroadcastReceiver içinde
 * gerçekleştiği için TÜM UYGULAMAYI düşürür ("Unable to start receiver").
 *
 * `SharedPreferences`'ın tipli getter'ları bu dönüşümü yapmaz, bu yüzden
 * ham değeri alıp `Number` üzerinden çeviriyoruz. Böylece paket ileride
 * Long yazmaya geçse de kod ayakta kalır.
 */
private fun android.content.SharedPreferences.readIntCompat(key: String): Int =
    try {
        when (val raw = all[key]) {
            is Number -> raw.toInt()
            is String -> raw.toIntOrNull() ?: 0
            else -> 0
        }
    } catch (e: Exception) {
        0
    }
