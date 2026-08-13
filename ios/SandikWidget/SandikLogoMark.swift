import SwiftUI

/// Sandık logo ikonu — marka brief'indeki SVG'nin birebir SwiftUI karşılığı.
///
/// Kaynak geometri (viewBox 80×50):
/// ```svg
/// <rect x="2"  y="2"  width="76" height="46" rx="10" stroke-width="2.8"/>
/// <rect x="9"  y="10" width="30" height="30" rx="5"  stroke-width="2.4"/>
/// <line x1="48" y1="25" x2="72" y2="25"            stroke-width="4.5"/>
/// <circle cx="48" cy="25" r="4.5" fill/>
/// ```
///
/// Tüm koordinatlar 80×50 tuvale göre normalize edilip verilen `size`'a
/// ölçeklenir; böylece Dynamic Island'ın 24pt'lik compact alanında da,
/// kilit ekranının 20pt'lik başlığında da aynı oranlar korunur.
///
/// **Wordmark burada YOK.** Dynamic Island compact alanında "sandık"
/// yazısı okunamayacak kadar küçülür; brief bunu açıkça yasaklar.
/// Wordmark yalnızca expanded/kilit ekranı başlığında, ayrı bir `Text`
/// olarak kullanılır.
struct SandikLogoMark: View {
    /// Çizim rengi. Marka kuralı gereği ikon her zaman amber'dir; parametre
    /// yalnızca amber zemin ÜSTÜNE çizim gerektiğinde (`onAmber`) kullanılır.
    var color: Color = SandikTheme.amber

    /// İkonun genişliği. Yükseklik 80:50 oranından türetilir.
    var width: CGFloat = 26

    private var height: CGFloat { width * (50.0 / 80.0) }

    var body: some View {
        Canvas { context, size in
            // Ölçek: viewBox 80×50 → verilen kutu.
            let s = size.width / 80.0

            // Dış gövde — sandığın kasası.
            let outer = Path(
                roundedRect: CGRect(x: 2 * s, y: 2 * s, width: 76 * s, height: 46 * s),
                cornerRadius: 10 * s
            )
            context.stroke(outer, with: .color(color), lineWidth: 2.8 * s)

            // İç kare — kilit haznesi.
            let inner = Path(
                roundedRect: CGRect(x: 9 * s, y: 10 * s, width: 30 * s, height: 30 * s),
                cornerRadius: 5 * s
            )
            context.stroke(inner, with: .color(color), lineWidth: 2.4 * s)

            // Kıskaç kolu — yuvarlak uçlu çizgi.
            var arm = Path()
            arm.move(to: CGPoint(x: 48 * s, y: 25 * s))
            arm.addLine(to: CGPoint(x: 72 * s, y: 25 * s))
            context.stroke(
                arm,
                with: .color(color),
                style: StrokeStyle(lineWidth: 4.5 * s, lineCap: .round)
            )

            // Mafsal noktası — dolu daire.
            let pivot = Path(
                ellipseIn: CGRect(
                    x: (48 - 4.5) * s,
                    y: (25 - 4.5) * s,
                    width: 9 * s,
                    height: 9 * s
                )
            )
            context.fill(pivot, with: .color(color))
        }
        .frame(width: width, height: height)
        // Logo dekoratiftir; asıl bilgi yanındaki metinlerdedir. VoiceOver'ın
        // "resim" diye okuyup kullanıcıyı oyalamaması için gizlenir.
        .accessibilityHidden(true)
    }
}
