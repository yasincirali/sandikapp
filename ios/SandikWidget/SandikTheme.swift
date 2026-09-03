import SwiftUI

/// Tek bir palet — koyu ya da açık.
///
/// Değerler `lib/theme/sandik.dart` içindeki `SandikPalette.dark` ve
/// `SandikPalette.light` token'larından okunmuştur (satır referansları
/// aşağıda). Bu dosya elle senkron tutulur — Dart'ta bir token değişirse
/// burası da değişmeli.
///
/// **Palet dışı renk eklenmemelidir.** Marka brief'i bunu açıkça yasaklar;
/// yeni bir tona ihtiyaç varsa önce `sandik.dart` içinde tanımlanır.
struct SandikPalette {

    // MARK: - Yüzeyler

    /// Seviye 0 — ekran zemini.
    let background: Color
    /// Seviye 1 — kart, liste satırı, pill zemini.
    let surface1: Color
    /// Seviye 2 — hero kart / elevated yüzey.
    let surface2: Color

    // MARK: - Marka

    /// Ana marka rengi — logo ikonu, vurgu.
    ///
    /// ⚠️ ASLA doğrudan metin rengi yapılmaz: beyaz/açık zeminde 1.94:1
    /// kontrast verir. Bir ZEMİN rengidir; üstüne `onAmber` gelir.
    let amber: Color

    /// Display sayılar ve wordmark.
    let gold: Color

    /// Amber zemin üstündeki metin.
    let onAmber: Color

    // MARK: - Durum

    /// Artış / kâr.
    let gain: Color
    /// Düşüş / zarar.
    let loss: Color

    // MARK: - Metin tonları

    /// Ana başlık, birincil sayı.
    let text90: Color
    /// İkincil etiket.
    let text58: Color
    /// Yardımcı metin.
    let text36: Color
    /// Devre dışı.
    let text20: Color

    /// Hairline ayraç.
    let hairline: Color

    /// Yöne göre durum rengi. Renk TEK BAŞINA anlam taşımamalı —
    /// çağıran taraf ayrıca ▲/▼ işareti göstermek zorundadır.
    func statusColor(isPositive: Bool) -> Color {
        isPositive ? gain : loss
    }

    // MARK: - Hazır paletler

    /// Koyu palet — `sandik.dart:636-665`.
    ///
    /// Metin tonlarındaki not: token adları alfa değeriyle UYUŞMAZ (marka
    /// brief'inde de düşülmüş). `text36` aslında %58, `text20` ise %42'dir.
    /// Yani `text36`, `text58`'den daha soluk DEĞİLDİR. Hiyerarşi kurarken
    /// isme değil gerçek değere bakılır: %88 → %55 → %42.
    static let dark = SandikPalette(
        background: Color(hex: 0x0A1E15),   // sandik.dart:929
        surface1:   Color(hex: 0x112E28),   // sandik.dart:930
        surface2:   Color(hex: 0x1A3D2E),   // sandik.dart:931
        amber:      Color(hex: 0xF5A623),   // sandik.dart:934
        gold:       Color(hex: 0xF5C842),   // sandik.dart:935
        onAmber:    Color(hex: 0x112E28),   // sandik.dart:658 — 7.66:1
        gain:       Color(hex: 0x3DB77F),   // sandik.dart:945 — 5.73:1
        loss:       Color(hex: 0xFF6B52),   // sandik.dart:946 — 5.17:1
        text90:     Color.white.opacity(0.88),
        text58:     Color.white.opacity(0.55),
        text36:     Color.white.opacity(0.58),
        text20:     Color.white.opacity(0.42),
        hairline:   Color.white.opacity(0.10)
    )

    /// Açık palet — `sandik.dart:673-715`.
    ///
    /// `amber` iki modda AYNI kalır (CTA zemini), ama `gold` ve `onAmber`
    /// koyulaşır: açık zeminde altın sarısı metin okunmaz.
    static let light = SandikPalette(
        background: Color(hex: 0xF4F1EA),
        surface1:   Color(hex: 0xFBFAF6),
        surface2:   Color(hex: 0xFFFFFF),
        amber:      Color(hex: 0xF5A623),
        gold:       Color(hex: 0x4A3618),
        onAmber:    Color(hex: 0x112E28),
        gain:       Color(hex: 0x0F7A4E),
        loss:       Color(hex: 0xC0341F),
        text90:     Color.black.opacity(0.88),
        text58:     Color.black.opacity(0.58),
        text36:     Color.black.opacity(0.55),
        text20:     Color.black.opacity(0.42),
        hairline:   Color.black.opacity(0.10)
    )

    /// Dart tarafından gelen çözülmüş bayrağa göre palet.
    ///
    /// Bayrak `@Environment(\.colorScheme)`'in YERİNE geçer: uzantı cihazın
    /// görünümünü görebilir ama uygulamanın tema tercihini göremez, oysa
    /// istenen ikincisidir.
    static func resolved(isLight: Bool) -> SandikPalette {
        isLight ? .light : .dark
    }
}

/// Moddan bağımsız sabitler.
enum SandikTheme {

    // MARK: - Marka

    /// Ana marka rengi — iki modda da AYNI (`sandik.dart:934` / `:684`).
    ///
    /// Bir CTA/vurgu ZEMİNİDİR; açık paletde bile değişmez çünkü üstüne gelen
    /// mürekkep (`onAmber`) koyudur. Metin rengi olarak ASLA kullanılmaz:
    /// beyaz zeminde 1.94:1 kontrast verir.
    static let amber = SandikPalette.dark.amber

    // MARK: - Köşe yarıçapı

    /// Küçük rozet, chip.
    static let radiusSm: CGFloat = 8
    /// İç kart, buton.
    static let radiusMd: CGFloat = 14
    /// Kilit ekranı ana çerçevesi, sheet.
    static let radiusLg: CGFloat = 20
}

// MARK: - Tipografi

extension Font {
    /// DM Sans dosya adı — ağırlığa göre.
    ///
    /// Uzantı ana uygulamanın font kaydını MİRAS ALMAZ; dosyalar
    /// `ios/SandikWidget/Fonts/` altında ve `Info.plist` içindeki
    /// `UIAppFonts` listesinde kayıtlıdır.
    private static func dmSansName(_ weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return "DMSans-Black"
        case .bold: return "DMSans-Bold"
        case .semibold: return "DMSans-SemiBold"
        case .medium: return "DMSans-Medium"
        default: return "DMSans-Regular"
        }
    }

    /// Finansal sayılar için tabular (sabit genişlikli) rakam.
    ///
    /// **Neden zorunlu:** Live Activity'de sayı dakikada bir güncellenir.
    /// Orantılı rakamlarda `1` ile `8` farklı genişliktedir; her tazelemede
    /// rakamlar yatayda zıplar ve sakin durması gereken bir yüzey
    /// tedirgin edici olur. Marka için pazarlık konusu değildir.
    ///
    /// `.custom(_:size:)` font bulunamazsa sessizce sistem fontuna düşer —
    /// kasıtlı bir kabul: `monospacedDigit()` sistem fontunda da tabular
    /// davranır, yani font eksikse hizalama yine bozulmaz, yalnızca
    /// karakter biçimi değişir.
    static func sandikNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(dmSansName(weight), size: size).monospacedDigit()
    }

    /// Etiket/başlık — sayı olmayan metin.
    static func sandikLabel(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(dmSansName(weight), size: size)
    }
}

// MARK: - Yardımcılar

extension Color {
    /// `0xRRGGBB` biçiminden renk — token sabitlerini Dart'taki
    /// `Color(0xFF..)` yazımına birebir benzer tutmak için.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
