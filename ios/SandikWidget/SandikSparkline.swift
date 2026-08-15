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
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if points.count >= 2 {
                // Çizginin kalınlığı üstte/altta kırpılmasın diye dikey pay.
                let padY: CGFloat = 2
                let usableH = max(h - padY * 2, 1)

                let path = Path { p in
                    for (i, v) in points.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(points.count - 1)
                        // Normalize değer yukarı doğru artar; ekran
                        // koordinatı aşağı doğru artar → ters çevrilir.
                        let y = padY + usableH * (1 - CGFloat(clamp(v)))
                        if i == 0 {
                            p.move(to: CGPoint(x: x, y: y))
                        } else {
                            p.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }

                if showsFill {
                    // Dolgu: çizginin altını kapatan dikey gradient.
                    var fill = path
                    fill.addLine(to: CGPoint(x: w, y: h))
                    fill.addLine(to: CGPoint(x: 0, y: h))
                    fill.closeSubpath()

                    fill.fill(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                path.stroke(
                    color,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                )
            }
        }
        // Grafik dekoratiftir; asıl bilgi yüzde metnindedir. VoiceOver'ın
        // anlamsız bir "resim" okuması kullanıcıyı oyalar.
        .accessibilityHidden(true)
    }

    /// Bozuk veriye karşı koruma: aralık dışı değer grafiği taşırır.
    private func clamp(_ v: Double) -> Double {
        min(max(v, 0), 1)
    }
}

// MARK: - Path yardımcıları
//
// SwiftUI'da `Path` doğrudan `View` değildir; `.stroke`/`.fill` çağrıları
// `Shape` üzerinde çalışır. Aşağıdaki sarmalayıcılar `GeometryReader`
// içinde doğrudan çizim yapabilmeyi sağlar.

@available(iOS 17.0, *)
private extension Path {
    func stroke(_ color: Color, style: StrokeStyle) -> some View {
        _PathShape(path: self).stroke(color, style: style)
    }

    func fill<S: ShapeStyle>(_ style: S) -> some View {
        _PathShape(path: self).fill(style)
    }
}

/// Hazır bir `Path`'i `Shape`'e sarar.
@available(iOS 17.0, *)
private struct _PathShape: Shape {
    let path: Path
    func path(in rect: CGRect) -> Path { path }
}
