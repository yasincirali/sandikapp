import AppIntents
import SwiftUI
import WidgetKit

/// Ana ekran widget'ı — TEK VARLIK (gram altın, dolar, bir fon…).
///
/// Ar-Ge kararı 2026-10-24 §1: önce yalnız iOS; varlık `AppIntentConfiguration`
/// ile seçilir; seçim listesi YALNIZ portföy + takip listesi (katalog araması
/// yok); kilit ekranı varyantı sonra; değişim ok + sayıyla (yalnız renk değil).
///
/// Veriyi Flutter tarafı yazar (`VarlikWidgetService` →
/// `HomeWidgetService.varlikListesiniYaz`), burada yalnızca okunur. Sözleşmeye
/// YALNIZ yeni bir anahtar eklendi (`sandik_varliklar`); portföy widget'ının
/// ve kilit ekranı widget'ının okuduğu anahtarlar ve biçimleri değişmedi.
///
/// ## Neden ayrı dosya
/// Kilit ekranı widget'ı pbxproj kaydı unutulmasın diye `SandikHomeWidget
/// .swift` içine yazılmıştı. Bu dosya pbxproj'a (dosya referansı + grup +
/// SandikWidgetExtension "Sources" fazı) kaydedildi; kayıt
/// `test/varlik_widget_sozlesmesi_test.dart` ile kilitli — kayıt düşerse
/// test kırılır, TestFlight hattına kırık proje gitmez.
///
/// ## Neden `@available` yok
/// `AppIntentConfiguration` ve `WidgetConfigurationIntent` iOS 17 ister;
/// uzantı hedefinin `IPHONEOS_DEPLOYMENT_TARGET` değeri zaten 17.0
/// (pbxproj, üç yapılandırmada da). Hedef düşürülürse derleme burada kırılır
/// — widget sessizce boş kalmaz (`SandikWidgetBundle` notuyla aynı karar).
///
/// Widget kendi başına ağa çıkmaz: fiyat yalnızca uygulama açıkken tazelenir.
/// Bu yüzden son güncelleme saati gösterilir.

// MARK: - Paylaşımlı veri

private enum VarlikWidgetKeys {
    static let suite = "group.com.sandik.app"
    /// `HomeWidgetService.kVarliklar` ile birebir aynı.
    static let varliklar = "sandik_varliklar"
    /// Portföy widget'ıyla aynı tema bayrağı (`HomeWidgetService._kIsLightTheme`).
    static let isLightTheme = "sandik_is_light_theme"
}

/// Dokunuş: Portföy sekmesi (Varlıklarım | Takip Listesi).
///
/// `DeepLinkRouter.varlikWidgetHost` ile aynı olmalı. `?homeWidget` ZORUNLU:
/// `home_widget` eklentisi iOS'ta yalnız bu parametreyi taşıyan URL'yi Dart'a
/// iletir (gerekçe `SandikHomeWidget.swift` › `widgetClickURL`).
private let varlikWidgetClickURL = URL(string: "sandik://varlik-widget?homeWidget=1")

/// Seçim listesindeki bir varlık — Dart `VarlikWidgetOgesi.toJson`.
///
/// Metinler Dart'ta biçimlenir (`fmtFiyat`, `fmtPctIsaretli`); burada sayı
/// yeniden biçimlenmez ya da hesaplanmaz. Eksik alan = bilinmiyor ("—").
struct SandikVarlikOgesi: Decodable, Hashable {
    /// Kotasyon sembolü (`ALTIN_GRAM24`, `USDTRY=X`, `TEFAS:AFT`) — seçimin
    /// saklanan kimliği.
    let id: String
    let ad: String
    let alt: String?
    let fiyat: String?
    let degisim: String?
    /// 1 artış, -1 düşüş, 0 değişim yok; yoksa bilinmiyor.
    let yon: Int?
}

/// `sandik_varliklar` paketinin tamamı — Dart `varlikWidgetPaketi`.
struct SandikVarlikPaketi: Decodable {
    let v: Int
    let saat: String?
    let ogeler: [SandikVarlikOgesi]

    /// Bu build'in tanıdığı tek biçim sürümü. Tanınmayan sürüm okunmaz:
    /// yanlış okunmuş bir fiyat göstermektense "liste yok" demek doğru.
    static let surum = 1

    static let bos = SandikVarlikPaketi(v: 1, saat: nil, ogeler: [])

    /// Paylaşımlı depodan okur. Anahtar yoksa, boşsa (oturum kapandı) ya da
    /// çözülemiyorsa boş paket.
    static func oku() -> SandikVarlikPaketi {
        guard let defaults = UserDefaults(suiteName: VarlikWidgetKeys.suite),
              let metin = defaults.string(forKey: VarlikWidgetKeys.varliklar),
              !metin.isEmpty,
              let veri = metin.data(using: .utf8),
              let paket = try? JSONDecoder().decode(SandikVarlikPaketi.self, from: veri),
              paket.v == surum
        else {
            return .bos
        }
        return paket
    }
}

// MARK: - Varlık seçimi (App Intents)

/// Düzenleme ekranında seçilen varlık.
///
/// Kimlik kotasyon sembolüdür; kullanıcıya ya da bir lot'a ait değildir.
/// Liste yalnız uygulamanın yazdığı paketten gelir (katalog araması yok).
struct SandikVarlikEntity: AppEntity {
    let id: String
    let ad: String
    let alt: String?

    init(id: String, ad: String, alt: String?) {
        self.id = id
        self.ad = ad
        self.alt = alt
    }

    init(oge: SandikVarlikOgesi) {
        self.init(id: oge.id, ad: oge.ad, alt: oge.alt)
    }

    // Metin LİTERAL döner (Xcode şablonuyla aynı biçim): App Intents meta
    // veri çıkarıcısı bu değerleri derleme anında okur.
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Varlık" }

    static var defaultQuery: SandikVarlikQuery { SandikVarlikQuery() }

    var displayRepresentation: DisplayRepresentation {
        if let alt = alt, !alt.isEmpty {
            return DisplayRepresentation(title: "\(ad)", subtitle: "\(alt)")
        }
        return DisplayRepresentation(title: "\(ad)")
    }
}

/// Seçim listesi: portföy + takip listesi, uygulamanın son yazdığı sırayla.
struct SandikVarlikQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SandikVarlikEntity] {
        let ogeler = SandikVarlikPaketi.oku().ogeler
        return identifiers.compactMap { kimlik in
            ogeler.first(where: { $0.id == kimlik }).map { SandikVarlikEntity(oge: $0) }
        }
    }

    func suggestedEntities() async throws -> [SandikVarlikEntity] {
        SandikVarlikPaketi.oku().ogeler.map { SandikVarlikEntity(oge: $0) }
    }

    /// Widget ilk eklendiğinde listenin başı (portföyün ilk varlığı).
    func defaultResult() async -> SandikVarlikEntity? {
        SandikVarlikPaketi.oku().ogeler.first.map { SandikVarlikEntity(oge: $0) }
    }
}

struct SandikVarlikSecimi: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Varlık seç" }

    static var description: IntentDescription {
        "Widget'ta görünecek varlığı seç. Liste, portföyündeki ve takip listendeki varlıklardan oluşur."
    }

    @Parameter(title: "Varlık")
    var varlik: SandikVarlikEntity?

    init() {}
}

// MARK: - Zaman çizelgesi

struct SandikVarlikEntry: TimelineEntry {
    enum Durum {
        /// Seçili (ya da varsayılan) varlık.
        case oge(SandikVarlikOgesi)
        /// Seçilen varlık artık listede değil (takipten çıkarıldı / satıldı).
        case listedeYok(String)
        /// Uygulama henüz liste yazmadı ya da oturum kapalı.
        case listeBos
    }

    let date: Date
    let durum: Durum
    let saat: String
    let isLight: Bool

    /// Önizleme / yer tutucu. Fiyat UYDURULMAZ: "—".
    static let ornek = SandikVarlikEntry(
        date: Date(),
        durum: .oge(SandikVarlikOgesi(
            id: "ALTIN_GRAM24", ad: "Gram altın", alt: nil,
            fiyat: "—", degisim: nil, yon: nil)),
        saat: "",
        isLight: false
    )
}

struct SandikVarlikProvider: AppIntentTimelineProvider {

    private func oku(_ secim: SandikVarlikSecimi) -> SandikVarlikEntry {
        let paket = SandikVarlikPaketi.oku()
        let isLight = UserDefaults(suiteName: VarlikWidgetKeys.suite)?
            .bool(forKey: VarlikWidgetKeys.isLightTheme) ?? false
        let saat = paket.saat ?? ""

        let durum: SandikVarlikEntry.Durum
        if paket.ogeler.isEmpty {
            durum = .listeBos
        } else if let secili = secim.varlik {
            if let oge = paket.ogeler.first(where: { $0.id == secili.id }) {
                durum = .oge(oge)
            } else {
                durum = .listedeYok(secili.ad)
            }
        } else if let ilk = paket.ogeler.first {
            durum = .oge(ilk)
        } else {
            durum = .listeBos
        }
        return SandikVarlikEntry(date: Date(), durum: durum, saat: saat, isLight: isLight)
    }

    func placeholder(in context: Context) -> SandikVarlikEntry { .ornek }

    func snapshot(for configuration: SandikVarlikSecimi, in context: Context) async -> SandikVarlikEntry {
        let girdi = oku(configuration)
        // Galeride liste boşsa örnek göster; boş "Uygulamayı aç" kartı
        // widget'ın ne yaptığını anlatmaz.
        if context.isPreview, case .listeBos = girdi.durum {
            return .ornek
        }
        return girdi
    }

    func timeline(for configuration: SandikVarlikSecimi, in context: Context) async -> Timeline<SandikVarlikEntry> {
        // Portföy widget'ıyla aynı karar: veriyi uygulama yazar ve yazınca
        // bu türü yeniler (`.never`). Zamanlı yenileme boşuna bütçe harcardı.
        Timeline(entries: [oku(configuration)], policy: .never)
    }
}

// MARK: - Görünüm

struct SandikVarlikView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SandikVarlikEntry

    private var palette: SandikPalette { .resolved(isLight: entry.isLight) }

    var body: some View {
        switch entry.durum {
        case .oge(let oge):
            ogeGorunumu(oge)
        case .listedeYok(let ad):
            bilgi(baslik: ad, metin: "Bu varlık artık listende yok. Değiştirmek için widget'a basılı tut.")
        case .listeBos:
            bilgi(baslik: "sandık", metin: "Uygulamayı aç; portföyündeki ve takip listendeki varlıklar burada seçilebilir.")
        }
    }

    private func ogeGorunumu(_ oge: SandikVarlikOgesi) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SandikLogoMark(width: 14)
                Text(oge.ad)
                    .font(.sandikLabel(13, weight: .bold))
                    .foregroundColor(palette.text90)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let alt = oge.alt, !alt.isEmpty {
                Text(alt)
                    .font(.sandikLabel(10, weight: .medium))
                    .foregroundColor(palette.text58)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            Spacer(minLength: 4)
            Text(oge.fiyat ?? "—")
                .font(.sandikNumber(family == .systemSmall ? 22 : 26))
                .foregroundColor(palette.text90)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            degisimSatiri(oge)
                .padding(.top, 2)
            Spacer(minLength: 4)
            if !entry.saat.isEmpty {
                Text(entry.saat)
                    .font(.sandikNumber(10, weight: .medium))
                    .foregroundColor(palette.text20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Tek öğe olarak okunur: "Gram altın, ₺6.123,45, günlük artış +%0,42".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisimMetni(oge))
    }

    /// Yön yalnız renkle verilmez: ▲/▼ ve işaretli yüzde her zaman yanında.
    @ViewBuilder
    private func degisimSatiri(_ oge: SandikVarlikOgesi) -> some View {
        if let degisim = oge.degisim, !degisim.isEmpty {
            HStack(spacing: 4) {
                if let ok = okIsareti(oge.yon) {
                    Text(ok)
                        .font(.sandikLabel(10, weight: .bold))
                        .foregroundColor(renk(oge.yon))
                }
                Text(degisim)
                    .font(.sandikNumber(13, weight: .semibold))
                    .foregroundColor(renk(oge.yon))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("günlük")
                    .font(.sandikLabel(10, weight: .medium))
                    .foregroundColor(palette.text36)
                    .lineLimit(1)
            }
        } else {
            // Ölçüm yok: yüzde uydurulmaz.
            Text("Günlük değişim yok")
                .font(.sandikLabel(10, weight: .medium))
                .foregroundColor(palette.text36)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func okIsareti(_ yon: Int?) -> String? {
        guard let yon = yon, yon != 0 else { return nil }
        return yon > 0 ? "▲" : "▼"
    }

    /// Değişim yoksa ya da yön bilinmiyorsa nötr ton (portföy widget'ıyla
    /// aynı kural: düz bir değeri kırmızı göstermek "kaybettim" okunur).
    private func renk(_ yon: Int?) -> Color {
        guard let yon = yon, yon != 0 else { return palette.text58 }
        return palette.statusColor(isPositive: yon > 0)
    }

    private func erisimMetni(_ oge: SandikVarlikOgesi) -> String {
        var parcalar: [String] = [oge.ad, oge.fiyat ?? "fiyat yok"]
        if let degisim = oge.degisim, !degisim.isEmpty {
            let yon = oge.yon ?? 0
            if yon > 0 {
                parcalar.append("günlük artış \(degisim)")
            } else if yon < 0 {
                parcalar.append("günlük düşüş \(degisim)")
            } else {
                parcalar.append("günlük değişim yok")
            }
        } else {
            parcalar.append("günlük değişim yok")
        }
        if !entry.saat.isEmpty {
            parcalar.append("\(entry.saat) itibarıyla")
        }
        return parcalar.joined(separator: ", ")
    }

    private func bilgi(baslik: String, metin: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SandikLogoMark(width: 14)
                Text(baslik)
                    .font(.sandikLabel(13, weight: .bold))
                    .foregroundColor(palette.text90)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(metin)
                .font(.sandikLabel(11, weight: .medium))
                .foregroundColor(palette.text58)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget tanımı

struct SandikVarlikWidget: Widget {
    /// `HomeWidgetService.iOSVarlikWidgetName` ile aynı olmalı.
    let kind = "SandikVarlikWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SandikVarlikSecimi.self,
            provider: SandikVarlikProvider()
        ) { entry in
            SandikVarlikView(entry: entry)
                .widgetURL(varlikWidgetClickURL)
                // iOS 17'de zorunlu (bkz. `SandikHomeWidget`).
                .containerBackground(for: .widget) {
                    SandikPalette.resolved(isLight: entry.isLight).background
                }
        }
        .configurationDisplayName("Tek varlık")
        .description("Seçtiğin varlığın fiyatı ve günlük değişimi: gram altın, dolar, bir fon…")
        .supportedFamilies([.systemSmall])
    }
}
