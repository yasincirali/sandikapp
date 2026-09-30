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
/// ## `?homeWidget` neden ZORUNLU
/// URL'yi Dart'a taşıyan `home_widget` eklentisi gelen URL'leri
/// `isWidgetUrl` ile süzüyor ve **yalnızca `homeWidget` adlı bir query
/// parametresi taşıyanları** kabul ediyor (`HomeWidgetPlugin.swift:462`).
/// Parametresiz URL sessizce düşer — uygulama açılır, dokunuş Dart'a hiç
/// ulaşmaz. Android tarafında böyle bir süzgeç yok; parametre orada
/// zararsızdır ve iki platform aynı URI'yi kullanabilsin diye eklendi.
private let widgetClickURL = URL(string: "sandik://widget/home?homeWidget=1")

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


// MARK: - Kilit ekranı widget'ı (karar 4.1 / 4.3 / 4.4 / 4.5, 2026-09-30)
//
// Ana ekran widget'ından AYRI tür: ana ekranın görünümü ve arka planı hiç
// değişmez. Veri aynı paylaşımlı depodan okunur; kilit ekranına özel dört
// anahtarı `HomeWidgetService` yazar (`_kLockAmounts`, `_kLockPct`,
// `_kPctNum`, `_kHidden`).
//
// Bu kod `SandikHomeWidget.swift` İÇİNDE, ayrı dosyada değil: uzantı hedefi
// dosyaları pbxproj'da tek tek listeliyor ve proje Windows'ta
// düzenleniyor — yeni dosya kaydı unutulursa widget sessizce hiç derlenmez.
//
// Kararlar:
// - TEK kart (kullanıcı kararı 2026-09-30, ikinci tur: "kilit ekranında 2
//   parçalı olmasın"). Yuvarlak widget kaldırıldı; renkli yuvarlak gösterge
//   Dinamik Ada'da yaşıyor (`SandikYonHalkasi`). iOS kilit ekranında en
//   geniş widget dikdörtgendir (satırın yarısı).
// - "Canlı seans kartı" (üçüncü tur: "göz alıcı olmalı, Apple'ın yeni
//   teknolojilerinden faydalanmalı"):
//     * Sistemin buzlu kart zemini (`AccessoryWidgetBackground`), üstünde
//       kartın alt yarısına YAYILMIŞ günün eğrisi — sayı grafiğin üstünde.
//     * Seans açıkken canlı çubuk + kapanışa geri sayım
//       (`ProgressView/Text(timerInterval:)`): uygulama açılmadan saniye
//       saniye akar, güncelleme bütçesi harcamaz.
//     * Zaman çizelgesi 18:00'de ikinci girdiyle kendiliğinden "kapalı"
//       görünüme geçer; kapalıyken sonraki açılışın günü ve saati.
//     * Tutar `privacySensitive`: telefon kilitliyken sistem örter, Face ID
//       ile bakınca görünür — ayar açıkken bile (iki kat gizlilik).
//     * Yüzde `numericText` geçişiyle değişir, `widgetAccentable` ile
//       renklendirilmiş kilit ekranında vurgu rengini alır.
// - "Bakiyeyi gizle" açıkken yüzde de, eğri de YOK — yalnız "••".
// - Kilit ekranı tek renkli (vibrant) çizer: renk yerine `.primary` /
//   `.secondary`; yön her zaman ▲/▼ ile.

private enum KilitKeys {
    static let lockAmounts = "sandik_lock_amounts"
    static let lockPct = "sandik_lock_pct"
    static let hidden = "sandik_hidden"
}

struct SandikKilitEntry: TimelineEntry {
    let date: Date
    let hasData: Bool
    let isHidden: Bool
    let showsAmount: Bool
    /// `+%0,42` / `−%0,06` / `%0,00` ya da `—`.
    let pctText: String
    let changeText: String
    let isPositive: Bool
    let isFlat: Bool
    let isMarketOpen: Bool
    let sparkline: [Double]

    /// Yön yalnız gerçek, görünür bir hareket varken (ana ekranla aynı kural).
    var hasDirection: Bool { hasData && !isHidden && !isFlat }

    /// Aynı veri, seans kapanmış olarak — zaman çizelgesinin 18:00 girdisi.
    func kapali(at tarih: Date) -> SandikKilitEntry {
        SandikKilitEntry(
            date: tarih, hasData: hasData, isHidden: isHidden,
            showsAmount: showsAmount, pctText: pctText, changeText: changeText,
            isPositive: isPositive, isFlat: isFlat, isMarketOpen: false,
            sparkline: sparkline)
    }

    static let placeholder = SandikKilitEntry(
        date: Date(),
        hasData: false,
        isHidden: false,
        showsAmount: false,
        pctText: "—",
        changeText: "",
        isPositive: true,
        isFlat: true,
        isMarketOpen: false,
        sparkline: []
    )
}

struct SandikKilitProvider: TimelineProvider {

    private func read() -> SandikKilitEntry {
        guard let defaults = UserDefaults(suiteName: WidgetKeys.suite),
              defaults.bool(forKey: WidgetKeys.hasData) else {
            return .placeholder
        }
        let gizli = defaults.bool(forKey: KilitKeys.hidden)
        // Gizliyken seri OKUNMAZ (Dart zaten siler; eski sürümden kalan
        // bir seri ihtimaline karşı burada da).
        let seri: [Double] = gizli ? [] :
            (defaults.string(forKey: WidgetKeys.sparkSeries) ?? "")
                .split(separator: ",")
                .compactMap { Double($0) }
        let yuzde = defaults.string(forKey: KilitKeys.lockPct) ?? ""
        return SandikKilitEntry(
            date: Date(),
            hasData: true,
            isHidden: gizli,
            showsAmount: defaults.bool(forKey: KilitKeys.lockAmounts) && !gizli,
            pctText: yuzde.isEmpty ? "—" : yuzde,
            changeText: defaults.string(forKey: WidgetKeys.change) ?? "",
            isPositive: defaults.bool(forKey: WidgetKeys.isPositive),
            isFlat: defaults.bool(forKey: WidgetKeys.isFlat),
            isMarketOpen: defaults.bool(forKey: WidgetKeys.marketOpen),
            sparkline: seri
        )
    }

    func placeholder(in context: Context) -> SandikKilitEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (SandikKilitEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SandikKilitEntry>) -> Void) {
        // Veriyi uygulama yazar ve yeniler (`.never`). Tek istisna seansın
        // bitişi: açıkken 18:00'e "kapalı" ikinci girdi eklenir — kart
        // uygulama açılmasa da kapanışta kendiliğinden döner, geri sayım
        // 0:00'da donup kalmaz.
        let simdi = read()
        var girdiler = [simdi]
        if simdi.isMarketOpen, let bitis = BistSeans.aralik()?.upperBound,
           bitis > Date() {
            girdiler.append(simdi.kapali(at: bitis))
        }
        completion(Timeline(entries: girdiler, policy: .never))
    }
}

struct SandikKilitView: View {
    let entry: SandikKilitEntry

    private var ok: String? {
        entry.hasDirection ? directionArrow(entry.isPositive) : nil
    }

    private var tutarGorunur: Bool {
        entry.showsAmount && !entry.isHidden && !entry.changeText.isEmpty
            && entry.changeText != "—"
    }

    /// Geçiş animasyonu için yüzdenin sayı karşılığı ("+%0,42" → 0.42).
    private var yuzdeSayi: Double {
        let rakam = entry.pctText
            .filter { $0.isNumber || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        let deger = Double(rakam) ?? 0
        return entry.pctText.contains("−") || entry.pctText.contains("-") ? -deger : deger
    }

    // ## Düzen: yüzde kartın kendisi (kullanıcı bildirimi, 2026-10-01)
    // "Kilit ekranında aşırı küçük kalmış — 12 mini'de bile." Dış boyut iOS'un
    // (dikdörtgen widget satırın yarısı, ~160×70 pt; büyütülemez). İçeride ise
    // üç eşit satır vardı: 11 pt "sandık" başlığı, 24 pt yüzde, 10 pt seans
    // satırı — yazının asıl sorusu olan yüzde kartın üçte birine sıkışıyordu.
    // Başlık satırı kalktı: kart zaten sandık'ın (kilit ekranı düzenleyicisi
    // uygulama adını gösterir), logo alt satırın başına küçük iner. Yüzde
    // ~29 pt, alt satır tek sıra: logo + tutar solda, geri sayım / açılış
    // sağda; seans çubuğu ikisinin arasında ince bir çizgi.

    var body: some View {
        ZStack(alignment: .topLeading) {
            AccessoryWidgetBackground()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Günün eğrisi kartın alt yarısına yayılır — sayı üstünde durur.
            if entry.hasData, !entry.isHidden, entry.sparkline.count >= 2 {
                SandikSparkline(
                    points: entry.sparkline,
                    color: .primary,
                    showsFill: true
                )
                .opacity(0.4)
                .padding(.top, 22)
                .padding(.bottom, 14)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                sayi
                Spacer(minLength: 0)
                seansCubugu
                altSatir
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var sayi: some View {
        if !entry.hasData {
            HStack(spacing: 5) {
                SandikLogoMark(width: 14)
                Text("Uygulamayı aç")
                    .font(.sandikLabel(15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else if entry.isHidden {
            Text("••")
                .font(.sandikNumber(30, weight: .bold))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let ok = ok {
                    Text(ok)
                        .font(.sandikLabel(17, weight: .black))
                }
                Text(entry.pctText)
                    .font(.sandikNumber(29, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    // Uzun yüzde ("+%12,34") ya da kısa kart (12 mini ~157×66 pt)
                    // taşırmasın: tek satır, yer yoksa küçülür.
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText(value: yuzdeSayi))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetAccentable()
        }
    }

    /// Seans açıkken kapanışa kadar dolan ince çubuk — uygulama kapalıyken de
    /// akar (`timerInterval`), güncelleme bütçesi harcamaz.
    @ViewBuilder
    private var seansCubugu: some View {
        if entry.hasData, !entry.isHidden, entry.isMarketOpen,
           let seans = BistSeans.aralik(), seans.upperBound > entry.date {
            ProgressView(timerInterval: seans, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .widgetAccentable()
        }
    }

    /// Logo + (izin varsa) tutar solda; sağda kapanışa geri sayım ya da
    /// sonraki açılış.
    private var altSatir: some View {
        HStack(spacing: 4) {
            SandikLogoMark(width: 10)
            if tutarGorunur {
                Text(entry.changeText)
                    .font(.sandikNumber(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Kilitliyken sistem örter; Face ID ile bakınca açılır.
                    .privacySensitive()
            }
            Spacer(minLength: 4)
            seansBilgisi
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var seansBilgisi: some View {
        if entry.hasData, !entry.isHidden {
            if entry.isMarketOpen, let seans = BistSeans.aralik(),
               seans.upperBound > entry.date {
                // Kapanışa kalan süre — saniye saniye, uygulama kapalıyken de.
                Text(timerInterval: entry.date...seans.upperBound, countsDown: true)
                    .font(.sandikNumber(12, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 58, alignment: .trailing)
            } else if let acilis = BistSeans.sonrakiAcilis(entry.date) {
                // "Seans kapalı ·" öneki kalktı: çubuk yokken "açılış" zaten
                // kapalı demektir; yer yüzdeye kaldı.
                HStack(spacing: 3) {
                    Text("açılış")
                        .font(.sandikLabel(11, weight: .medium))
                    Text(acilis, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.sandikNumber(12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }
}

struct SandikKilitWidget: Widget {
    /// `HomeWidgetService._iOSKilitWidgetName` ile aynı olmalı.
    let kind = "SandikKilitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SandikKilitProvider()) { entry in
            SandikKilitView(entry: entry)
                // Ana ekran widget'ıyla aynı hedef: Performans, günlük grafik.
                .widgetURL(widgetClickURL)
                // iOS 17'de zorunlu; kilit ekranında zemin sistemindir.
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("sandık")
        .description("Günün değişimi kilit ekranında. Tutar yalnız izin verirsen görünür.")
        .supportedFamilies([.accessoryRectangular])
    }
}
