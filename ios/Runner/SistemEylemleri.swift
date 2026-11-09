import AppIntents
import CoreSpotlight
import Flutter
import UIKit
import UniformTypeIdentifiers

/// Siri Kestirmeleri ve Spotlight aramasının uygulamaya köprüsü (2026-10-19).
///
/// ## Neden
/// yasin (Ar-Ge fikir turu 1, 2026-10-19): ikon kısayolları (#219) ilk adımdı,
/// Siri ve Spotlight "sonraya" kalmıştı; aynı gün "arkadaşını getir dışındakileri
/// uygula" dendi. Amaç uygulamayı açmadan değer vermek ("Portföyüm ne durumda")
/// ve sık işe tek cümleyle girmek.
///
/// ## Akış
/// Uygulamayı açan eylemler (Siri "varlık ekle", Spotlight'ta varlığa dokunmak)
/// bekleyen eylemi `UserDefaults.standard`'a bırakır; Dart `al` ile TÜKETİR
/// (`lib/services/sistem_eylemleri.dart`). Kanal canlıysa `geldi` ile hemen
/// haber verilir; değilse (soğuk açılış) Dart açılışta ve her öne dönüşte
/// kendisi sorar. Yönlendirme ikon kısayoluyla AYNI yoldan gider
/// (`HizliEylemler.istek`): kilit atlatılmaz, giriş ekranının üstüne ekran açılmaz.
///
/// Spotlight dokunuşu bir eklenti değil, sahne olayıdır: `FlutterSceneDelegate`
/// alt sınıflanıp `scene(_:continue:)` ezilmez (Flutter'ın eklentilere
/// dağıtımını keserdi); bu sınıf `addSceneDelegate` ile sıraya girer.
final class SistemEylemleri: NSObject, FlutterSceneLifeCycleDelegate {
    static let kanalAdi = "com.sandik.app/sistem_eylemleri"
    static let bekleyenAnahtar = "sandik_bekleyen_sistem_eylemi"
    /// Spotlight öğe kimliği öneki; geri kalanı varlık (lot) id'si.
    static let varlikOnek = "varlik:"
    static let spotlightAlani = "com.sandik.app.varlik"

    private static let paylasilan = SistemEylemleri()
    private static var kanal: FlutterMethodChannel?

    static func register(registrar: FlutterPluginRegistrar) {
        let c = FlutterMethodChannel(name: kanalAdi, binaryMessenger: registrar.messenger())
        c.setMethodCallHandler { call, result in
            switch call.method {
            case "al":
                result(al())
            case "spotlightYaz":
                let ogeler = call.arguments as? [[String: String]] ?? []
                spotlightYaz(ogeler)
                result(nil)
            case "spotlightTemizle":
                spotlightYaz([])
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        kanal = c
        registrar.addSceneDelegate(paylasilan)
    }

    /// Eylemi bırakır ve kanal canlıysa Dart'a haber verir. Ana iş parçacığı:
    /// `invokeMethod` başka iş parçacığından çağrılamaz.
    @MainActor
    static func birak(_ eylem: String) {
        UserDefaults.standard.set(eylem, forKey: bekleyenAnahtar)
        kanal?.invokeMethod("geldi", arguments: nil)
    }

    private static func al() -> String? {
        let d = UserDefaults.standard
        let v = d.string(forKey: bekleyenAnahtar)
        d.removeObject(forKey: bekleyenAnahtar)
        return v
    }

    /// Alanı silip baştan yazar: kapanan pozisyon ve hesap değişimi ayrıca
    /// izlenmez, liste her zaman o anki hesabın açık pozisyonlarıdır. Tutar
    /// YAZILMAZ; yalnız ad ve sembol (dizin cihazda kalır).
    private static func spotlightYaz(_ ogeler: [[String: String]]) {
        let dizin = CSSearchableIndex.default()
        let kayitlar: [CSSearchableItem] = ogeler.compactMap { o in
            guard let id = o["id"], let baslik = o["baslik"] else { return nil }
            let nitelik = CSSearchableItemAttributeSet(contentType: UTType.content)
            nitelik.title = baslik
            nitelik.contentDescription = o["aciklama"]
            nitelik.keywords = [o["sembol"], baslik, "Sandık"].compactMap { $0 }
            return CSSearchableItem(
                uniqueIdentifier: varlikOnek + id,
                domainIdentifier: spotlightAlani,
                attributeSet: nitelik)
        }
        dizin.deleteSearchableItems(withDomainIdentifiers: [spotlightAlani]) { _ in
            guard !kayitlar.isEmpty else { return }
            dizin.indexSearchableItems(kayitlar) { _ in }
        }
    }

    private func spotlightDokunusu(_ etkinlik: NSUserActivity) -> Bool {
        guard etkinlik.activityType == CSSearchableItemActionType,
              let kimlik = etkinlik.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              kimlik.hasPrefix(SistemEylemleri.varlikOnek) else { return false }
        Task { @MainActor in SistemEylemleri.birak(kimlik) }
        return true
    }

    // MARK: FlutterSceneLifeCycleDelegate

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
        // Soğuk açılış: Spotlight dokunuşu bağlantı seçeneklerinde gelir.
        guard let etkinlik = connectionOptions?.userActivities.first else { return false }
        return spotlightDokunusu(etkinlik)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
        spotlightDokunusu(userActivity)
    }
}

// MARK: - Siri / Kestirmeler

private var turkce: Bool {
    Locale.preferredLanguages.first?.hasPrefix("tr") ?? true
}

/// "Portföyüm ne durumda" — uygulamayı AÇMADAN ana ekran widget'ının yazdığı
/// özeti okur (`HomeWidgetService`, app group). Ayrı hesap yapılmaz: Siri'nin
/// söylediği sayı widget'ta görünenle aynı olmalı (fiyat kaynağı kuralı).
/// "Tutarları gizle" açıksa widget tutar yazmaz; Siri de söylemez. Kilitli
/// cihazda çalışmaz (`requiresAuthentication`): tutar sesli okunuyor.
struct PortfoyDurumuIntent: AppIntent {
    static let title: LocalizedStringResource = "Portföyüm ne durumda"
    static let description = IntentDescription("Sandık'taki toplamı ve bugünkü değişimi söyler.")
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cumle = PortfoyDurumuIntent.cumle(UserDefaults(suiteName: "group.com.sandik.app"))
        return .result(dialog: "\(cumle)")
    }

    static func cumle(_ d: UserDefaults?) -> String {
        guard let d, d.bool(forKey: "sandik_has_data") else {
            return turkce
                ? "Henüz özet yok. Sandık'ı bir kez açınca hazır olur."
                : "No summary yet. Open Sandık once and it will be ready."
        }
        if d.bool(forKey: "sandik_hidden") {
            return turkce
                ? "Tutarların gizli. Görmek için Sandık'ı aç."
                : "Your amounts are hidden. Open Sandık to see them."
        }
        let toplam = d.string(forKey: "sandik_total") ?? ""
        let fark = d.string(forKey: "sandik_change") ?? ""
        let yuzde = d.string(forKey: "sandik_change_pct") ?? ""
        let saat = d.string(forKey: "sandik_updated_at") ?? ""
        var s = turkce ? "Portföyün \(toplam)." : "Your portfolio is \(toplam)."
        // "—" = ölçüm yok (widget sözleşmesi); uydurma sıfır söylenmez.
        if !fark.isEmpty, fark != "—" {
            let ek = yuzde.isEmpty ? fark : "\(yuzde), \(fark)"
            s += turkce ? " Bugün \(ek)." : " Today \(ek)."
        }
        if !saat.isEmpty {
            s += turkce ? " Son güncelleme \(saat)." : " Updated \(saat)."
        }
        return s
    }
}

/// Uygulamayı açıp ikon kısayoluyla aynı ekrana götüren eylemler. Ad
/// `HizliEylem` enum adlarıyla birebir (Dart `HizliEylemler.cozumle`).
struct VarlikEkleIntent: AppIntent {
    static let title: LocalizedStringResource = "Varlık ekle"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        SistemEylemleri.birak("varlikEkle")
        return .result()
    }
}

struct AlarmKurIntent: AppIntent {
    static let title: LocalizedStringResource = "Alarm kur"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        SistemEylemleri.birak("alarmKur")
        return .result()
    }
}

struct AramaIntent: AppIntent {
    static let title: LocalizedStringResource = "Sandık'ta ara"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        SistemEylemleri.birak("arama")
        return .result()
    }
}

/// Kurulumsuz Siri cümleleri. Her cümle uygulama adını bir kez taşımak zorunda
/// (Apple kuralı). Türkçe ve İngilizce aynı listede: Siri cihaz diline uyanı eşler.
struct SandikKisayollari: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PortfoyDurumuIntent(),
            phrases: [
                "\(.applicationName) portföyüm ne durumda",
                "\(.applicationName) bugün nasıl",
                "How is my \(.applicationName) portfolio",
            ],
            shortTitle: "Portföy durumu",
            systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(
            intent: VarlikEkleIntent(),
            phrases: [
                "\(.applicationName) varlık ekle",
                "Add an asset in \(.applicationName)",
            ],
            shortTitle: "Varlık ekle",
            systemImageName: "plus.circle")
        AppShortcut(
            intent: AlarmKurIntent(),
            phrases: [
                "\(.applicationName) alarm kur",
                "Set an alert in \(.applicationName)",
            ],
            shortTitle: "Alarm kur",
            systemImageName: "bell.badge")
        AppShortcut(
            intent: AramaIntent(),
            phrases: [
                "\(.applicationName) ara",
                "Search in \(.applicationName)",
            ],
            shortTitle: "Ara",
            systemImageName: "magnifyingglass")
    }
}
