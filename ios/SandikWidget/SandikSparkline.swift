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

            func point(_ i: Int) -> CGPoint {
                let x = w * CGFloat(i) / CGFloat(points.count - 1)
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
                fill.addLine(to: CGPoint(x: w, y: h))
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
        }
        // Grafik dekoratiftir; asıl bilgi yüzde metnindedir. VoiceOver'ın
        // anlamsız bir "resim" okuması kullanıcıyı oyalar.
        .accessibilityHidden(true)
    }
}
