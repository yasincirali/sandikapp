import SwiftUI
import WidgetKit

/// Sandık logo işareti — uygulama ikonunun "sandık" hâli (2026-10-01).
///
/// ## Neden değişti
/// Önceki işaret (80×50 çerçeve + iç kare + kol) uygulama ikonundaki amber
/// dalgalarla hiçbir bağ kurmuyordu; kullanıcı "çok amatör" dedi, küçük
/// boyutta ışık anahtarı / pil gibi okunuyordu. Dört yön ve üç "logo +
/// sandık" birleşimi çizildi (`logo-secenekleri/`), yasin **E · İkon-sandık**'ı
/// seçti: ana ekrandaki ikonun aynısı, üstte kapak aralığı ve ortada kilit.
/// İkonu tanıyan kullanıcı işareti hemen eşler; kilit "sandık" adını söyler.
///
/// ## Geometri (viewBox 64×64)
/// ```svg
/// <clipPath><rect x="4" y="4" width="56" height="56" rx="16"/></clipPath>
/// zemin: #FCD35A → #EAA12B dikey gradyan
/// dalgalar: tepe y = 24 / 34 / 44 (#E2861F, #C56314, #993D0A)
/// kapak aralığı: y 23…26 boş
/// kilit levhası: (25.5, 19) 13×16 r3.5 #5A2405, anahtar deliği #FCD35A
/// ```
/// Dalga eğrisi `assets/images/sandik_logo.svg`'deki ikonla aynı formdadır
/// (kenarlarda çukur, ortada tepe); 16 pt'de okunsun diye üç katmana indi.
///
/// ## Kare oran
/// Eski işaret 8:5'ti; Ada'nın compact alanında yön halkası (24×24) ile
/// logo arasında geçişte yerleşim zıplıyordu. Yeni işaret kare — `width`
/// hem genişlik hem yüksekliktir.
///
/// ## Tek renk
/// Kilit ekranı widget'ı (`accessoryRectangular`) ve StandBy gibi yüzeyleri
/// sistem tek renk çizer (`widgetRenderingMode != .fullColor`). Orada
/// gradyan gri lekeye dönerdi; bunun yerine katmanlar opaklık basamağıyla
/// (0.38 / 0.62 / 0.82 / 1) çizilir ve kilit levhası OYULUR — siluet aynı
/// kalır, renk sistemin olur.
///
/// **Wordmark burada YOK.** Dynamic Island compact alanında "sandık"
/// yazısı okunamayacak kadar küçülür. Wordmark yalnızca expanded/kilit
/// ekranı başlığında, ayrı bir `Text` olarak kullanılır.
struct SandikLogoMark: View {
    /// İşaretin kenarı (kare).
    var width: CGFloat = 26

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        // Canvas kapanışı kaçışlıdır; ortam değeri dışarıda okunup değer
        // olarak taşınır.
        let tekRenk = renderingMode != .fullColor
        Canvas { context, size in
            let s = size.width / 64.0

            let kasa = Path(
                roundedRect: CGRect(x: 4 * s, y: 4 * s, width: 56 * s, height: 56 * s),
                cornerRadius: 16 * s,
                style: .continuous
            )
            let levha = Path(
                roundedRect: CGRect(x: 25.5 * s, y: 19 * s, width: 13 * s, height: 16 * s),
                cornerRadius: 3.5 * s,
                style: .continuous
            )

            // Kapak ve gövde aynı içeriği taşır; aradaki 3 birimlik bant
            // boş kalır — sandığın kapak çizgisi.
            for bolge in [
                CGRect(x: 0, y: 0, width: size.width, height: 23 * s),
                CGRect(x: 0, y: 26 * s, width: size.width, height: size.height - 26 * s),
            ] {
                var ctx = context
                ctx.clip(to: kasa)
                ctx.clip(to: Path(bolge))
                // Tek renkte levha oyulur: içine konan anahtar deliği
                // siluetin içinde boşlukta durur.
                if tekRenk { ctx.clip(to: levha, options: .inverse) }
                Self.katmanlar(&ctx, size: size, s: s, tekRenk: tekRenk)
            }

            if !tekRenk {
                context.fill(levha, with: .color(Color(hex: 0x5A2405)))
            }
            context.fill(
                Self.anahtarDeligi(s),
                with: .color(tekRenk ? .white : Color(hex: 0xFCD35A))
            )
        }
        .frame(width: width, height: width)
        // Logo dekoratiftir; asıl bilgi yanındaki metinlerdedir. VoiceOver'ın
        // "resim" diye okuyup kullanıcıyı oyalamaması için gizlenir.
        .accessibilityHidden(true)
    }

    // MARK: - Çizim

    private static func katmanlar(
        _ ctx: inout GraphicsContext, size: CGSize, s: CGFloat, tekRenk: Bool
    ) {
        let tum = Path(CGRect(origin: .zero, size: size))
        let tepeler: [CGFloat] = [24, 34, 44]
        if tekRenk {
            ctx.fill(tum, with: .color(.white.opacity(0.38)))
            for (tepe, opak) in zip(tepeler, [0.62, 0.82, 1.0]) {
                ctx.fill(dalga(tepe, s), with: .color(.white.opacity(opak)))
            }
        } else {
            ctx.fill(tum, with: .linearGradient(
                Gradient(colors: [Color(hex: 0xFCD35A), Color(hex: 0xEAA12B)]),
                startPoint: CGPoint(x: 0, y: 4 * s),
                endPoint: CGPoint(x: 0, y: 60 * s)
            ))
            for (tepe, renk) in zip(tepeler, [UInt32(0xE2861F), 0xC56314, 0x993D0A]) {
                ctx.fill(dalga(tepe, s), with: .color(Color(hex: renk)))
            }
        }
    }

    /// İkondaki dalga: kenarlarda çukur, ortada tepe; altı kapalı alan.
    private static func dalga(_ b: CGFloat, _ s: CGFloat) -> Path {
        let a: CGFloat = 9
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(-2, b + a * 0.45))
        path.addCurve(to: p(13, b + a), control1: p(4, b + a * 0.9), control2: p(8, b + a))
        path.addCurve(to: p(32, b), control1: p(21, b + a), control2: p(24, b))
        path.addCurve(to: p(51, b + a), control1: p(40, b), control2: p(43, b + a))
        path.addCurve(to: p(66, b + a * 0.45), control1: p(56, b + a), control2: p(60, b + a * 0.9))
        path.addLine(to: p(66, 70))
        path.addLine(to: p(-2, 70))
        path.closeSubpath()
        return path
    }

    /// Yuvarlak baş + aşağı genişleyen gövde.
    private static func anahtarDeligi(_ s: CGFloat) -> Path {
        var path = Path(ellipseIn: CGRect(x: 29.4 * s, y: 22.5 * s, width: 5.2 * s, height: 5.2 * s))
        path.move(to: CGPoint(x: 30.6 * s, y: 26.5 * s))
        path.addLine(to: CGPoint(x: 33.4 * s, y: 26.5 * s))
        path.addLine(to: CGPoint(x: 34.1 * s, y: 31.5 * s))
        path.addLine(to: CGPoint(x: 29.9 * s, y: 31.5 * s))
        path.closeSubpath()
        return path
    }
}
