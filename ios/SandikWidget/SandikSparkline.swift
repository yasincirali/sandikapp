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

    /// Tutar ekseni kılavuzları — alt ve üst sınır etiketi.
    ///
    /// Boş bırakılırsa eksen HİÇ çizilmez. Tutar gizliyken Dart tarafı
    /// zaten boş gönderir: eksen portföy büyüklüğünü ele verir ve
    /// normalize seri göndermenin bütün gerekçesi buydu.
    ///
    /// Dar alanlarda (Dynamic Island) çağıran bilinçli olarak vermez —
    /// 26pt yüksekliğinde bir grafikte iki etiket okunmaz, gürültü olur.
    var axisMin: String? = nil
    var axisMax: String? = nil

    /// Eksen etiketlerine ayrılan sol şerit. Çizgi bu şeridin sağından
    /// başlar, yoksa rakamların üstünden geçer ve ikisi de okunmaz.
    private var axisInset: CGFloat { hasAxis ? 44 : 0 }

    private var hasAxis: Bool {
        guard let lo = axisMin, let hi = axisMax else { return false }
        return !lo.isEmpty && !hi.isEmpty
    }

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
            let plotX = axisInset
            let usableW = max(w - padRight - plotX, 1)

            // ---- Tutar ekseni kılavuzları ----
            //
            // İki yatay çizgi (üst/alt sınır) + hizalı etiketler. Sınırlar
            // gerçek min/max'ın biraz DIŞINDA üretilir (Dart tarafında),
            // böylece çizgi kılavuza değmez.
            //
            // Eksen olmadan grafik "ne kadar oynadı" sorusunu
            // yanıtlamıyordu: aynı görünen iki çizgiden biri 5 kuruşluk,
            // diğeri 50.000 TL'lik hareket olabilir.
            if hasAxis, let lo = axisMin, let hi = axisMax {
                let guideColor = SandikTheme.text36.opacity(0.55)

                let guides: [(String, CGFloat)] = [
                    (hi, padY),
                    (lo, padY + usableH),
                ]

                for (label, y) in guides {
                    var guide = Path()
                    guide.move(to: CGPoint(x: plotX, y: y))
                    guide.addLine(to: CGPoint(x: w - padRight, y: y))
                    context.stroke(
                        guide,
                        with: .color(guideColor),
                        style: StrokeStyle(lineWidth: 0.5)
                    )

                    // Etiket sağa yaslı, çizginin ortasına hizalı.
                    //
                    // `context.draw(_:at:anchor:)` kullanılıyor;
                    // `resolve` + `measure` ile elle ölçüp ortalamaya gerek
                    // yok ve anchor'lı çizim daha az API yüzeyi kullanır
                    // (derleyemediğim bir hedefte risk azaltır).
                    context.draw(
                        Text(label)
                            .font(.sandikNumber(7, weight: .medium))
                            .foregroundColor(SandikTheme.text58),
                        at: CGPoint(x: plotX - 4, y: y),
                        anchor: .trailing
                    )
                }
            }

            func point(_ i: Int) -> CGPoint {
                let x = plotX + usableW * CGFloat(i) / CGFloat(points.count - 1)
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
                fill.addLine(to: CGPoint(x: plotX + usableW, y: h))
                fill.addLine(to: CGPoint(x: plotX, y: h))
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
