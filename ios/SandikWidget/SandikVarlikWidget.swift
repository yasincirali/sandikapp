import AppIntents
import SwiftUI
import WidgetKit

/// Ana ekran widget'ı — TEK VARLIK (gram altın, dolar, bir fon…).
///
/// Ar-Ge kararı 2026-10-24 §1: önce yalnız iOS; varlık `AppIntentConfiguration`
/// ile seçilir; seçim listesi YALNIZ portföy + takip listesi (katalog araması
/// yok); kilit ekranı varyantı sonra; değişim ok + sayıyla (yalnız renk değil).
///
/// Ar-Ge 2026-10-25 §2: kilit ekranı geldi — aynı widget `accessoryRectangular`
/// (ad, fiyat, ok + işaretli yüzde) ve `accessoryInline` (tek satır, kısa ad).
/// Veri, seçim ve yazma noktası aynı; yalnız görünüm eklendi. Mevcut portföy
/// kilit widget'ı (`SandikKilitWidget`) bundan habersiz.
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
/// Fiyat uygulama açıkken tazelenir; son güncelleme saati gösterilir.
///
/// ## Uygulama açılmadan tazeleme (yasin onayı 2026-10-26)
/// Seçili varlık SUNUCU KAPSAMINDAYSA (öğede `sunucu == true`: altın, TL
/// döviz, kripto — karar Dart'ta, `FiyatKaynagi.widgetSunucuKapsamindaMi`)
/// zaman çizelgesi yarım saatte bir yenilenir ve fiyat `widget-fiyat` edge
/// function'ından çekilir (`SandikWidgetFiyatServisi`). Çağrı uygulamanın
/// yazdığı public URL + anon anahtarla yapılır; oturum jetonu widget'ta YOK.
/// Başarısızsa son bilinen değer saatiyle kalır (bugünkü davranış). Kapsam
/// dışı varlıkta (BIST, fon, endeks) widget ağa çıkmaz, `.never` sürer.

// MARK: - Paylaşımlı veri

private enum VarlikWidgetKeys {
    static let suite = "group.com.sandik.app"
    /// `HomeWidgetService.kVarliklar` ile birebir aynı.
    static let varliklar = "sandik_varliklar"
    /// Portföy widget'ıyla aynı tema bayrağı (`HomeWidgetService._kIsLightTheme`).
    static let isLightTheme = "sandik_is_light_theme"
    /// `HomeWidgetService.kWidgetApiUrl` / `kWidgetApiAnahtar`: aktif sunucunun
    /// public URL'si ve anon anahtarı (uygulama yazar).
    static let apiUrl = "sandik_widget_api_url"
    static let apiAnahtar = "sandik_widget_api_anahtar"
    /// `HomeWidgetService.kVarlikCanli`: widget'ın sunucudan çektiği son
    /// fiyatlar. Yalnız burada YAZILIR; oturum kapanınca Dart boşaltır.
    static let canli = "sandik_varlik_canli"
}

/// Dokunuş: Portföy sekmesi (Varlıklarım | Takip Listesi).
///
/// `DeepLinkRouter.varlikWidgetHost` ile aynı olmalı. `?homeWidget` ZORUNLU:
/// `home_widget` eklentisi iOS'ta yalnız bu parametreyi taşıyan URL'yi Dart'a
/// iletir (gerekçe `SandikHomeWidget.swift` › `widgetClickURL`).
private let varlikWidgetClickURL = URL(string: "sandik://varlik-widget?homeWidget=1")

/// Seçim listesindeki bir varlık — Dart `VarlikWidgetOgesi.toJson`.
///
/// Metinler Dart'ta biçimlenir (`fmtFiyat`, `fmtPctIsaretli`); uygulamanın
/// yazdığı sayı burada yeniden biçimlenmez ya da hesaplanmaz. Tek istisna
/// widget'ın SUNUCUDAN kendi çektiği fiyat (`canliIle`): o sayı Dart'ın
/// kuralıyla (`SandikWidgetBicim`) biçimlenir. Eksik alan = bilinmiyor ("—").
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
    /// Tek satırlık kilit ekranı için kısa ad ("Gr altın"); yoksa `ad`.
    /// Bu ve aşağıdaki alanlar isteğe bağlı (2026-10-25): eski paket de okunur.
    var kisa: String? = nil
    /// Yazım anında seans kapalıydı: fiyat son kapanış. Karar Dart'ta
    /// (`borsaTakvimindeMi` + `BugunService.seansAcikMi`, tatil dahil);
    /// kripto/altın/döviz bu alanı hiç almaz.
    var kapanis: Bool? = nil
    /// Yazım anında seans açıktı: bugünkü kapanış (epoch ms). Bu andan sonra
    /// fiyat kapanıştan önceki bir an — "Kapanış" denmez, saat yazılır.
    var seansSonu: Double? = nil
    /// `true`: fiyat `widget-fiyat`'tan tazelenebilir (2026-10-26). Yoksa
    /// widget bu öğe için ağa çıkmaz.
    var sunucu: Bool? = nil
    /// Sunucudan gelen fiyatın azami ondalığı (Dart `fmtFiyat` `azami`);
    /// yoksa eski kural (`fiyatOndaligi`).
    var hane: Int? = nil

    var gorunenKisaAd: String {
        if let kisa = kisa, !kisa.isEmpty { return kisa }
        return ad
    }

    /// Aynı öğe, sunucudan çekilen fiyatla. Yüzdeyi sunucu bilmiyorsa
    /// `nil` — uygulamanın eski yüzdesi YENİ fiyatın yanında kalmaz
    /// (farklı anların sayısı birleşmez; satır "değişim yok" der).
    /// Kapanış/seans alanları düşer: kapsamdaki türler (altın, döviz,
    /// kripto) zaten hiç almaz.
    func canliIle(_ c: SandikCanliFiyat) -> SandikVarlikOgesi {
        let yuzde = c.degisim.map { SandikWidgetBicim.yuzde($0) }
        return SandikVarlikOgesi(
            id: id, ad: ad, alt: alt,
            fiyat: SandikWidgetBicim.fiyat(c.fiyat, hane: hane),
            degisim: yuzde?.metin,
            yon: yuzde?.yon,
            kisa: kisa,
            kapanis: nil,
            seansSonu: nil,
            sunucu: sunucu,
            hane: hane)
    }
}

/// `widget-fiyat` yanıtındaki tek sembol: TL fiyat, kaynağın yazım anı
/// (epoch ms) ve günlük yüzde (bilinmiyorsa yok).
struct SandikCanliFiyat: Codable, Hashable {
    let fiyat: Double
    let zaman: Double
    var degisim: Double? = nil

    var gecerli: Bool { fiyat.isFinite && fiyat > 0 && zaman.isFinite && zaman > 0 }

    var tarih: Date { Date(timeIntervalSince1970: zaman / 1000) }
}

/// Dart `tr_format.dart` kurallarının Swift eşi — YALNIZ widget'ın sunucudan
/// çektiği sayı için. `fmtFiyat` (`fiyatBicimi`) ve `fmtPctIsaretli` ile
/// aynı çıktı: `₺6.123,45`, `+%0,42`, `−%0,06`, `%0,00`.
enum SandikWidgetBicim {
    private static func bicimci(enAz: Int, enCok: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        f.roundingMode = .halfUp
        f.minimumFractionDigits = enAz
        f.maximumFractionDigits = enCok
        return f
    }

    /// Dart `fiyatOndaligi`: 1 ₺ ve üstü 2 hane; altı en az 4 anlamlı hane
    /// (en çok 8).
    static func fiyatOndaligi(_ deger: Double) -> Int {
        let a = abs(deger)
        if a > 0 && a < 1 {
            return min(max(Int(floor(-log10(a))) + 4, 2), 8)
        }
        return 2
    }

    /// Dart `fmtFiyat(deger, azami: hane)`.
    static func fiyat(_ deger: Double, hane: Int?) -> String {
        let f: NumberFormatter
        if let hane = hane {
            f = bicimci(enAz: 2, enCok: max(2, hane))
        } else {
            let d = fiyatOndaligi(deger)
            f = bicimci(enAz: d, enCok: d)
        }
        return "₺" + (f.string(from: NSNumber(value: deger)) ?? "")
    }

    /// Dart `fmtPctIsaretli` + yön (`varlikWidgetOgesi`): sıfıra yuvarlanan
    /// değer işaretsiz ve yönsüz.
    static func yuzde(_ pct: Double) -> (metin: String, yon: Int) {
        let f = bicimci(enAz: 2, enCok: 2)
        let mutlak = "%" + (f.string(from: NSNumber(value: abs(pct))) ?? "")
        let sifir = "%" + (f.string(from: NSNumber(value: 0.0)) ?? "")
        if mutlak == sifir { return (mutlak, 0) }
        return pct > 0 ? ("+" + mutlak, 1) : ("\u{2212}" + mutlak, -1)
    }

    /// Dart `DateFormat('HH:mm', 'tr_TR')` / `'d MMM HH:mm'`.
    static func saat(_ an: Date) -> String { tarihci("HH:mm").string(from: an) }
    static func tarih(_ an: Date) -> String { tarihci("d MMM HH:mm").string(from: an) }

    private static func tarihci(_ kalip: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = kalip
        return f
    }
}

/// `widget-fiyat` istemcisi ve widget'ın kendi fiyat deposu.
///
/// Yalnız `sunucu == true` öğe için çağrılır. Uygulamanın yazdığı public
/// URL + anon anahtar kullanılır (ikisi de uygulama paketinde gömülü kamuya
/// açık değerler); oturum jetonu YOK, kişisel veri gitmez — gövde yalnız
/// sembol. Her hata sessizce `nil`: widget son bilinen değerle kalır.
enum SandikWidgetFiyatServisi {
    /// Zaman çizelgesi bu aralıkla yenilenir (WidgetKit bütçesi; sunucu
    /// yanıtı da 60 sn önbellekli).
    static let tazelemeAraligi: TimeInterval = 30 * 60
    /// Bilinen fiyat bundan tazeyse ağa çıkılmaz (uygulama az önce yazdı ya
    /// da önceki tur yeni çekti).
    static let tazeEsigi: TimeInterval = 10 * 60
    /// Kısa: WidgetKit zaman çizelgesini uzun bekletmek istemez.
    static let zamanAsimi: TimeInterval = 8
    /// Depoda en çok bu kadar sembol (yalnız seçili olanlar birikir).
    static let depoSiniri = 20

    /// Widget'ın daha önce çektiği fiyatlar (sembol → fiyat).
    static func depo() -> [String: SandikCanliFiyat] {
        guard let defaults = UserDefaults(suiteName: VarlikWidgetKeys.suite),
              let metin = defaults.string(forKey: VarlikWidgetKeys.canli),
              !metin.isEmpty,
              let veri = metin.data(using: .utf8),
              let sozluk = try? JSONDecoder().decode([String: SandikCanliFiyat].self, from: veri)
        else {
            return [:]
        }
        return sozluk.filter { $0.value.gecerli }
    }

    private static func depoyaYaz(_ sembol: String, _ c: SandikCanliFiyat) {
        guard let defaults = UserDefaults(suiteName: VarlikWidgetKeys.suite) else { return }
        var sozluk = depo()
        sozluk[sembol] = c
        if sozluk.count > depoSiniri {
            let enEskiler = sozluk.sorted { $0.value.zaman < $1.value.zaman }
                .prefix(sozluk.count - depoSiniri)
            for (anahtar, _) in enEskiler {
                sozluk.removeValue(forKey: anahtar)
            }
        }
        guard let veri = try? JSONEncoder().encode(sozluk),
              let metin = String(data: veri, encoding: .utf8)
        else { return }
        defaults.set(metin, forKey: VarlikWidgetKeys.canli)
    }

    /// Sembolün güncel fiyatını sunucudan çeker ve depoya yazar.
    static func cek(_ sembol: String) async -> SandikCanliFiyat? {
        guard let defaults = UserDefaults(suiteName: VarlikWidgetKeys.suite),
              let taban = defaults.string(forKey: VarlikWidgetKeys.apiUrl),
              let anahtar = defaults.string(forKey: VarlikWidgetKeys.apiAnahtar),
              !anahtar.isEmpty,
              let kok = URL(string: taban),
              kok.scheme == "https"
        else {
            return nil
        }
        let hedef = kok.appendingPathComponent("functions/v1/widget-fiyat")
        var istek = URLRequest(
            url: hedef, cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: zamanAsimi)
        istek.httpMethod = "POST"
        istek.setValue("application/json", forHTTPHeaderField: "Content-Type")
        istek.setValue(anahtar, forHTTPHeaderField: "apikey")
        istek.setValue("Bearer \(anahtar)", forHTTPHeaderField: "Authorization")
        guard let govde = try? JSONSerialization.data(withJSONObject: ["semboller": [sembol]])
        else { return nil }
        istek.httpBody = govde

        let ayar = URLSessionConfiguration.ephemeral
        ayar.timeoutIntervalForRequest = zamanAsimi
        ayar.timeoutIntervalForResource = zamanAsimi
        let oturum = URLSession(configuration: ayar)
        defer { oturum.finishTasksAndInvalidate() }
        do {
            let (veri, yanit) = try await oturum.data(for: istek)
            guard let http = yanit as? HTTPURLResponse, http.statusCode == 200,
                  let sozluk = try? JSONDecoder().decode([String: SandikCanliFiyat].self, from: veri),
                  let c = sozluk[sembol], c.gecerli
            else {
                return nil
            }
            depoyaYaz(sembol, c)
            return c
        } catch {
            return nil
        }
    }
}

/// Sunucudan tazelenen widget'ın ritmi — Android `WidgetRitmi` ile birebir
/// (müşteri raporu 2026-10-26 21:15 #2/#3, yasin "yap").
///
/// Neden: her widget her çağrıda bir Edge Function çağrısı ve log satırı
/// harcar (ücretsiz plan ayda 500.000 çağrı, 1 GB log). Kullanıcının
/// bakmadığı saatte yarım saatlik ritim boşa gider:
/// - gece 00:00–07:00 TR: 2 saatte bir;
/// - hafta sonu altın/döviz (kotasyon az oynar): saatte bir; kripto 7/24
///   olduğu için hafta sonu gündüz yarım saatte bir kalır;
/// - fon: NAV günde bir değişir. İş günü 07:00–22:00 TR arasında bugünün
///   NAV'ı henüz alınmadıysa saatte bir denenir; alındıysa ya da pencere
///   dışındaysa sonraki iş gününün 07:00'sine kadar beklenir.
/// "Bugünün NAV'ı alındı" = widget'ın sunucudan çektiği fiyatın anı (fon
/// için NAV'ın sunucuda İLK görüldüğü an) bugüne (TR) ait. Uygulamanın
/// yazım anı sayılmaz: uygulama sabah NAV yayımlanmadan açıldıysa dünkü
/// NAV'ı bugünün saatiyle yazmış olur.
enum SandikWidgetRitmi {
    static let gece: TimeInterval = 2 * 60 * 60
    static let haftaSonu: TimeInterval = 60 * 60
    static let fonDeneme: TimeInterval = 60 * 60
    static let geceSonu = 7
    static let fonPencereSonu = 22

    private static var takvim: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        return c
    }

    static func fonMu(_ sembol: String) -> Bool { sembol.hasPrefix("TEFAS:") }
    static func kriptoMu(_ sembol: String) -> Bool { sembol.hasPrefix("KRIPTO:") }

    private static func isGunu(_ d: Date) -> Bool {
        let g = takvim.component(.weekday, from: d) // 1 = Pazar, 7 = Cumartesi
        return g != 1 && g != 7
    }

    private static func fonPenceresinde(_ d: Date) -> Bool {
        let saat = takvim.component(.hour, from: d)
        return isGunu(d) && saat >= geceSonu && saat < fonPencereSonu
    }

    private static func bugunAlindi(_ canliZaman: Date?, _ simdi: Date) -> Bool {
        guard let z = canliZaman else { return false }
        return takvim.isDate(z, inSameDayAs: simdi)
    }

    /// Fiyat şimdi sunucudan çekilmeli mi (bilinen fiyatın 10 dk tazelik
    /// kuralına ek olarak). Fonda pencere dışında ya da bugünün NAV'ı
    /// alındıysa çağrı yapılmaz.
    static func cekilmeli(_ sembol: String, simdi: Date, canliZaman: Date?) -> Bool {
        guard fonMu(sembol) else { return true }
        return fonPenceresinde(simdi) && !bugunAlindi(canliZaman, simdi)
    }

    /// Zaman çizelgesinin sonraki yenileme anı.
    static func sonraki(_ sembol: String, simdi: Date, canliZaman: Date?) -> Date {
        if fonMu(sembol) {
            if cekilmeli(sembol, simdi: simdi, canliZaman: canliZaman) {
                return simdi.addingTimeInterval(fonDeneme)
            }
            return sonrakiIsGunuSabahi(simdi)
        }
        let saat = takvim.component(.hour, from: simdi)
        if saat < geceSonu { return simdi.addingTimeInterval(gece) }
        if !isGunu(simdi) && !kriptoMu(sembol) { return simdi.addingTimeInterval(haftaSonu) }
        return simdi.addingTimeInterval(SandikWidgetFiyatServisi.tazelemeAraligi)
    }

    /// Bugün iş günüyse ve saat 07:00'den önceyse bugün 07:00; değilse
    /// sonraki iş gününün 07:00'si (TR).
    static func sonrakiIsGunuSabahi(_ simdi: Date) -> Date {
        let c = takvim
        var gun = c.startOfDay(for: simdi)
        for _ in 0..<8 {
            if let sabah = c.date(bySettingHour: geceSonu, minute: 0, second: 0, of: gun),
               sabah > simdi, isGunu(sabah) {
                return sabah
            }
            gun = c.date(byAdding: .day, value: 1, to: gun) ?? gun.addingTimeInterval(86_400)
        }
        return simdi.addingTimeInterval(fonDeneme)
    }
}

/// `sandik_varliklar` paketinin tamamı — Dart `varlikWidgetPaketi`.
struct SandikVarlikPaketi: Decodable {
    let v: Int
    let saat: String?
    let ogeler: [SandikVarlikOgesi]
    /// Yazım anı (epoch ms) ve biçimli hâli ("24 Eki 14:05"). İsteğe bağlı.
    var zaman: Double? = nil
    var tarih: String? = nil

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
    /// Paketin yazım anı; eski paket yazmadıysa `nil` (tazelik bilinmiyor).
    var zaman: Date? = nil
    /// Yazım anının tarihli hâli ("24 Eki 14:05"), Dart biçimler.
    var tarih: String = ""

    /// Fiyat bu kadar eskiyse saatin yerine tarih yazılır (Ar-Ge 2026-10-25).
    static let bayatlikEsigi: TimeInterval = 24 * 60 * 60

    /// Bu girdinin anında fiyat 1 günden eski mi?
    var bayat: Bool {
        guard let zaman = zaman else { return false }
        return date.timeIntervalSince(zaman) >= Self.bayatlikEsigi
    }

    /// Aynı veri, başka bir an için — zaman çizelgesinin ileri girdileri.
    func ayniVeri(at tarihi: Date) -> SandikVarlikEntry {
        SandikVarlikEntry(
            date: tarihi, durum: durum, saat: saat, isLight: isLight,
            zaman: zaman, tarih: tarih)
    }

    /// Önizleme / yer tutucu. Fiyat UYDURULMAZ: "—".
    static let ornek = SandikVarlikEntry(
        date: Date(),
        durum: .oge(SandikVarlikOgesi(
            id: "ALTIN_GRAM24", ad: "Gram altın", alt: nil,
            fiyat: "—", degisim: nil, yon: nil, kisa: "Gr altın")),
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

        var durum: SandikVarlikEntry.Durum
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
        var zaman = paket.zaman.map { Date(timeIntervalSince1970: $0 / 1000) }
        var saatMetni = saat
        var tarih = paket.tarih ?? ""

        // Widget'ın sunucudan çektiği fiyat, uygulamanın yazdığından
        // YENİYSE o gösterilir; zaman etiketi de onun anıdır.
        if case .oge(let oge) = durum, oge.sunucu == true,
           let c = SandikWidgetFiyatServisi.depo()[oge.id] {
            let dahaYeni: Bool
            if let yazim = zaman {
                dahaYeni = c.tarih > yazim
            } else {
                dahaYeni = true
            }
            if dahaYeni {
                durum = .oge(oge.canliIle(c))
                zaman = c.tarih
                saatMetni = SandikWidgetBicim.saat(c.tarih)
                tarih = SandikWidgetBicim.tarih(c.tarih)
            }
        }
        return SandikVarlikEntry(
            date: Date(), durum: durum, saat: saatMetni, isLight: isLight,
            zaman: zaman, tarih: tarih)
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
        // Kapsam dışı varlıkta portföy widget'ıyla aynı karar: veriyi
        // uygulama yazar ve yazınca bu türü yeniler (`.never`). Zamanlı
        // yenileme boşuna bütçe harcardı.
        //
        // Sunucu kapsamındaki varlıkta (2026-10-26) gündüz yarım saatte bir
        // yenilenir; bilinen fiyat 10 dk'dan eskiyse `widget-fiyat`'tan
        // çekilir. Başarısızsa son bilinen değer saatiyle kalır. Gece, hafta
        // sonu ve fon için seyrek ritim (aynı gün, 21:15 raporu #2/#3):
        // `SandikWidgetRitmi`. Sunucu yanıtı 60 sn önbellekli.
        //
        // İki ileri girdi (veri aynı, yalnız an): seansın bitişi (açıkken
        // yazılmış fiyat o andan sonra saatle görünür) ve 1 günlük eşik
        // (saat → tarih). Uygulama açılmasa da etiket doğru kalır.
        var simdi = oku(configuration)
        var yenileme: Date? = nil
        if case .oge(let oge) = simdi.durum, oge.sunucu == true {
            // Ritim (gece, hafta sonu, fon günde bir): `SandikWidgetRitmi`.
            var canliZaman = SandikWidgetFiyatServisi.depo()[oge.id]?.tarih
            var bayat = true
            if let bilinen = simdi.zaman {
                bayat = simdi.date.timeIntervalSince(bilinen) >= SandikWidgetFiyatServisi.tazeEsigi
            }
            if bayat, SandikWidgetRitmi.cekilmeli(oge.id, simdi: simdi.date, canliZaman: canliZaman) {
                if let cekilen = await SandikWidgetFiyatServisi.cek(oge.id) {
                    canliZaman = cekilen.tarih
                    simdi = oku(configuration)
                }
            }
            yenileme = SandikWidgetRitmi.sonraki(oge.id, simdi: simdi.date, canliZaman: canliZaman)
        }
        var anlar: [Date] = []
        if case .oge(let oge) = simdi.durum, let ms = oge.seansSonu {
            anlar.append(Date(timeIntervalSince1970: ms / 1000))
        }
        if let zaman = simdi.zaman {
            anlar.append(zaman.addingTimeInterval(SandikVarlikEntry.bayatlikEsigi))
        }
        let ileri = anlar.filter { $0 > simdi.date }.sorted()
            .map { simdi.ayniVeri(at: $0) }
        if let yenileme = yenileme {
            return Timeline(entries: [simdi] + ileri, policy: .after(yenileme))
        }
        return Timeline(entries: [simdi] + ileri, policy: .never)
    }
}

// MARK: - Görünüm

struct SandikVarlikView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SandikVarlikEntry

    private var palette: SandikPalette { .resolved(isLight: entry.isLight) }

    /// Kilit ekranı aileleri: sistem tek renk (vibrant) çizer. Orada renk
    /// anlam taşımaz; yön ▲/▼ ve işaretli yüzdeyle verilir, metin
    /// `.primary` / `.secondary` (portföy kilit widget'ıyla aynı kural).
    private var kilitEkrani: Bool {
        family == .accessoryRectangular || family == .accessoryInline
    }

    var body: some View {
        icerik
            // iOS 17'de zorunlu (bkz. `SandikHomeWidget`). Kilit ekranında
            // zemin sistemindir; tema rengi orada lekeye dönerdi.
            .containerBackground(for: .widget) {
                if kilitEkrani {
                    Color.clear
                } else {
                    palette.background
                }
            }
    }

    @ViewBuilder
    private var icerik: some View {
        switch family {
        case .accessoryInline:
            satirGorunumu
        case .accessoryRectangular:
            dikdortgenGorunumu
        default:
            kucukGorunum
        }
    }

    // MARK: Ana ekran (systemSmall)

    @ViewBuilder
    private var kucukGorunum: some View {
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
            if let zaman = zamanEtiketi(oge, saatHer: true) {
                Text(zaman)
                    .font(.sandikNumber(10, weight: .medium))
                    .foregroundColor(palette.text20)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    // MARK: Kilit ekranı — dikdörtgen

    private var dikdortgenGorunumu: some View {
        Group {
            switch entry.durum {
            case .oge(let oge):
                dikdortgenOge(oge)
            case .listedeYok(let ad):
                dikdortgenBilgi(baslik: ad, metin: "Listende yok. Basılı tutup değiştir.")
            case .listeBos:
                dikdortgenBilgi(baslik: "sandık", metin: "Uygulamayı aç")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            AccessoryWidgetBackground()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
    }

    /// Üç satır: ad · fiyat · değişim + zaman. Kişisel tutar yok — yalnız
    /// piyasa fiyatı (kilitliyken örtülecek bir şey yok).
    private func dikdortgenOge(_ oge: SandikVarlikOgesi) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                SandikLogoMark(width: 12)
                Text(oge.ad)
                    .font(.sandikLabel(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(oge.fiyat ?? "—")
                .font(.sandikNumber(22, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .widgetAccentable()
            HStack(spacing: 4) {
                if let degisim = oge.degisim, !degisim.isEmpty {
                    if let ok = okIsareti(oge.yon) {
                        Text(ok)
                            .font(.sandikLabel(10, weight: .black))
                    }
                    Text(degisim)
                        .font(.sandikNumber(12, weight: .semibold))
                        .lineLimit(1)
                } else {
                    // Ölçüm yok: yüzde uydurulmaz.
                    Text("Değişim yok")
                        .font(.sandikLabel(11, weight: .medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let zaman = zamanEtiketi(oge, saatHer: true) {
                    Text(zaman)
                        .font(.sandikNumber(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisimMetni(oge))
    }

    private func dikdortgenBilgi(baslik: String, metin: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                SandikLogoMark(width: 12)
                Text(baslik)
                    .font(.sandikLabel(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(metin)
                .font(.sandikLabel(12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Kilit ekranı — tek satır (saatin üstü)

    /// Sistem bu ailede tek satır metin çizer ve sığmayanı keser; bu yüzden
    /// tek `Text`: "Gr altın ₺4.215 ▲%0,4". Ok varken işaret tekrar
    /// yazılmaz (dar satır); ok yoksa (değişim sıfır) yüzde zaten işaretsiz.
    @ViewBuilder
    private var satirGorunumu: some View {
        switch entry.durum {
        case .oge(let oge):
            Text(satirMetni(oge))
                .accessibilityLabel(erisimMetni(oge))
        case .listedeYok(let ad):
            Text("\(ad) listende yok")
        case .listeBos:
            Text("sandık · Uygulamayı aç")
        }
    }

    private func satirMetni(_ oge: SandikVarlikOgesi) -> String {
        var parcalar: [String] = [oge.gorunenKisaAd, oge.fiyat ?? "—"]
        if let degisim = oge.degisim, !degisim.isEmpty {
            if let ok = okIsareti(oge.yon) {
                parcalar.append(ok + isaretsiz(degisim))
            } else {
                parcalar.append(degisim)
            }
        }
        var metin = parcalar.joined(separator: " ")
        // Dar satırda zaman yalnız gerektiğinde: kapanış, bayat fiyat ya da
        // seans içinde yazılıp seansı bitmiş fiyat.
        if let zaman = zamanEtiketi(oge, saatHer: false) {
            metin += " · " + zaman
        }
        return metin
    }

    /// Yalnız gösterim: baştaki işaret düşer, sayı yeniden biçimlenmez.
    private func isaretsiz(_ yuzde: String) -> String {
        var s = yuzde
        while let ilk = s.first, ilk == "+" || ilk == "-" || ilk == "\u{2212}" {
            s.removeFirst()
        }
        return s
    }

    // MARK: Ortak

    /// Fiyatın yanındaki zaman bilgisi; yoksa `nil`.
    ///
    /// - "Kapanış": Dart yazım anında seansı kapalı buldu (yalnız BIST
    ///   takvimindeki türler; kripto/altın/döviz asla). Fiyat 1 günden
    ///   eskiyse tarih de eklenir.
    /// - Fiyat 1 günden eski: saat yerine tarih ("24 Eki 14:05").
    /// - Seans içinde yazılmış, seans bitmiş: saat (kapanıştan önceki an).
    /// - Aksi hâlde saat yalnız `saatHer` ise (ana ekran, dikdörtgen).
    private func zamanEtiketi(_ oge: SandikVarlikOgesi, saatHer: Bool) -> String? {
        let tarihli = entry.bayat && !entry.tarih.isEmpty
        if oge.kapanis == true {
            return tarihli ? "Kapanış · \(entry.tarih)" : "Kapanış"
        }
        if tarihli { return entry.tarih }
        if entry.saat.isEmpty { return nil }
        if saatHer { return entry.saat }
        if let ms = oge.seansSonu,
           entry.date >= Date(timeIntervalSince1970: ms / 1000) {
            return entry.saat
        }
        return nil
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

    /// Üç boyutta da aynı cümle kalıbı: ad, fiyat, günlük değişim, an.
    private func erisimMetni(_ oge: SandikVarlikOgesi) -> String {
        var parcalar: [String] = [oge.ad, oge.fiyat ?? "fiyat yok"]
        if oge.kapanis == true {
            parcalar.append("kapanış fiyatı")
        }
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
        if entry.bayat && !entry.tarih.isEmpty {
            parcalar.append("\(entry.tarih) itibarıyla")
        } else if !entry.saat.isEmpty {
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
            // Zemin (`containerBackground`) görünümün içinde: aileye göre
            // seçiliyor (kilit ekranında sistem zemini).
            SandikVarlikView(entry: entry)
                .widgetURL(varlikWidgetClickURL)
        }
        .configurationDisplayName("Tek varlık")
        .description("Seçtiğin varlığın fiyatı ve günlük değişimi: gram altın, dolar, bir fon…")
        // Kilit ekranı (2026-10-25): dikdörtgen + saatin üstündeki tek satır.
        // Aynı tür, aynı seçim — galeride iki boyut daha.
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}
