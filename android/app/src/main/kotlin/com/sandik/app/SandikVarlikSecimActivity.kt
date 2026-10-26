package com.sandik.app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.widget.BaseAdapter
import android.widget.Button
import android.widget.ListView
import android.widget.TextView

/**
 * Tek varlık widget'ının seçim ekranı — iOS'taki App Intents "Varlık seç"
 * listesinin (`SandikVarlikQuery`) karşılığı.
 *
 * Liste YALNIZ uygulamanın yazdığı paketten gelir (`sandik_varliklar`:
 * portföy + takip listesi, Dart'ın sırasıyla); katalog araması yok, ağ yok.
 * Seçim widget kimliği başına saklanır (bkz.
 * `SandikVarlikWidgetProvider.SECIM_DOSYASI`).
 *
 * ## Neden Flutter ekranı değil
 * Widget eklenirken uygulama kapalı olabilir; burada Flutter motoru açmak
 * saniyeler sürer ve oturum/biyometrik kilit akışına girerdi. Liste zaten
 * yazılmış bir JSON — düz bir `Activity` ve `ListView` yeter. Framework
 * sınıfları: yeni bağımlılık yok.
 *
 * ## Güvenlik
 * `exported=true` zorunlu (ekleme akışını başka uygulama — launcher —
 * başlatır). Bu yüzden gelen widget kimliğinin BU sağlayıcıya ait olduğu
 * doğrulanır; değilse ekran hiçbir şey yazmadan kapanır.
 */
class SandikVarlikSecimActivity : Activity() {

    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        // Varsayılan sonuç İPTAL: kullanıcı geri dönerse ilk eklemede widget
        // eklenmez, yeniden yapılandırmada eski seçim kalır.
        setResult(RESULT_CANCELED, sonuc())

        if (!bizimWidgetMi()) {
            finish()
            return
        }

        try {
            kur()
        } catch (e: Exception) {
            // Seçim ekranı açılamazsa uygulama düşmesin; ekleme iptal olur.
            finish()
        }
    }

    private fun bizimWidgetMi(): Boolean {
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return false
        return try {
            AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider ==
                ComponentName(this, SandikVarlikWidgetProvider::class.java)
        } catch (e: Exception) {
            false
        }
    }

    private fun sonuc(): Intent =
        Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)

    private fun kur() {
        setContentView(R.layout.sandik_varlik_secim)
        val p = WidgetPaleti(SandikVarlikWidgetProvider.acikTemaMi(this))
        temayiUygula(p)

        val paket = SandikVarlikWidgetProvider.paketiOku(this)
        val depo = SandikVarlikWidgetProvider.secimDeposu(this)
        val secili = depo.getString(SandikVarlikWidgetProvider.secimAnahtari(widgetId), null)

        val liste = findViewById<ListView>(R.id.secim_liste)
        val bos = findViewById<TextView>(R.id.secim_bos)
        val ekle = findViewById<Button>(R.id.secim_ekle)

        if (paket.ogeler.isEmpty()) {
            liste.visibility = View.GONE
            bos.visibility = View.VISIBLE
            ekle.visibility = View.VISIBLE
            ekle.setTextColor(getColor(p.gold))
            ekle.setOnClickListener { bitir(null) }
            return
        }

        liste.divider = ColorDrawable(getColor(p.hairline))
        liste.dividerHeight = resources.displayMetrics.density.toInt().coerceAtLeast(1)
        liste.adapter = SecimAdapter(paket.ogeler, secili, p)
        liste.setOnItemClickListener { _, _, konum, _ ->
            bitir(paket.ogeler.getOrNull(konum))
        }
    }

    /**
     * Seçimi yazar, widget'ı HEMEN çizer (yayın beklenmez) ve ekranı kapatır.
     * [oge] `null`: boş listede "Yine de ekle" — seçim yok, liste gelince
     * ilk varlık gösterilir.
     */
    private fun bitir(oge: VarlikOgesi?) {
        try {
            val duzenle = SandikVarlikWidgetProvider.secimDeposu(this).edit()
            if (oge != null) {
                duzenle.putString(SandikVarlikWidgetProvider.secimAnahtari(widgetId), oge.id)
                // Ad da saklanır: varlık listeden düşerse widget "X artık
                // listende yok" diyebilsin (iOS seçili varlığın adını taşır).
                duzenle.putString(SandikVarlikWidgetProvider.secimAdAnahtari(widgetId), oge.ad)
            }
            duzenle.apply()
            SandikVarlikWidgetProvider.ciz(
                this, AppWidgetManager.getInstance(this), intArrayOf(widgetId))
            // Seçilen varlık sunucu kapsamındaysa ve fiyatı eskiyse hemen
            // tazelenir (arka iş parçacığında; ekran beklemez).
            SandikVarlikWidgetProvider.tazele(applicationContext, null)
        } catch (e: Exception) {
            // Çizilemese de sonuç OK: bir sonraki güncellemede çizilir.
        }
        setResult(RESULT_OK, sonuc())
        finish()
    }

    /**
     * Zemin, metin ve sistem çubukları uygulamanın SEÇİLİ temasına göre
     * (widget'la aynı karar; XML/tema yalnız sistemin modunu bilir).
     */
    @Suppress("DEPRECATION")
    private fun temayiUygula(p: WidgetPaleti) {
        val zemin = getColor(p.bg)
        window.decorView.setBackgroundColor(zemin)
        findViewById<View>(R.id.secim_kok).setBackgroundColor(zemin)
        findViewById<TextView>(R.id.secim_baslik).setTextColor(getColor(p.textPrimary))
        findViewById<TextView>(R.id.secim_aciklama).setTextColor(getColor(p.textMuted))
        findViewById<TextView>(R.id.secim_bos).setTextColor(getColor(p.textMuted))

        // Android 15+ kenardan kenara: çubuklar şeffaf, zemin decor'dan
        // görünür; bu iki satır orada etkisizdir, altında çubuğu boyar.
        window.statusBarColor = zemin
        window.navigationBarColor = zemin

        // Açık zeminde KOYU ikon, koyu zeminde açık ikon.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val maske = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(if (p.acik) maske else 0, maske)
        } else {
            var bayrak = window.decorView.systemUiVisibility
            bayrak = if (p.acik) bayrak or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                     else bayrak and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                bayrak = if (p.acik) bayrak or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                         else bayrak and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
            }
            window.decorView.systemUiVisibility = bayrak
        }
    }

    private inner class SecimAdapter(
        private val ogeler: List<VarlikOgesi>,
        private val secili: String?,
        private val p: WidgetPaleti,
    ) : BaseAdapter() {

        override fun getCount(): Int = ogeler.size

        override fun getItem(position: Int): Any = ogeler[position]

        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val satir = convertView ?: LayoutInflater.from(this@SandikVarlikSecimActivity)
                .inflate(R.layout.sandik_varlik_secim_satir, parent, false)
            val oge = ogeler[position]

            val ad = satir.findViewById<TextView>(R.id.satir_ad)
            val alt = satir.findViewById<TextView>(R.id.satir_alt)
            val fiyat = satir.findViewById<TextView>(R.id.satir_fiyat)
            val isaret = satir.findViewById<TextView>(R.id.satir_secili)

            ad.text = oge.ad
            ad.setTextColor(getColor(p.textPrimary))
            if (oge.alt.isNullOrEmpty()) {
                alt.visibility = View.GONE
            } else {
                alt.text = oge.alt
                alt.setTextColor(getColor(p.textMuted))
                alt.visibility = View.VISIBLE
            }
            // Son bilinen fiyat — yalnız tanımak için; yoksa boş (uydurma
            // sayı yok, "—" bile basılmaz: liste fiyat listesi değil).
            fiyat.text = oge.fiyat ?: ""
            fiyat.setTextColor(getColor(p.textMuted))
            isaret.setTextColor(getColor(p.gold))
            isaret.visibility = if (oge.id == secili) View.VISIBLE else View.GONE
            return satir
        }
    }
}
