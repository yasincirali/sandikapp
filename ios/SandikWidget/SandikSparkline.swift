import SwiftUI

/// Gün içi portföy hareketini gösteren küçük çizgi grafik.
///
/// ## Neden normalize veri
/// Gelen noktalar 0…1 aralığındadır; ham TL değeri taşımaz. Kilit ekranı
/// telefonu açmadan görülebilen bir yüzey olduğu için grafiğin ekseninden
/// portföy büyüklüğünün okunabilmesi istenmez. Normalize seri yalnızca
/// ŞEKLİ anlatır: gün içinde yükseldi mi, düştü mü.
///
/// Bu aynı zamanda `showAmounts` kapalıyken de grafiğin gösterilebilmesini
/// sağlar — kullanıcı tutarını saklarken bile "bugün nasıl gidiyor"
/// sorusunu yanıtlayabilir.
///
/// ## Neden animasyon yok
/// Marka kuralı: kilit ekranında saatlerce duran bir yüzey sakin olmalı.
/// Çizgi her güncellemede yeniden çizilir ama geçiş animasyonu yoktur.
@available(iOS 17.0, *)
struct SandikSparkline: View {
    /// Normalize edilmiş noktalar (0…1). İki noktadan az ise çizilmez.
    let points: [Double]

    /// Çizgi rengi — kazanç/kayıp durumuna göre çağıran belirler.
    let color: Color

    /// Altındaki gradient dolgu gösterilsin mi? Dar alanlarda (Dynamic
    /// Island) kapatılır; dolgu o ölçekte gürültüye dönüşür.
    var showsFill: Bool = true

    /// Piyasa açık mı? Serinin ucundaki noktanın rengini sürer.
    ///
    /// **Neden `nil` olabiliyor:** uç noktası yalnızca istendiğinde çizilir.
    /// `nil` verilirse hiç nokta çizilmez — Dynamic Island'ın dar alanında
    /// 26pt yüksekliğinde bir grafikte nokta çizgiyle birleşip leke olur.
    ///
    /// Değer verildiğinde renk başlıktaki canlılık noktasıyla AYNI kuralı
    /// izler: açıkken yeşil, kapalıyken gri. İki işaret aynı yüzeyde farklı
    /// şey söylerse (başlık "Piyasa kapalı" derken uç yeşil parlarsa)
    /// kullanıcı donuk veriyi canlı sanır.
    var isMarketOpen: Bool? = nil

    var body: some View {
        // `Canvas` kullanılıyor, `GeometryReader` + `Path` DEĞİL.
        //
        // Neden: `Path`'i @ViewBuilder içinde `var` ile kopyalayıp mutasyon
        // etmek derlenmez (SwiftUI orada bildirim kabul etmez) ve `Path`'e
        // eklenen `fill`/`stroke` uzantıları `Shape`'inkilerle çakışır.
        // `Canvas` saf çizimdir; `SandikLogoMark` da aynı yolu kullanıyor.
        Canvas { context, size in
            guard points.count >= 2 else { return }

            let w = size.width
            let h = size.height
            // Çizginin kalınlığı üstte/altta kırpılmasın diye dikey pay.
            let padY: CGFloat = 2
            let usableH = max(h - padY * 2, 1)

            // Sağda pay: uç noktası ve halesi tam kenara denk gelirse
            // kırpılır. Nokta çizilmiyorsa pay da yok — grafik tüm
            // genişliği kullansın.
            let padRight: CGFloat = isMarketOpen == nil ? 0 : 5
            let usableW = max(w - padRight, 1)

            func point(_ i: Int) -> CGPoint {
                let x = usableW * CGFloat(i) / CGFloat(points.count - 1)
                // Normalize değer yukarı doğru artar; ekran koordinatı
                // aşağı doğru artar → ters çevrilir.
                let v = min(max(points[i], 0), 1)
                return CGPoint(x: x, y: padY + usableH * (1 - CGFloat(v)))
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<points.count {
                line.addLine(to: point(i))
            }

            if showsFill {
                // Dolgu: çizginin altını kapatan dikey gradient.
                var fill = line
                fill.addLine(to: CGPoint(x: usableW, y: h))
                fill.addLine(to: CGPoint(x: 0, y: h))
                fill.closeSubpath()

                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [
                            color.opacity(0.28),
                            color.opacity(0.0),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: h)
                    )
                )
            }

            context.stroke(
                line,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )

            // ---- Serinin ucundaki canlılık noktası ----
            //
            // Kullanıcının "grafiğin ucu güncel mi" sorusunu tek bakışta
            // yanıtlar. Çizginin son noktası zaten canlı portföy toplamına
            // sabitleniyor (bkz. LiveActivityService._dayValues); nokta o
            // ucu görünür kılar.
            //
            // Renk başlıktaki canlılık noktasıyla aynı kuralı izler:
            // açıkken yeşil, kapalıyken gri. Kapalıyken hale de çizilmez —
            // hale "veri akıyor" demektir ve gece bu doğru değildir.
            if let isOpen = isMarketOpen {
                let tip = point(points.count - 1)
                let dotColor = isOpen ? SandikTheme.gain : SandikTheme.text36

                if isOpen {
                    // Hale: noktanın etrafında düşük alfalı yumuşak daire.
                    // Animasyon YOK — marka kuralı gereği kilit ekranında
                    // yanıp sönen öğe bulunmaz (pil + rahatsızlık).
                    let haloR: CGFloat = 4.5
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: tip.x - haloR, y: tip.y - haloR,
                            width: haloR * 2, height: haloR * 2)),
                        with: .color(dotColor.opacity(0.26))
                    )
                }

                // Nokta gövdesi. Zemin rengiyle ince bir çeper: çizgi
                // noktanın altından geçtiğinde ikisi birbirine karışmasın.
                let r: CGFloat = 2.6
                let dotRect = CGRect(
                    x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)
                context.stroke(
                    Path(ellipseIn: dotRect.insetBy(dx: -1.1, dy: -1.1)),
                    with: .color(SandikTheme.background),
                    lineWidth: 1.6
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            }
        }
        // Grafik dekoratiftir; asıl bilgi yüzde metnindedir. VoiceOver'ın
        // anlamsız bir "resim" okuması kullanıcıyı oyalar.
        .accessibilityHidden(true)
    }
}
