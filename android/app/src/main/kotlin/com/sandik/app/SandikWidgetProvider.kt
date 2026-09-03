package com.sandik.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.res.ColorStateList
import android.os.Build
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

    /**
     * Widget paleti — uygulamanın SEÇİLİ temasına göre.
     *
     * `values` ↔ `values-night` ayrımı SİSTEMİN karanlık modunu izler;
     * kullanıcı ise uygulama içinde ayrı bir tema seçebiliyor
     * (Sistem / Açık / Koyu). Uygulamayı "Açık" yapıp cihazı koyu bırakan
     * kullanıcıda widget koyu kalıyordu.
     *
     * Karar Dart tarafında verilir ve `sandik_is_light_theme` anahtarıyla
     * çözülmüş bir bool olarak gelir ("Sistem" orada cihazın görünümüne
     * çözülür). Burada yalnızca uygulanır.
     */
    private class Palette(isLight: Boolean) {
        val background = if (isLight) R.drawable.widget_background_light
                         else R.drawable.widget_background_dark
        val textPrimary = if (isLight) R.color.widget_text_primary_light
                          else R.color.widget_text_primary_dark
        val textMuted = if (isLight) R.color.widget_text_muted_light
                        else R.color.widget_text_muted_dark
        val gain = if (isLight) R.color.widget_gain_light
                   else R.color.widget_gain_dark
        val loss = if (isLight) R.color.widget_loss_light
                   else R.color.widget_loss_dark
        val gold = if (isLight) R.color.widget_gold_light
                   else R.color.widget_gold_dark
        val hairline = if (isLight) R.color.widget_hairline_light
                       else R.color.widget_hairline_dark
    }

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

        // Varsayılan KOYU: bayrak henüz yazılmamışsa (eski sürümden gelen
        // kurulum) bugüne kadarki görünüm korunur.
        val palette = Palette(data.getBoolean("sandik_is_light_theme", false))

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.sandik_widget)

            // Zemin ve moda duyarlı metinler XML'deki değerlerin ÜSTÜNE
            // yeniden basılır: XML kaynak seçimi sistemin moduna bakar,
            // biz uygulamanın tercihini istiyoruz.
            views.setInt(R.id.widget_root, "setBackgroundResource", palette.background)
            views.setTextColor(R.id.widget_total, context.getColor(palette.gold))
            views.setTextColor(R.id.widget_date, context.getColor(palette.textMuted))
            views.setTextColor(R.id.widget_updated, context.getColor(palette.textMuted))
            views.setTextColor(
                R.id.widget_change_label, context.getColor(palette.textMuted))
            // Ayraç bir `ImageView`'ın `src`'si; `setColorFilter` ile boyanır
            // (canlılık noktasıyla aynı teknik). Kendi drawable'ı hâlâ
            // `values-night`'a bakıyordu, yani tek başına SİSTEMİ izliyordu.
            views.setInt(
                R.id.widget_divider,
                "setColorFilter",
                context.getColor(palette.hairline)
            )

            val hasData = data.getBoolean("sandik_has_data", false)

            if (hasData) {
                val total = data.getString("sandik_total", "") ?: ""
                val change = data.getString("sandik_change", "") ?: ""
                val changePct = data.getString("sandik_change_pct", "") ?: ""
                val isPositive = data.getBoolean("sandik_is_positive", true)
                val updatedAt = data.getString("sandik_updated_at", "") ?: ""
                val date = data.getString("sandik_date", "") ?: ""
                val marketOpen = data.getBoolean("sandik_market_open", false)

                views.setTextViewText(R.id.widget_total, total)
                views.setTextViewText(R.id.widget_change, change)
                views.setTextViewText(R.id.widget_date, date)

                // Canlılık şeridi — kilit ekranıyla AYNI metin ve kural:
                // "Canlı • 21:51" / "Piyasa kapalı • 21:51". Kullanıcı
                // rakamın neden değişmediğini bilmeli, aksi halde donuk
                // sayı "uygulama bozuk" olarak okunur.
                val durum = context.getString(
                    if (marketOpen) R.string.widget_live
                    else R.string.widget_market_closed
                )
                views.setTextViewText(R.id.widget_updated, "$durum • $updatedAt")

                // Nokta rengi: açıkken gain, kapalıyken gri. Yeşil nokta
                // "veri akıyor" demektir ve gece bu doğru değildir.
                views.setInt(
                    R.id.widget_live_dot,
                    "setColorFilter",
                    context.getColor(
                        if (marketOpen) palette.gain else palette.textMuted
                    )
                )

                // Etiketler yalnızca gerçekten bir rakam varken görünür.
                // Bakiye gizliyken değişim satırı boş gönderilir; etiket
                // tek başına kalırsa kart başlık deyip altını boş bırakır.
                views.setViewVisibility(
                    R.id.widget_change_label,
                    if (change.isEmpty()) View.GONE else View.VISIBLE
                )
                views.setViewVisibility(
                    R.id.widget_divider,
                    if (change.isEmpty()) View.GONE else View.VISIBLE
                )

                // Kâr/zarar rengi — moda duyarlı kaynaklardan okunur.
                //
                // Hareket yoksa NÖTR: sıfır bir yön taşımaz ve kâr/zarar
                // rengi basmak olmayan bir hareketi varmış gibi gösterir.
                // "Değişim yok" yazısı kırmızı görünüyordu.
                val isFlat = data.getBoolean("sandik_is_flat", false)
                val changeColor = when {
                    isFlat -> context.getColor(palette.textMuted)
                    isPositive -> context.getColor(palette.gain)
                    else -> context.getColor(palette.loss)
                }
                views.setTextColor(R.id.widget_change, changeColor)

                // Yön oku — renge EK bir sinyal. Renk körlüğünde de okunur
                // ve kilit ekranındaki ▲/▼ ile aynı işaret kullanılır.
                // Hareket yoksa ok hiç basılmaz.
                views.setTextViewText(
                    R.id.widget_arrow,
                    if (isPositive) "▲" else "▼"
                )
                views.setTextColor(R.id.widget_arrow, changeColor)
                views.setViewVisibility(
                    R.id.widget_arrow,
                    if (isFlat || change.isEmpty()) View.GONE else View.VISIBLE
                )

                // Yüzde rozeti — durum renginin düşük alfalı zemini üstünde.
                // Kilit ekranındaki "+%2,45 Günlük" rozetinin karşılığı.
                views.setTextViewText(R.id.widget_change_pct, changePct)
                views.setTextColor(R.id.widget_change_pct, changeColor)
                // Rozet zemini TINT ile boyanır, `setBackgroundColor` ile
                // DEĞİL: ikincisi yuvarlak köşeli drawable'ı düz bir
                // dikdörtgenle değiştirir ve rozet kilit ekranındakine
                // benzemez. Tint şekli korur, yalnızca rengi sürer.
                // Rozet zemini TINT ile boyanır, `setBackgroundColor` ile
                // DEĞİL: ikincisi yuvarlak köşeli drawable'ı düz bir
                // dikdörtgenle değiştirir ve rozet kilit ekranındakine
                // benzemez. Tint şekli korur, yalnızca rengi sürer.
                //
                // `setColorStateList` API 31'de geldi; altında rozet
                // zemini varsayılan (nötr) kalır — şekli doğru, yalnızca
                // rengi sabit. Metin rengi zaten durumu taşıyor.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    views.setColorStateList(
                        R.id.widget_change_pct,
                        "setBackgroundTintList",
                        ColorStateList.valueOf(
                            // %14 alfa — kilit ekranındaki rozetle aynı.
                            (changeColor and 0x00FFFFFF) or (0x24 shl 24)
                        )
                    )
                }
                views.setViewVisibility(
                    R.id.widget_change_pct,
                    if (changePct.isEmpty()) View.GONE else View.VISIBLE
                )

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
                // Boş durumda tutar alanı bir YÖNLENDİRME metnidir, marka
                // altını değil — okunabilir metin rengine döner.
                views.setTextColor(
                    R.id.widget_total, context.getColor(palette.textPrimary))
                views.setTextViewText(R.id.widget_change, "")
                views.setTextViewText(R.id.widget_updated, "")
                views.setTextViewText(R.id.widget_date, "")
                views.setViewVisibility(R.id.widget_change_label, View.GONE)
                views.setViewVisibility(R.id.widget_change_pct, View.GONE)
                views.setViewVisibility(R.id.widget_arrow, View.GONE)
                views.setViewVisibility(R.id.widget_divider, View.GONE)
                views.setViewVisibility(R.id.widget_live_dot, View.GONE)
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
