package com.sandik.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONObject

/**
 * Ana ekran widget'ı — TEK VARLIK (gram altın, dolar, bir fon…).
 *
 * iOS `SandikVarlikWidget`'ın (c595383, kilit ekranı 579bc98) Android
 * karşılığı; yasin onayı 2026-10-25. Görünüm iOS `systemSmall` ile aynı
 * sırada: ad (+ uzun ad), fiyat, ok + işaretli günlük yüzde, zaman.
 *
 * ## Veri
 * Flutter tarafı yazar (`VarlikWidgetService` →
 * `HomeWidgetService.varlikListesiniYaz`), burada yalnızca okunur. Anahtar
 * iOS ile AYNI (`sandik_varliklar`, JSON `v` = 1): iki platform için ayrı
 * anahtar ya da biçim yok — sözleşme tek, `varlik_widget_sozlesmesi_test`
 * iki okuyucuyu da kilitler. Metinler Dart'ta biçimlenir; burada sayı
 * yeniden biçimlenmez ya da hesaplanmaz. Eksik alan = bilinmiyor ("—").
 *
 * ## Seçim
 * iOS'ta App Intents; burada `SandikVarlikSecimActivity` (widget info
 * `android:configure`). Seçim widget kimliği başına [SECIM_DOSYASI]'nda
 * saklanır — `HomeWidgetPreferences`'a YAZILMAZ: o depo Dart'ındır ve oturum
 * kapanınca temizlenir; kullanıcının widget ayarı ise iOS'taki gibi
 * oturumdan bağımsız durur (yalnız sembol: kişisel veri değil).
 * Seçim yoksa listenin ilki gösterilir (iOS `defaultResult` ile aynı).
 *
 * ## Zaman etiketi (iOS zaman çizelgesinin karşılığı)
 * iOS iki ileri girdiyle (seans sonu, 1 günlük eşik) etiketi uygulama
 * açılmadan çevirir. Android'de girdi yok; aynı anlara tek bir KESİN OLMAYAN
 * alarm (`AlarmManager.set`, RTC — cihazı uyandırmaz, izin istemez) kurulur
 * ve widget yeniden çizilir. Ağa çıkılmaz; yalnız etiket değişir.
 */
class SandikVarlikWidgetProvider : AppWidgetProvider() {

    companion object {
        /**
         * Dokunuş URI'si — iOS `varlikWidgetClickURL` ve Dart
         * `DeepLinkRouter.varlikWidgetHost` ile BİREBİR aynı. Atıf
         * (`widget_tapped.surface = varlik_widget`) ve Portföy sekmesine
         * yönlendirme host'a dayanır. `?homeWidget=1` Android'de gerekmez
         * ama iki platform aynı URI'yi taşısın (gerekçe
         * `SandikWidgetProvider.WIDGET_CLICK_URI`).
         */
        const val VARLIK_WIDGET_CLICK_URI = "sandik://varlik-widget?homeWidget=1"

        /** `HomeWidgetService.kVarliklar` ile birebir aynı. */
        const val KEY_VARLIKLAR = "sandik_varliklar"

        /** Portföy widget'ıyla aynı tema bayrağı. */
        const val KEY_ACIK_TEMA = "sandik_is_light_theme"

        /** Widget kimliği başına seçim (yalnız sembol + son görülen ad). */
        const val SECIM_DOSYASI = "SandikVarlikWidgetSecim"

        /** Fiyat bu kadar eskiyse saatin yerine tarih (iOS `bayatlikEsigi`). */
        const val BAYATLIK_ESIGI_MS = 24L * 60 * 60 * 1000

        fun secimAnahtari(widgetId: Int) = "secim_$widgetId"
        fun secimAdAnahtari(widgetId: Int) = "secim_ad_$widgetId"

        fun secimDeposu(context: Context): SharedPreferences =
            context.getSharedPreferences(SECIM_DOSYASI, Context.MODE_PRIVATE)

        /**
         * Paylaşımlı depodaki paketi okur. Anahtar yoksa, boşsa (oturum
         * kapandı), sürüm tanınmıyorsa ya da çözülemiyorsa boş paket —
         * yanlış okunmuş bir fiyat göstermektense "liste yok" demek doğru.
         */
        fun paketiOku(context: Context): VarlikPaketi {
            return try {
                val metin = HomeWidgetPlugin.getData(context)
                    .getString(KEY_VARLIKLAR, null)
                if (metin.isNullOrEmpty()) VarlikPaketi.BOS
                else VarlikPaketi.coz(metin)
            } catch (e: Exception) {
                VarlikPaketi.BOS
            }
        }

        fun acikTemaMi(context: Context): Boolean = try {
            HomeWidgetPlugin.getData(context).getBoolean(KEY_ACIK_TEMA, false)
        } catch (e: Exception) {
            false
        }

        /**
         * Verilen örnekleri çizer. Seçim ekranı da seçimden hemen sonra bunu
         * çağırır (yayın beklenmez). Receiver/Activity içinde atılan istisna
         * uygulamayı düşürür; widget ikincil yüzeydir, hata yutulur.
         */
        fun ciz(context: Context, manager: AppWidgetManager, widgetIds: IntArray) {
            try {
                val paket = paketiOku(context)
                val paleti = WidgetPaleti(acikTemaMi(context))
                val secim = secimDeposu(context)
                val simdi = System.currentTimeMillis()
                widgetIds.forEach { id ->
                    val durum = durumuBul(paket, secim, id)
                    manager.updateAppWidget(
                        id, gorunum(context, paket, durum, paleti, simdi))
                }
                alarmiKur(context, paket, manager, simdi)
            } catch (e: Exception) {
                // Yutulur: bir sonraki güncellemede yeniden denenir.
            }
        }

        private fun durumuBul(
            paket: VarlikPaketi,
            secim: SharedPreferences,
            widgetId: Int
        ): VarlikDurumu {
            if (paket.ogeler.isEmpty()) return VarlikDurumu.ListeBos
            val secili = secim.getString(secimAnahtari(widgetId), null)
            if (secili.isNullOrEmpty()) return VarlikDurumu.Oge(paket.ogeler.first())
            val oge = paket.ogeler.firstOrNull { it.id == secili }
            if (oge != null) return VarlikDurumu.Oge(oge)
            // Takipten çıkarıldı / satıldı: sessizce başka bir varlığa geçmek
            // yanlış bir fiyatı "seçtiğin" diye gösterirdi.
            return VarlikDurumu.ListedeYok(
                secim.getString(secimAdAnahtari(widgetId), null) ?: secili)
        }

        private fun gorunum(
            context: Context,
            paket: VarlikPaketi,
            durum: VarlikDurumu,
            p: WidgetPaleti,
            simdi: Long
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.sandik_varlik_widget)

            // Zemin ve metin renkleri XML'in ÜSTÜNE basılır: XML kaynak seçimi
            // sistemin moduna bakar, widget uygulamanın tercihini izler
            // (`SandikWidgetProvider.Palette` ile aynı karar).
            views.setInt(R.id.varlik_root, "setBackgroundResource", p.background)
            views.setTextColor(R.id.varlik_ad, context.getColor(p.textPrimary))
            views.setTextColor(R.id.varlik_alt, context.getColor(p.textMuted))
            views.setTextColor(R.id.varlik_fiyat, context.getColor(p.textPrimary))
            views.setTextColor(R.id.varlik_gunluk, context.getColor(p.textMuted))
            views.setTextColor(R.id.varlik_zaman, context.getColor(p.textMuted))
            views.setTextColor(R.id.varlik_bilgi, context.getColor(p.textMuted))

            when (durum) {
                is VarlikDurumu.Oge -> ogeyiBas(context, views, paket, durum.oge, p, simdi)
                is VarlikDurumu.ListedeYok -> bilgiyiBas(
                    views,
                    durum.ad,
                    context.getString(
                        // Yeniden yapılandırma (basılı tut → düzenle) Android
                        // 12'de geldi; altında kaldırıp yeniden eklemek gerekir.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                            R.string.varlik_widget_listede_yok
                        else R.string.varlik_widget_listede_yok_eski
                    )
                )
                VarlikDurumu.ListeBos -> bilgiyiBas(
                    views,
                    context.getString(R.string.widget_brand),
                    context.getString(R.string.varlik_widget_liste_bos)
                )
            }

            // Dokunuş Portföy sekmesini açar. Bütün kart dokunma alanı
            // (portföy widget'ında yalnız tutar satırıydı); küçük widget'ta
            // tek bir hedef var, ≥48 dp kendiliğinden sağlanır.
            val pending = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse(VARLIK_WIDGET_CLICK_URI)
            )
            views.setOnClickPendingIntent(R.id.varlik_root, pending)
            return views
        }

        private fun ogeyiBas(
            context: Context,
            views: RemoteViews,
            paket: VarlikPaketi,
            oge: VarlikOgesi,
            p: WidgetPaleti,
            simdi: Long
        ) {
            views.setViewVisibility(R.id.varlik_icerik, View.VISIBLE)
            views.setViewVisibility(R.id.varlik_bilgi, View.GONE)
            views.setTextViewText(R.id.varlik_ad, oge.ad)
            if (oge.alt.isNullOrEmpty()) {
                views.setViewVisibility(R.id.varlik_alt, View.GONE)
            } else {
                views.setTextViewText(R.id.varlik_alt, oge.alt)
                views.setViewVisibility(R.id.varlik_alt, View.VISIBLE)
            }
            views.setTextViewText(R.id.varlik_fiyat, oge.fiyat ?: "—")

            // Yön yalnız renkle verilmez: ▲/▼ ve işaretli yüzde her zaman
            // yanında. Değişim sıfırsa ya da yön bilinmiyorsa ok yok, ton
            // nötr — düz bir değeri kırmızı göstermek "kaybettim" okunur.
            val degisim = oge.degisim
            if (!degisim.isNullOrEmpty()) {
                val yon = oge.yon ?: 0
                val renk = context.getColor(
                    when {
                        yon > 0 -> p.gain
                        yon < 0 -> p.loss
                        else -> p.textMuted
                    }
                )
                views.setTextViewText(R.id.varlik_degisim, degisim)
                views.setTextColor(R.id.varlik_degisim, renk)
                views.setTextColor(R.id.varlik_ok, renk)
                if (yon != 0) {
                    views.setTextViewText(R.id.varlik_ok, if (yon > 0) "▲" else "▼")
                    views.setViewVisibility(R.id.varlik_ok, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.varlik_ok, View.GONE)
                }
                views.setViewVisibility(R.id.varlik_gunluk, View.VISIBLE)
            } else {
                // Ölçüm yok: yüzde uydurulmaz.
                views.setTextViewText(
                    R.id.varlik_degisim,
                    context.getString(R.string.varlik_widget_degisim_yok)
                )
                views.setTextColor(R.id.varlik_degisim, context.getColor(p.textMuted))
                views.setViewVisibility(R.id.varlik_ok, View.GONE)
                views.setViewVisibility(R.id.varlik_gunluk, View.GONE)
            }

            val zaman = zamanEtiketi(context, paket, oge, simdi)
            if (zaman.isNullOrEmpty()) {
                views.setViewVisibility(R.id.varlik_zaman, View.GONE)
            } else {
                views.setTextViewText(R.id.varlik_zaman, zaman)
                views.setViewVisibility(R.id.varlik_zaman, View.VISIBLE)
            }

            // Tek öğe olarak okunur: "Gram altın, ₺6.123,45, günlük artış
            // +%0,42, 14:05 itibarıyla" — iOS `erisimMetni` ile aynı kalıp.
            views.setContentDescription(
                R.id.varlik_root, erisimMetni(context, paket, oge, simdi))
        }

        private fun bilgiyiBas(views: RemoteViews, baslik: String, metin: String) {
            views.setViewVisibility(R.id.varlik_icerik, View.GONE)
            views.setViewVisibility(R.id.varlik_alt, View.GONE)
            views.setViewVisibility(R.id.varlik_zaman, View.GONE)
            views.setViewVisibility(R.id.varlik_bilgi, View.VISIBLE)
            views.setTextViewText(R.id.varlik_ad, baslik)
            views.setTextViewText(R.id.varlik_bilgi, metin)
            views.setContentDescription(R.id.varlik_root, "$baslik. $metin")
        }

        /**
         * Fiyatın yanındaki zaman bilgisi; yoksa `null` (iOS `zamanEtiketi`,
         * ana ekran boyutu: saat her zaman yazılır).
         *
         * - "Kapanış": Dart yazım anında seansı kapalı buldu (yalnız BIST
         *   takvimindeki türler; kripto/altın/döviz asla). Karar Dart'ta,
         *   burada takvime bakılmaz. Fiyat 1 günden eskiyse tarih eklenir.
         * - Fiyat 1 günden eski: saat yerine tarih ("24 Eki 14:05").
         * - Aksi hâlde yazım saati.
         */
        private fun zamanEtiketi(
            context: Context,
            paket: VarlikPaketi,
            oge: VarlikOgesi,
            simdi: Long
        ): String? {
            val tarihli = paket.bayatMi(simdi) && !paket.tarih.isNullOrEmpty()
            if (oge.kapanis == true) {
                val kapanis = context.getString(R.string.varlik_widget_kapanis)
                return if (tarihli) "$kapanis · ${paket.tarih}" else kapanis
            }
            if (tarihli) return paket.tarih
            return paket.saat?.takeIf { it.isNotEmpty() }
        }

        private fun erisimMetni(
            context: Context,
            paket: VarlikPaketi,
            oge: VarlikOgesi,
            simdi: Long
        ): String {
            val parcalar = mutableListOf(
                oge.ad,
                oge.fiyat ?: context.getString(R.string.varlik_widget_a11y_fiyat_yok)
            )
            if (oge.kapanis == true) {
                parcalar.add(context.getString(R.string.varlik_widget_a11y_kapanis))
            }
            val degisim = oge.degisim
            val yon = oge.yon ?: 0
            parcalar.add(
                when {
                    degisim.isNullOrEmpty() || yon == 0 ->
                        context.getString(R.string.varlik_widget_a11y_degisim_yok)
                    yon > 0 -> context.getString(R.string.varlik_widget_a11y_artis, degisim)
                    else -> context.getString(R.string.varlik_widget_a11y_dusus, degisim)
                }
            )
            val an = if (paket.bayatMi(simdi) && !paket.tarih.isNullOrEmpty()) paket.tarih
                     else paket.saat
            if (!an.isNullOrEmpty()) {
                parcalar.add(context.getString(R.string.varlik_widget_a11y_itibariyla, an))
            }
            return parcalar.joinToString(", ")
        }

        /**
         * Etiketin kendiliğinden değişeceği ilk an: 1 günlük tazelik eşiği.
         * O anda bütün örnekler yeniden çizilir. Gelecekte bir an yoksa
         * bekleyen alarm iptal edilir.
         *
         * `seansSonu` burada an DEĞİL: ana ekran boyutu saati zaten her
         * zaman yazar (iOS `saatHer: true`); seans sonu yalnız kilit
         * ekranının tek satırını değiştiriyordu, Android'de o boyut yok.
         */
        private fun alarmiKur(
            context: Context,
            paket: VarlikPaketi,
            manager: AppWidgetManager,
            simdi: Long
        ) {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            val bilesen = ComponentName(context, SandikVarlikWidgetProvider::class.java)
            val tumu = manager.getAppWidgetIds(bilesen)
            val intent = Intent(context, SandikVarlikWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, tumu)
            }
            val bekleyen = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val esik = paket.zaman?.plus(BAYATLIK_ESIGI_MS)
            if (tumu.isEmpty() || paket.ogeler.isEmpty() || esik == null || esik <= simdi) {
                alarm.cancel(bekleyen)
                return
            }
            // RTC (WAKEUP değil): cihaz uyuyorsa ekran açılınca çizilir —
            // kullanıcının göremeyeceği bir etiket için pil harcanmaz.
            alarm.set(AlarmManager.RTC, esik, bekleyen)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        ciz(context, appWidgetManager, appWidgetIds)
    }

    /** Kaldırılan widget'ın seçimi depoda asılı kalmaz. */
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        try {
            val duzenle = secimDeposu(context).edit()
            appWidgetIds.forEach {
                duzenle.remove(secimAnahtari(it))
                duzenle.remove(secimAdAnahtari(it))
            }
            duzenle.apply()
        } catch (e: Exception) {
            // Yalnız temizlik: kalırsa yeni bir kimlikle çakışmaz.
        }
    }
}

/** Bir widget örneğinin göstereceği şey (iOS `SandikVarlikEntry.Durum`). */
sealed class VarlikDurumu {
    /** Seçili (ya da varsayılan: listenin ilki) varlık. */
    data class Oge(val oge: VarlikOgesi) : VarlikDurumu()

    /** Seçilen varlık artık listede değil (takipten çıkarıldı / satıldı). */
    data class ListedeYok(val ad: String) : VarlikDurumu()

    /** Uygulama henüz liste yazmadı ya da oturum kapalı. */
    object ListeBos : VarlikDurumu()
}

/** Seçim listesindeki bir varlık — Dart `VarlikWidgetOgesi.toJson`. */
data class VarlikOgesi(
    /** Kotasyon sembolü (`ALTIN_GRAM24`, `TEFAS:AFT`) — seçimin kimliği. */
    val id: String,
    val ad: String,
    val alt: String?,
    val fiyat: String?,
    val degisim: String?,
    /** 1 artış, -1 düşüş, 0 değişim yok; `null` bilinmiyor. */
    val yon: Int?,
    /** Yazım anında seans kapalıydı: fiyat son kapanış (karar Dart'ta). */
    val kapanis: Boolean?,
)

/** `sandik_varliklar` paketi — Dart `varlikWidgetPaketi`. */
data class VarlikPaketi(
    val saat: String?,
    val ogeler: List<VarlikOgesi>,
    /** Yazım anı (epoch ms) ve biçimli hâli; eski pakette yok. */
    val zaman: Long?,
    val tarih: String?,
) {
    /** Fiyat 1 günden eski mi? Yazım anı bilinmiyorsa hayır. */
    fun bayatMi(simdi: Long): Boolean {
        val z = zaman ?: return false
        return simdi - z >= SandikVarlikWidgetProvider.BAYATLIK_ESIGI_MS
    }

    companion object {
        /** Bu build'in tanıdığı tek biçim sürümü (iOS `SandikVarlikPaketi.surum`). */
        const val SURUM = 1

        val BOS = VarlikPaketi(null, emptyList(), null, null)

        /** Tanınmayan sürüm ya da bozuk JSON: boş paket. */
        fun coz(metin: String): VarlikPaketi {
            val kok = JSONObject(metin)
            if (kok.optInt("v", -1) != SURUM) return BOS
            val dizi = kok.optJSONArray("ogeler") ?: return BOS
            val ogeler = mutableListOf<VarlikOgesi>()
            for (i in 0 until dizi.length()) {
                val o = dizi.optJSONObject(i) ?: continue
                val id = o.metin("id") ?: continue
                val ad = o.metin("ad") ?: continue
                ogeler.add(
                    VarlikOgesi(
                        id = id,
                        ad = ad,
                        alt = o.metin("alt"),
                        fiyat = o.metin("fiyat"),
                        degisim = o.metin("degisim"),
                        yon = if (o.has("yon") && !o.isNull("yon")) o.optInt("yon") else null,
                        kapanis = if (o.has("kapanis") && !o.isNull("kapanis"))
                            o.optBoolean("kapanis") else null,
                    )
                )
            }
            return VarlikPaketi(
                saat = kok.metin("saat"),
                ogeler = ogeler,
                zaman = if (kok.has("zaman") && !kok.isNull("zaman"))
                    kok.optLong("zaman") else null,
                tarih = kok.metin("tarih"),
            )
        }
    }
}

/**
 * Alan yoksa ya da JSON `null` ise `null`. `optString` yok alanda "" ve
 * `null` değerde "null" metnini döndürür — ikisi de "—" yerine ekrana
 * düşerdi.
 */
private fun JSONObject.metin(ad: String): String? =
    if (has(ad) && !isNull(ad)) optString(ad).takeIf { it.isNotEmpty() } else null

/**
 * Widget paleti — uygulamanın SEÇİLİ temasına göre (`sandik_is_light_theme`).
 * Kaynaklar `values/widget_palette.xml`; portföy widget'ının paletiyle aynı
 * renk adları (`SandikWidgetProvider.Palette`). Seçim ekranı da bunu okur:
 * widget ile ayar ekranı aynı temada görünür.
 */
class WidgetPaleti(val acik: Boolean) {
    val background = if (acik) R.drawable.widget_background_light
                     else R.drawable.widget_background_dark
    val bg = if (acik) R.color.widget_bg_light else R.color.widget_bg_dark
    val textPrimary = if (acik) R.color.widget_text_primary_light
                      else R.color.widget_text_primary_dark
    val textMuted = if (acik) R.color.widget_text_muted_light
                    else R.color.widget_text_muted_dark
    val gain = if (acik) R.color.widget_gain_light else R.color.widget_gain_dark
    val loss = if (acik) R.color.widget_loss_light else R.color.widget_loss_dark
    val gold = if (acik) R.color.widget_gold_light else R.color.widget_gold_dark
    val hairline = if (acik) R.color.widget_hairline_light
                   else R.color.widget_hairline_dark
}
