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
import org.json.JSONArray
import org.json.JSONObject
import java.math.RoundingMode
import java.net.HttpURLConnection
import java.net.URL
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10

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
 * ve widget yeniden çizilir. Kapsam dışı varlıkta ağa çıkılmaz; yalnız
 * etiket değişir.
 *
 * ## Uygulama açılmadan tazeleme (yasin onayı 2026-10-26; iOS ile aynı)
 * Gösterilen varlık SUNUCU KAPSAMINDAYSA (öğede `sunucu == true`: altın, TL
 * döviz, kripto — karar Dart'ta) aynı kesin olmayan alarm en geç 30 dk
 * sonraya kurulur; `onUpdate` bilinen fiyat 10 dk'dan eskiyse `widget-fiyat`
 * edge function'ını ARKA İŞ PARÇACIĞINDA çağırır (`goAsync`, ana iş
 * parçacığında ağ yok) ve yeniden çizer. Çağrı uygulamanın yazdığı public URL
 * + anon anahtarla yapılır; oturum jetonu YOK. Başarısızsa son bilinen değer
 * saatiyle kalır. Sistem zamanlayıcısı (`updatePeriodMillis`) ve WorkManager
 * KULLANILMAZ: projedeki desen bu alarm; RTC olduğu için ekran kapalıyken
 * cihaz uyandırılmaz, açılınca tazelenir.
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

        /**
         * `HomeWidgetService.kWidgetApiUrl` / `kWidgetApiAnahtar`: aktif
         * sunucunun public URL'si ve anon anahtarı (uygulama yazar).
         */
        const val KEY_API_URL = "sandik_widget_api_url"
        const val KEY_API_ANAHTAR = "sandik_widget_api_anahtar"

        /**
         * `HomeWidgetService.kVarlikCanli`: widget'ın sunucudan çektiği son
         * fiyatlar (`{sembol: {fiyat, zaman, degisim?}}`). Yalnız burada
         * YAZILIR; Dart'ın deposunda durur ki oturum kapanınca boşalsın.
         */
        const val KEY_CANLI = "sandik_varlik_canli"

        /** Sunucu kapsamındaki varlıkta yenileme aralığı (iOS `tazelemeAraligi`). */
        const val TAZELEME_ARALIGI_MS = 30L * 60 * 1000

        /** Bilinen fiyat bundan tazeyse ağa çıkılmaz (iOS `tazeEsigi`). */
        const val TAZE_ESIGI_MS = 10L * 60 * 1000

        /** Son deneme anı — başarısız istek her yayında tekrarlanmasın. */
        private const val KEY_SON_DENEME = "canli_son_deneme"

        /** `widget-fiyat` istek sınırı (sunucudaki `WIDGET_AZAMI_SEMBOL`). */
        private const val AZAMI_SEMBOL = 5

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
                val canli = canliDepo(context)
                val simdi = System.currentTimeMillis()
                widgetIds.forEach { id ->
                    val (gorunen, durum) =
                        canliyiUygula(paket, durumuBul(paket, secim, id), canli)
                    manager.updateAppWidget(
                        id, gorunum(context, gorunen, durum, paleti, simdi))
                }
                alarmiKur(context, paket, manager, simdi)
            } catch (e: Exception) {
                // Yutulur: bir sonraki güncellemede yeniden denenir.
            }
        }

        /**
         * Tüm örneklerde gösterilen ve sunucudan tazelenebilecek semboller
         * (`sunucu == true`), en çok [AZAMI_SEMBOL].
         */
        private fun kapsamdakiSemboller(
            paket: VarlikPaketi,
            secim: SharedPreferences,
            widgetIds: IntArray
        ): List<String> = widgetIds.asList()
            .mapNotNull { (durumuBul(paket, secim, it) as? VarlikDurumu.Oge)?.oge }
            .filter { it.sunucu == true }
            .map { it.id }
            .distinct()
            .take(AZAMI_SEMBOL)

        /**
         * Widget'ın sunucudan çektiği fiyat, uygulamanın yazdığından
         * YENİYSE onu gösterir; zaman etiketi de onun anıdır (iOS
         * `SandikVarlikProvider.oku` ile aynı karar). Sunucu yüzdeyi
         * bilmiyorsa yüzde YOK — uygulamanın eski yüzdesi yeni fiyatın
         * yanında kalmaz (farklı anların sayısı birleşmez).
         */
        private fun canliyiUygula(
            paket: VarlikPaketi,
            durum: VarlikDurumu,
            canli: Map<String, CanliFiyat>
        ): Pair<VarlikPaketi, VarlikDurumu> {
            val oge = (durum as? VarlikDurumu.Oge)?.oge ?: return paket to durum
            if (oge.sunucu != true) return paket to durum
            val c = canli[oge.id] ?: return paket to durum
            val yazim = paket.zaman
            if (yazim != null && c.zaman <= yazim) return paket to durum
            val yuzde = c.degisim?.let { WidgetBicim.yuzde(it) }
            val yeni = oge.copy(
                fiyat = WidgetBicim.fiyat(c.fiyat, oge.hane),
                degisim = yuzde?.first,
                yon = yuzde?.second,
                kapanis = null,
            )
            val gorunen = paket.copy(
                saat = WidgetBicim.saat(c.zaman),
                zaman = c.zaman,
                tarih = WidgetBicim.tarih(c.zaman),
            )
            return gorunen to VarlikDurumu.Oge(yeni)
        }

        /** Widget'ın daha önce çektiği fiyatlar; okunamazsa boş. */
        fun canliDepo(context: Context): Map<String, CanliFiyat> = try {
            val metin = HomeWidgetPlugin.getData(context).getString(KEY_CANLI, null)
            if (metin.isNullOrEmpty()) emptyMap() else CanliFiyat.sozlukCoz(metin)
        } catch (e: Exception) {
            emptyMap()
        }

        /**
         * Gerekiyorsa `widget-fiyat`'tan fiyat çeker, depoya yazar ve
         * örnekleri yeniden çizer — ARKA İŞ PARÇACIĞINDA. [bitince] her
         * durumda (gerek yoksa hemen) çağrılır: `goAsync` sonucunu kapatır.
         *
         * Gerek: gösterilen kapsamdaki bir varlığın bilinen fiyatı
         * [TAZE_ESIGI_MS]'den eski ve son deneme de o kadar eski.
         */
        fun tazele(context: Context, bitince: (() -> Unit)?) {
            val bitir = { try { bitince?.invoke() } catch (e: Exception) {} }
            try {
                val manager = AppWidgetManager.getInstance(context)
                val tumu = manager.getAppWidgetIds(
                    ComponentName(context, SandikVarlikWidgetProvider::class.java))
                val paket = paketiOku(context)
                val secim = secimDeposu(context)
                val semboller = kapsamdakiSemboller(paket, secim, tumu)
                val simdi = System.currentTimeMillis()
                val canli = canliDepo(context)
                val bayat = semboller.filter { s ->
                    val bilinen = maxOf(paket.zaman ?: 0L, canli[s]?.zaman ?: 0L)
                    simdi - bilinen >= TAZE_ESIGI_MS
                }
                val sonDeneme = secim.getLong(KEY_SON_DENEME, 0L)
                if (bayat.isEmpty() || simdi - sonDeneme < TAZE_ESIGI_MS) {
                    bitir()
                    return
                }
                secim.edit().putLong(KEY_SON_DENEME, simdi).apply()
                Thread {
                    try {
                        val gelen = WidgetFiyatIstemcisi.cek(context, bayat)
                        if (gelen.isNotEmpty()) {
                            canliyiYaz(context, gelen)
                            ciz(context, manager, tumu)
                        }
                    } catch (e: Exception) {
                        // Son bilinen değer saatiyle kalır.
                    } finally {
                        bitir()
                    }
                }.start()
            } catch (e: Exception) {
                bitir()
            }
        }

        private fun canliyiYaz(context: Context, gelen: Map<String, CanliFiyat>) {
            val depo = HomeWidgetPlugin.getData(context)
            val birlesik = canliDepo(context).toMutableMap()
            birlesik.putAll(gelen)
            // Yalnız seçili birkaç sembol birikir; sınırsız büyümesin.
            val kalan = birlesik.entries.sortedByDescending { it.value.zaman }
                .take(20).associate { it.key to it.value }
            depo.edit().putString(KEY_CANLI, CanliFiyat.sozlukYaz(kalan)).apply()
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
            val gunEsigi = paket.zaman?.plus(BAYATLIK_ESIGI_MS)?.takeIf { it > simdi }
            // Sunucu kapsamındaki varlık gösteriliyorsa en geç yarım saat
            // sonra yeniden çizilir; `onUpdate` o turda fiyatı tazeler.
            val tazeleme = if (kapsamdakiSemboller(paket, secimDeposu(context), tumu)
                    .isNotEmpty()) simdi + TAZELEME_ARALIGI_MS else null
            val esik = listOfNotNull(gunEsigi, tazeleme).minOrNull()
            if (tumu.isEmpty() || paket.ogeler.isEmpty() || esik == null) {
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
        // Ağ çağrısı (gerekiyorsa) arka iş parçacığında; yayın `goAsync`
        // ile açık tutulur (sistem ~10 sn tanır; istek 9 sn'de vazgeçer).
        val sonuc = goAsync()
        tazele(context.applicationContext) { sonuc.finish() }
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
    /** `true`: fiyat `widget-fiyat`'tan tazelenebilir (2026-10-26). */
    val sunucu: Boolean? = null,
    /** Sunucudan gelen fiyatın azami ondalığı (Dart `fmtFiyat` `azami`). */
    val hane: Int? = null,
)

/**
 * `widget-fiyat` yanıtındaki tek sembol (iOS `SandikCanliFiyat`): TL fiyat,
 * kaynağın yazım anı (epoch ms), günlük yüzde (bilinmiyorsa `null`).
 */
data class CanliFiyat(val fiyat: Double, val zaman: Long, val degisim: Double?) {
    companion object {
        /** `{sembol: {fiyat, zaman, degisim?}}`; geçersiz öğe düşer. */
        fun sozlukCoz(metin: String): Map<String, CanliFiyat> {
            val kok = JSONObject(metin)
            val out = mutableMapOf<String, CanliFiyat>()
            val anahtarlar = kok.keys()
            while (anahtarlar.hasNext()) {
                val s = anahtarlar.next()
                val o = kok.optJSONObject(s) ?: continue
                val fiyat = o.optDouble("fiyat", Double.NaN)
                val zaman = o.optLong("zaman", 0L)
                if (fiyat.isNaN() || fiyat.isInfinite() || fiyat <= 0.0 || zaman <= 0L) continue
                val d = if (o.has("degisim") && !o.isNull("degisim"))
                    o.optDouble("degisim", Double.NaN) else Double.NaN
                out[s] = CanliFiyat(fiyat, zaman, if (d.isNaN() || d.isInfinite()) null else d)
            }
            return out
        }

        fun sozlukYaz(sozluk: Map<String, CanliFiyat>): String {
            val kok = JSONObject()
            sozluk.forEach { (s, c) ->
                val o = JSONObject().put("fiyat", c.fiyat).put("zaman", c.zaman)
                if (c.degisim != null) o.put("degisim", c.degisim)
                kok.put(s, o)
            }
            return kok.toString()
        }
    }
}

/**
 * Dart `tr_format.dart` kurallarının Kotlin eşi — YALNIZ widget'ın
 * sunucudan çektiği sayı için (uygulamanın yazdığı metin yeniden
 * biçimlenmez). `fmtFiyat` / `fmtPctIsaretli` ile aynı çıktı: `₺6.123,45`,
 * `+%0,42`, `−%0,06`, `%0,00`.
 */
object WidgetBicim {
    private val TR = Locale("tr", "TR")

    private fun bicimci(enAz: Int, enCok: Int): DecimalFormat {
        val semboller = DecimalFormatSymbols(TR).apply {
            groupingSeparator = '.'
            decimalSeparator = ','
        }
        return DecimalFormat("#,##0", semboller).apply {
            isGroupingUsed = true
            groupingSize = 3
            roundingMode = RoundingMode.HALF_UP
            minimumFractionDigits = enAz
            maximumFractionDigits = enCok
        }
    }

    /** Dart `fiyatOndaligi`: 1 ₺ ve üstü 2 hane; altı en az 4 anlamlı hane. */
    fun fiyatOndaligi(deger: Double): Int {
        val a = abs(deger)
        if (a > 0 && a < 1) return (floor(-log10(a)).toInt() + 4).coerceIn(2, 8)
        return 2
    }

    /** Dart `fmtFiyat(deger, azami: hane)`. */
    fun fiyat(deger: Double, hane: Int?): String {
        val f = if (hane != null) bicimci(2, maxOf(2, hane))
                else fiyatOndaligi(deger).let { bicimci(it, it) }
        return "₺" + f.format(deger)
    }

    /** Dart `fmtPctIsaretli` + yön: sıfıra yuvarlanan değer işaretsiz, yönsüz. */
    fun yuzde(pct: Double): Pair<String, Int> {
        val f = bicimci(2, 2)
        val mutlak = "%" + f.format(abs(pct))
        if (mutlak == "%" + f.format(0.0)) return mutlak to 0
        return if (pct > 0) ("+$mutlak" to 1) else ("−$mutlak" to -1)
    }

    /** Dart `DateFormat('HH:mm', 'tr_TR')` / `'d MMM HH:mm'`. */
    fun saat(ms: Long): String = SimpleDateFormat("HH:mm", TR).format(Date(ms))
    fun tarih(ms: Long): String = SimpleDateFormat("d MMM HH:mm", TR).format(Date(ms))
}

/**
 * `widget-fiyat` istemcisi (iOS `SandikWidgetFiyatServisi.cek`). Ana iş
 * parçacığında ÇAĞRILMAZ. Uygulamanın yazdığı public URL + anon anahtar;
 * oturum jetonu yok, gövde yalnız semboller. Her hata boş sözlük.
 */
object WidgetFiyatIstemcisi {
    /** `goAsync` ~10 sn tanır: bağlantı + okuma bunun altında kalır. */
    private const val BAGLANTI_MS = 4_000
    private const val OKUMA_MS = 5_000

    fun cek(context: Context, semboller: List<String>): Map<String, CanliFiyat> {
        if (semboller.isEmpty()) return emptyMap()
        val depo = HomeWidgetPlugin.getData(context)
        val taban = depo.getString(SandikVarlikWidgetProvider.KEY_API_URL, null)
        val anahtar = depo.getString(SandikVarlikWidgetProvider.KEY_API_ANAHTAR, null)
        if (taban.isNullOrEmpty() || anahtar.isNullOrEmpty()) return emptyMap()
        if (!taban.startsWith("https://")) return emptyMap()
        val hedef = URL(taban.trimEnd('/') + "/functions/v1/widget-fiyat")
        val baglanti = hedef.openConnection() as HttpURLConnection
        return try {
            baglanti.requestMethod = "POST"
            baglanti.connectTimeout = BAGLANTI_MS
            baglanti.readTimeout = OKUMA_MS
            baglanti.doOutput = true
            baglanti.useCaches = false
            baglanti.setRequestProperty("Content-Type", "application/json")
            baglanti.setRequestProperty("apikey", anahtar)
            baglanti.setRequestProperty("Authorization", "Bearer $anahtar")
            val govde = JSONObject().put("semboller", JSONArray(semboller)).toString()
            baglanti.outputStream.use { it.write(govde.toByteArray(Charsets.UTF_8)) }
            if (baglanti.responseCode != 200) return emptyMap()
            val metin = baglanti.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            CanliFiyat.sozlukCoz(metin).filterKeys { it in semboller }
        } catch (e: Exception) {
            emptyMap()
        } finally {
            baglanti.disconnect()
        }
    }
}

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
                        sunucu = if (o.has("sunucu") && !o.isNull("sunucu"))
                            o.optBoolean("sunucu") else null,
                        hane = if (o.has("hane") && !o.isNull("hane"))
                            o.optInt("hane") else null,
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
