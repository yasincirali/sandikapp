package com.sandik.app

import java.util.Calendar
import java.util.TimeZone

/**
 * Sunucudan tazelenen widget'ın ritmi — iOS `SandikWidgetRitmi` ile birebir
 * (müşteri raporu 2026-10-26 21:15 #2/#3, yasin "yap"). Gerekçe orada:
 * her tazeleme bir Edge Function çağrısı; kullanıcının bakmadığı saatte
 * yarım saatlik ritim ücretsiz plan kotasını boşa harcar.
 * - gece 00:00–07:00 TR: 2 saatte bir;
 * - hafta sonu altın/döviz: saatte bir (kripto gündüz yarım saat kalır);
 * - fon: iş günü 07:00–22:00 TR, bugünün NAV'ı alınmadıysa saatte bir;
 *   alındıysa ya da pencere dışındaysa sonraki iş günü 07:00.
 * "Alındı" = widget'ın sunucudan çektiği fiyatın anı (fonda NAV'ın sunucuda
 * ilk görüldüğü an) bugüne ait; uygulamanın yazım anı sayılmaz.
 *
 * Ayrı dosyada: sağlayıcı takvime bakmaz (kapanış kararı Dart'ta,
 * `varlik_widget_sozlesmesi_test`); buradaki takvim yalnız ağ ritmi içindir.
 */
object WidgetRitmi {
    const val GECE_MS = 2L * 60 * 60 * 1000
    const val HAFTA_SONU_MS = 60L * 60 * 1000
    const val FON_DENEME_MS = 60L * 60 * 1000
    private const val GECE_SONU = 7
    private const val FON_PENCERE_SONU = 22
    private val TR_SAAT: TimeZone = TimeZone.getTimeZone("Europe/Istanbul")

    private fun takvim(ms: Long): Calendar =
        Calendar.getInstance(TR_SAAT).apply { timeInMillis = ms }

    fun fonMu(sembol: String) = sembol.startsWith("TEFAS:")
    fun kriptoMu(sembol: String) = sembol.startsWith("KRIPTO:")

    private fun isGunu(c: Calendar): Boolean {
        val g = c.get(Calendar.DAY_OF_WEEK)
        return g != Calendar.SATURDAY && g != Calendar.SUNDAY
    }

    private fun fonPenceresinde(ms: Long): Boolean {
        val c = takvim(ms)
        val saat = c.get(Calendar.HOUR_OF_DAY)
        return isGunu(c) && saat >= GECE_SONU && saat < FON_PENCERE_SONU
    }

    private fun bugunAlindi(canliZaman: Long?, simdi: Long): Boolean {
        if (canliZaman == null) return false
        val a = takvim(canliZaman)
        val b = takvim(simdi)
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) &&
            a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }

    /** Fiyat şimdi sunucudan çekilmeli mi (10 dk tazelik kuralına ek). */
    fun cekilmeli(sembol: String, simdi: Long, canliZaman: Long?): Boolean {
        if (!fonMu(sembol)) return true
        return fonPenceresinde(simdi) && !bugunAlindi(canliZaman, simdi)
    }

    /** Sonraki yenileme anı (epoch ms). */
    fun sonraki(sembol: String, simdi: Long, canliZaman: Long?): Long {
        if (fonMu(sembol)) {
            return if (cekilmeli(sembol, simdi, canliZaman)) simdi + FON_DENEME_MS
            else sonrakiIsGunuSabahi(simdi)
        }
        val c = takvim(simdi)
        if (c.get(Calendar.HOUR_OF_DAY) < GECE_SONU) return simdi + GECE_MS
        if (!isGunu(c) && !kriptoMu(sembol)) return simdi + HAFTA_SONU_MS
        return simdi + SandikVarlikWidgetProvider.TAZELEME_ARALIGI_MS
    }

    /** Bugün iş günü ve 07:00 öncesiyse bugün 07:00; değilse sonraki iş günü 07:00 (TR). */
    fun sonrakiIsGunuSabahi(simdi: Long): Long {
        val c = takvim(simdi).apply {
            set(Calendar.HOUR_OF_DAY, GECE_SONU)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        repeat(8) {
            if (c.timeInMillis > simdi && isGunu(c)) return c.timeInMillis
            c.add(Calendar.DAY_OF_YEAR, 1)
        }
        return simdi + FON_DENEME_MS
    }
}
