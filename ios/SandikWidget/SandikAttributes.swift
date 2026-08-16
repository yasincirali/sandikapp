import ActivityKit
import Foundation

/// Live Activity'nin veri sözleşmesi — ana uygulama ile uzantının ORTAK tipi.
///
/// Bu dosya İKİ hedefe birden üye olmalıdır (Runner + SandikWidget). Yalnızca
/// birine üyeyse `Activity<SandikActivityAttributes>` diğer tarafta derlenmez.
///
/// ## Gizlilik değişmezi
/// Live Activity içeriği **kilit ekranında**, yani telefonu açmadan herkesin
/// görebileceği bir yüzeyde durur. `HomeWidgetService`'teki kuralın aynısı
/// burada daha da sıkı geçerlidir: yalnızca ÖZET yazılır. Varlık listesi,
/// ticker, adet, kullanıcı kimliği veya e-posta ASLA bu tipe girmez.
/// Kullanıcı bakiyeyi gizlediyse ([isHidden]) tutar hiç gönderilmez —
/// maskeleme sunum katmanında değil, KAYNAKTA yapılır ki veri cihazda
/// hiç bulunmasın.
@available(iOS 17.0, *)
struct SandikActivityAttributes: ActivityAttributes {
    /// Oturum boyunca DEĞİŞMEYEN alanlar.
    ///
    /// Not: `ActivityAttributes` protokolü değişken durumu `ContentState`
    /// adlı iç tipte arar; isim birebir böyle olmalıdır.
    public struct ContentState: Codable, Hashable {
        /// Biçimlenmiş toplam portföy değeri — ör. `₺1.482.350,80`.
        ///
        /// **Neden hazır metin, sayı değil:** Türkçe biçim (binlik `.`,
        /// ondalık `,`) tek bir yerde, Dart `tr_format` helper'larında
        /// üretilir. Swift tarafında `NumberFormatter` ile yeniden kurmak
        /// aynı kuralın ikinci bir kopyasını yaratır ve iki kopya
        /// kaçınılmaz olarak ayrışır.
        var totalText: String

        /// Günlük net değişim — ör. `+₺35.420,00`. İşaret dahildir.
        var changeText: String

        /// Günlük değişim yüzdesi — ör. `%2,45`. İşaret HARİÇ; yön ayrıca
        /// [isPositive] ile taşınır (bkz. aşağıdaki erişilebilirlik notu).
        var changePctText: String

        /// Yön. Renk seçimini VE ok işaretini birlikte sürer.
        ///
        /// Marka kuralı: kazanç/kayıp yalnızca renkle anlatılamaz — renk
        /// körlüğü için yön her zaman ▲/▼ ile de gösterilir. Bu yüzden
        /// tek bir bool iki sunum kararını birden besler.
        var isPositive: Bool

        /// Kullanıcı bakiyeyi gizlemişse `true` — tutar alanları `••••••`
        /// olarak gelir, gerçek rakam cihaza hiç ulaşmaz.
        var isHidden: Bool

        /// Son güncelleme — `HH:mm`, ör. `18:04`.
        var updatedAtText: String

        /// Verinin ait olduğu gün — `d MMMM EEEE`, ör. `15 Ağustos Cuma`.
        ///
        /// **Neden saat tek başına yetmiyor:** Live Activity kilit ekranında
        /// saatlerce durur ve gece yarısını geçebilir; sistem oturumu 8 saat
        /// sonra kapatana kadar içerik ekranda kalır. Yalnızca `18:04` gören
        /// kullanıcı bunun bugüne mi düne mi ait olduğunu bilemez.
        ///
        /// Gün adı dahildir: kullanıcı hafta sonu gösteriminde rakamın neden
        /// hareketsiz olduğunu tarihten de okuyabilsin.
        ///
        /// Eski sürümlerden gelen oturumlar bu alanı taşımaz; bu yüzden
        /// varsayılanı boştur ve boşken sunum tarafı satırı hiç çizmez.
        var dateText: String = ""

        /// Seansın planlanan bitişi. Kilit ekranında geri sayım göstermek
        /// için değil, "seans sürüyor mu" kararını uzantıda da verebilmek
        /// için taşınır.
        var sessionEndsAt: Date

        /// Gün içi portföy serisi — **normalize edilmiş** (0…1) noktalar.
        ///
        /// **Neden ham tutar değil:** kilit ekranı telefonu açmadan
        /// görülebilir. Ham TL değerleri göndermek, `showAmounts` kapalıyken
        /// bile portföy büyüklüğünü grafik ekseninden okunabilir kılardı.
        /// Normalize seri yalnızca ŞEKLİ taşır: gün içinde yükseldi mi,
        /// düştü mü. Tutar bilgisi cihazın bu yüzeyine hiç ulaşmaz.
        ///
        /// Boş dizi "grafik çizme" demektir (veri yok ya da tek nokta —
        /// tek noktalı bir "çizgi" yanıltıcı olurdu).
        var sparkline: [Double]

        /// Tutarlar kilit ekranında gösterilsin mi?
        ///
        /// **iOS kilitli/açık ayrımı VERMEZ.** ActivityKit'te böyle bir
        /// sinyal yoktur; aynı `ContentState` iki durumda da render edilir.
        /// Bu yüzden "kilitliyken gizle, açılınca göster" davranışı teknik
        /// olarak kurulamaz — bunun yerine kullanıcı tercihi taşınır
        /// (Ayarlar → "Kilit ekranında tutarı göster", varsayılan KAPALI).
        ///
        /// Kapalıyken tutar alanları kaynakta maskelenir; yüzde ve grafik
        /// görünmeye devam eder çünkü onlar portföy büyüklüğünü ele vermez.
        var showAmounts: Bool

        /// Grafiğin tutar ekseni — alt ve üst kılavuz etiketi.
        ///
        /// Sınırlar gerçek min/max'ın biraz DIŞINDADIR, böylece çizgi
        /// kılavuza değmez ve kullanıcı hareketin hangi bantta gezindiğini
        /// okuyabilir. Eksen olmadan "ne kadar oynadı" sorusu yanıtsız
        /// kalıyordu: aynı görünen iki çizgiden biri 5 kuruşluk, diğeri
        /// 50.000 TL'lik hareket olabilir.
        ///
        /// **Gizlilik:** bu iki metin portföy BÜYÜKLÜĞÜNÜ ele verir —
        /// normalize seri göndermenin bütün gerekçesi buydu. Dart tarafı
        /// yalnızca `showAmounts` açıkken doldurur; boşken sunum ekseni
        /// hiç çizmez.
        ///
        /// Eski sürümlerden gelen oturumlar bu alanları taşımaz; bu yüzden
        /// varsayılanları boştur.
        var axisMinText: String = ""
        var axisMaxText: String = ""

        /// Değişim ölçüldü ama SIFIR mı?
        ///
        /// Sıfır bir YÖN taşımaz: yeşil bir `+₺0,00` ya da kırmızı bir
        /// `-₺0,00` olmayan bir hareketi varmış gibi gösterir. Renk ve ok
        /// bu bayrağa göre bastırılır.
        ///
        /// **Neden ayrı alan:** önce metinden çıkarılıyordu
        /// (`changePctText == "%0,00"`). Biçimlendirme tek bir yerde bile
        /// değişse (ondalık sayısı, boşluk, yüzde işaretinin yeri) çıkarım
        /// sessizce yanlış sonuç verirdi. Dart tarafı bunu zaten
        /// hesaplıyor (`DailySummary.isFlat`); taşımak türetmekten güvenli.
        ///
        /// Eski sürümlerden gelen oturumlar bu alanı taşımaz; varsayılan
        /// `false` — yön gösterilir, eski davranış korunur.
        var isFlatChange: Bool = false

        /// BIST işlem saatleri içinde miyiz?
        ///
        /// Kullanıcının seçtiği GÖSTERİM penceresinden ayrıdır: 7/24
        /// gösterim seçilse bile gece fiyat hareket etmez. Bu bayrak
        /// olmadan donuk rakam "bozuk" gibi görünürdü — banner bunun
        /// yerine "Piyasa kapalı" der ve canlılık noktası griye döner.
        var isMarketOpen: Bool
    }

    /// Seans etiketi — ör. `BIST Seansı`. Oturum boyunca sabittir.
    var sessionName: String
}

@available(iOS 17.0, *)
extension SandikActivityAttributes.ContentState {
    /// Günlük değişim gerçekten hesaplanabildi mi?
    ///
    /// Gün içi seri çekilemediğinde Dart tarafı uydurma bir rakam yerine
    /// `"—"` gönderir (bkz. `LiveActivityService._todayChange`). Sunum
    /// tarafı bunu bilmezse `▲ +—` gibi anlamsız bir dizi basar ve yeşil
    /// renk "kazanç var" yanılgısı yaratır.
    var hasChangeData: Bool {
        changePctText != "—" && !changePctText.isEmpty
    }

    /// Sunumda kâr/zarar rengi kullanılmalı mı?
    var hasDirection: Bool { hasChangeData && !isFlatChange }

    /// Tutar ekseni çizilebilir mi?
    ///
    /// Tutar gizliyken Dart tarafı bu alanları boş gönderir; eksen o
    /// durumda hiç çizilmez (grafiğin şekli görünmeye devam eder).
    var hasAxis: Bool {
        !axisMinText.isEmpty && !axisMaxText.isEmpty
    }
}
