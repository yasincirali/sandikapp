import SwiftUI
import WidgetKit

/// Ana ekran widget'ı — portföy özeti.
///
/// Veriyi Flutter tarafı yazar (`HomeWidgetService`), burada yalnızca okunur.
/// Anahtar adları Dart'taki sabitlerle **birebir** aynı olmalıdır; tek harf
/// farkı widget'ı sessizce "veri yok" hâline düşürür.
///
/// **Neden PNG değil de çizim:** Android tarafı hazır bir PNG okur çünkü
/// `RemoteViews` özel görünüm çizemez. iOS'ta bu yol kapalı — PNG
/// `getApplicationSupportDirectory()` altına yazılıyor, yani uygulamanın
/// KENDİ kabına; uzantı ayrı sandbox'ta ve o yolu göremez. Paylaşımlı
/// `UserDefaults` (app group) ikisine de açık olduğu için iOS'a görsel
/// değil sayı gönderilir ve eğri burada `SandikSparkline` ile çizilir.
///
/// Widget kendi başına ağa çıkmaz: veri yalnızca uygulama açıkken tazelenir.
/// Bu yüzden son güncelleme saati gösterilir — kullanıcı baktığı sayının ne
/// kadar taze olduğunu bilmeli.

// MARK: - Paylaşımlı veri

private enum WidgetKeys {
    static let suite = "group.com.sandik.app"

    static let total = "sandik_total"
    static let change = "sandik_change"
    static let changePct = "sandik_change_pct"
    static let isPositive = "sandik_is_positive"
    static let isFlat = "sandik_is_flat"
    static let hasData = "sandik_has_data"
    static let updatedAt = "sandik_updated_at"
    static let date = "sandik_date"
    static let marketOpen = "sandik_market_open"
    static let isLightTheme = "sandik_is_light_theme"
    static let sparkSeries = "sandik_spark_series"
}

/// Widget dokunuşunun taşıdığı URI.
///
/// `SandikWidgetProvider.WIDGET_CLICK_URI` (Android) ve
/// `HomeWidgetService.widgetClickUri` (Dart) ile aynı olmalı — açılış atfı
/// bu eşleşmeye dayanıyor.
private let widgetClickURL = URL(string: "sandik://widget/home")

struct SandikEntry: TimelineEntry {
    let date: Date
    let total: String
    let change: String
    let changePct: String
    let isPositive: Bool
    let isFlat: Bool
    let hasData: Bool
    let updatedAt: String
    let dateLabel: String
    let isMarketOpen: Bool
    let isLight: Bool
    let sparkline: [Double]

    /// Yön RENKLE anlatılamaz — çağıran ayrıca ▲/▼ gösterir.
    /// Ölçüm yoksa ya da sıfırsa yön YOKTUR (nötr ton).
    var hasDirection: Bool { hasData && !isFlat }

    /// Veri hiç yazılmamışken gösterilen hâl.
    ///
    /// "₺0" DEĞİL: sıfır bir büyüklüktür ve kullanıcı portföyünün silindiğini
    /// sanabilir. Tire, "henüz ölçüm yok" der.
    static let placeholder = SandikEntry(
        date: Date(),
        total: "—",
        change: "",
        changePct: "",
        isPositive: true,
        isFlat: true,
        hasData: false,
        updatedAt: "",
        dateLabel: "",
        isMarketOpen: false,
        isLight: false,
        sparkline: []
    )
}

struct SandikProvider: TimelineProvider {

    private func read() -> SandikEntry {
        guard let defaults = UserDefaults(suiteName: WidgetKeys.suite) else {
            return .placeholder
        }
        guard defaults.bool(forKey: WidgetKeys.hasData) else {
            return .placeholder
        }

        // Seri "0.412,0.508,…" biçiminde gelir. Bozuk parça atlanır —
        // tek kötü değer yüzünden grafiğin tamamı kaybolmamalı.
        let seri = (defaults.string(forKey: WidgetKeys.sparkSeries) ?? "")
            .split(separator: ",")
            .compactMap { Double($0) }

        return SandikEntry(
            date: Date(),
            total: defaults.string(forKey: WidgetKeys.total) ?? "—",
            change: defaults.string(forKey: WidgetKeys.change) ?? "",
            changePct: defaults.string(forKey: WidgetKeys.changePct) ?? "",
            isPositive: defaults.bool(forKey: WidgetKeys.isPositive),
            isFlat: defaults.bool(forKey: WidgetKeys.isFlat),
            hasData: true,
            updatedAt: defaults.string(forKey: WidgetKeys.updatedAt) ?? "",
            dateLabel: defaults.string(forKey: WidgetKeys.date) ?? "",
            isMarketOpen: defaults.bool(forKey: WidgetKeys.marketOpen),
            isLight: defaults.bool(forKey: WidgetKeys.isLightTheme),
            sparkline: seri
        )
    }

    func placeholder(in context: Context) -> SandikEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SandikEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SandikEntry>) -> Void) {
        // Tek girdi, `.never` politikası: veriyi uygulama yazar ve yazdıktan
        // sonra `WidgetCenter.reloadAllTimelines()` çağırır (home_widget
        // paketi bunu yapar). Zamana bağlı yenileme boşuna bütçe harcardı —
        // widget kendi başına ağa çıkmıyor, bekleyecek yeni verisi yok.
        completion(Timeline(entries: [read()], policy: .never))
    }
}

// MARK: - Görünüm

struct SandikHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SandikEntry

    private var palette: SandikPalette { .resolved(isLight: entry.isLight) }

    private var accent: Color {
        entry.hasDirection
            ? palette.statusColor(isPositive: entry.isPositive)
            : palette.text58
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            baslik
            Spacer(minLength: 6)
            tutar
            if family != .systemSmall, !entry.sparkline.isEmpty {
                Spacer(minLength: 8)
                SandikSparkline(
                    points: entry.sparkline,
                    palette: palette,
                    color: accent,
                    // Dar alanda gradient dolgu gürültüye dönüşüyor —
                    // kilit ekranındaki kompakt görünümle aynı karar.
                    showsFill: family == .systemLarge,
                    isMarketOpen: entry.isMarketOpen
                )
                .frame(height: family == .systemLarge ? 64 : 36)
            }
            Spacer(minLength: 6)
            altBilgi
        }
    }

    private var baslik: some View {
        HStack(spacing: 6) {
            // Boyut `width` ile verilir; `frame` ile ezmek 80:50 oranını
            // bozardı (yükseklik genişlikten türetiliyor).
            SandikLogoMark(width: 16)
            Text("sandık")
                .font(.sandikLabel(12, weight: .bold))
                .foregroundColor(palette.text58)
            Spacer(minLength: 0)
            if !entry.isMarketOpen && entry.hasData {
                // Rakamın neden değişmediğini söyler. Bu olmadan kullanıcı
                // widget'ı bozuk sanıyor.
                Text("Kapalı")
                    .font(.sandikLabel(10, weight: .semibold))
                    .foregroundColor(palette.text36)
            }
        }
    }

    private var tutar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.total)
                .font(.sandikNumber(family == .systemSmall ? 20 : 26))
                .foregroundColor(palette.text90)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if entry.hasData, !entry.change.isEmpty {
                HStack(spacing: 4) {
                    // İşaret yalnızca RENKLE anlatılmaz: ok her zaman yanında.
                    if entry.hasDirection {
                        Text(entry.isPositive ? "▲" : "▼")
                            .font(.sandikLabel(10, weight: .bold))
                            .foregroundColor(accent)
                    }
                    Text(entry.change)
                        .font(.sandikNumber(13, weight: .semibold))
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !entry.changePct.isEmpty, family != .systemSmall {
                        Text(entry.changePct)
                            .font(.sandikNumber(11, weight: .medium))
                            .foregroundColor(palette.text36)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var altBilgi: some View {
        HStack(spacing: 0) {
            Text(entry.hasData ? entry.dateLabel : "Uygulamayı açıp portföyünü ekle")
                .font(.sandikLabel(10, weight: .medium))
                .foregroundColor(palette.text36)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if entry.hasData, !entry.updatedAt.isEmpty {
                Text(entry.updatedAt)
                    .font(.sandikNumber(10, weight: .medium))
                    .foregroundColor(palette.text20)
            }
        }
    }
}

// MARK: - Widget tanımı

struct SandikHomeWidget: Widget {
    /// `HomeWidgetService._iOSWidgetName` ile aynı olmalı.
    let kind = "SandikWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SandikProvider()) { entry in
            // `containerBackground` iOS 17'de ZORUNLU: olmadan widget ana
            // ekranda beyaz bir levha olarak çizilir. Hedef minimumu 17.0
            // olduğu için koşulsuz kullanılabilir.
            SandikHomeWidgetView(entry: entry)
                .widgetURL(widgetClickURL)
                .containerBackground(for: .widget) {
                    SandikPalette.resolved(isLight: entry.isLight).background
                }
        }
        .configurationDisplayName("sandık")
        .description("Portföyünün toplamı ve günlük değişimi.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
