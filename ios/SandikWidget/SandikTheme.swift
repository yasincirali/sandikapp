import SwiftUI

/// `lib/theme/sandik.dart` içindeki ÜRETİM token'larının Swift kopyası.
///
/// Değerler tahmin değildir; her biri Dart tarafındaki karşılığından
/// okunmuştur (satır referansları aşağıda). Bu dosya elle senkron tutulur —
/// Dart'ta bir token değişirse burası da değişmeli.
///
/// **Palet dışı renk eklenmemelidir.** Marka brief'i bunu açıkça yasaklar;
/// yeni bir tona ihtiyaç varsa önce `sandik.dart` içinde tanımlanır.
enum SandikTheme {

    // MARK: - Yüzeyler (dark — Live Activity çoğunlukla bu modda görünür)

    /// Seviye 0 — ekran zemini. `sandik.dart:929`
    static let background = Color(hex: 0x0A1E15)
    /// Seviye 1 — kart, liste satırı, pill zemini. `sandik.dart:930`
    static let surface1 = Color(hex: 0x112E28)
    /// Seviye 2 — hero kart / elevated yüzey. `sandik.dart:931`
    static let surface2 = Color(hex: 0x1A3D2E)

    // MARK: - Marka

    /// Ana marka rengi — logo ikonu, vurgu. `sandik.dart:934`
    ///
    /// ⚠️ ASLA doğrudan metin rengi yapılmaz: beyaz/açık zeminde 1.94:1
    /// kontrast verir. Bir ZEMİN rengidir; üstüne `onAmber` gelir.
    static let amber = Color(hex: 0xF5A623)

    /// Display sayılar ve wordmark. `sandik.dart:935`
    ///
    /// Koyu marka zemininde (`background`) okunur; amber'in aksine büyük
    /// punto display rakamlarda metin olarak kullanılabilir.
    static let gold = Color(hex: 0xF5C842)

    /// Amber zemin üstündeki metin — 7.66:1. `sandik.dart:658`
    ///
    /// Not: marka brief'i bunu `#12241E` olarak yazar ama üretimdeki değer
    /// `#112E28`'dir. Kod kaynaktır; brief eski kalmış.
    static let onAmber = Color(hex: 0x112E28)

    // MARK: - Durum

    /// Artış / kâr — 5.73:1. `sandik.dart:945`
    static let gain = Color(hex: 0x3DB77F)
    /// Düşüş / zarar — 5.17:1. `sandik.dart:946`
    static let loss = Color(hex: 0xFF6B52)

    // MARK: - Metin tonları
    //
    // ⚠️ Token adları alfa değeriyle UYUŞMAZ (marka brief'inde de not
    // düşülmüş): `text36` aslında %58, `text20` ise %42'dir. Yani `text36`,
    // `text58`'den daha soluk DEĞİLDİR. Hiyerarşi kurarken isme değil
    // gerçek değere bakılır. Pratikte üç kademe vardır: %88 → %55 → %42.

    /// Ana başlık, birincil sayı — beyaz @ %88.
    static let text90 = Color.white.opacity(0.88)
    /// İkincil etiket — beyaz @ %55.
    static let text58 = Color.white.opacity(0.55)
    /// Yardımcı metin — beyaz @ %58.
    static let text36 = Color.white.opacity(0.58)
    /// Devre dışı — beyaz @ %42.
    static let text20 = Color.white.opacity(0.42)

    /// Hairline ayraç — beyaz @ %10.
    static let hairline = Color.white.opacity(0.10)

    // MARK: - Köşe yarıçapı

    /// Küçük rozet, chip.
    static let radiusSm: CGFloat = 8
    /// İç kart, buton.
    static let radiusMd: CGFloat = 14
    /// Kilit ekranı ana çerçevesi, sheet.
    static let radiusLg: CGFloat = 20

    /// Yöne göre durum rengi. Renk TEK BAŞINA anlam taşımamalı —
    /// çağıran taraf ayrıca ▲/▼ işareti göstermek zorundadır.
    static func statusColor(isPositive: Bool) -> Color {
        isPositive ? gain : loss
    }
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
