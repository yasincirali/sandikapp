import AppIntents
import SwiftUI
import WidgetKit

/// Ana ekran widget'ı — VİTRİN: üç varlık alt alta (gram altın, dolar,
/// euro…), orta boy.
///
/// Ar-Ge 2026-10-29 §2 (yasin onayı): altın, dolar ve euro'yu birlikte
/// izleyen kişi üç küçük widget koymak zorundaydı; vitrin bunu tek orta
/// widget'a indirir. Her satır: ad, fiyat, günlük yüzde (ok + işaretli
/// sayı; yalnız renk değil).
///
/// ## Neden ayrı tür (tek varlık widget'ına `.systemMedium` eklemek değil)
/// - Seçim ayrı: tek varlık widget'ının intent'i TEK parametre taşıyor.
///   Aynı türe orta boy eklenseydi üç parametre küçük boyun ve kilit
///   ekranının düzenleme ekranına da düşerdi (iki satırı hiç çizilmeyen
///   seçim). Var olan widget'ların kayıtlı yapılandırması da intent'in
///   şekline bağlı; ona dokunmamak, kurulu widget'ları bozmamak demek.
/// - Veri, seçim listesi ve yazma noktası AYNI: `sandik_varliklar` paketi
///   (Dart `VarlikWidgetService`), aynı App Group, aynı tema bayrağı, aynı
///   `widget-fiyat` istemcisi ve ritmi (`SandikWidgetFiyatServisi`,
///   `SandikWidgetRitmi`). Yeni anahtar yok; pakete yalnız isteğe bağlı
///   `vitrin` alanı eklendi (varsayılan üçlü).
/// - Dart `HomeWidgetService.iOSVitrinWidgetName` bu türü ayrıca yeniler
///   (`home_widget` iOS'ta yalnız adı verilen türü yeniler).
///
/// ## Neden ayrı dosya
/// Tek varlık dosyasındaki kaynak kilidi (`.supportedFamilies` tek kez)
/// o widget'ın ailelerini denetliyor; vitrin aynı dosyada olsaydı kilit
/// iki widget'ı karıştırırdı. Bu dosya pbxproj'a (dosya referansı + grup +
/// SandikWidgetExtension "Sources" fazı) kaydedildi; kayıt
/// `test/vitrin_widget_sozlesmesi_test.dart` ile kilitli.
///
/// ## Fiyat
/// - Sunucu kapsamındaki satır (`sunucu == true`: altın, TL döviz, kripto,
///   fon — karar Dart'ta, `FiyatKaynagi.widgetSunucuKapsamindaMi`) fiyatını
///   uygulamanın yazdığı ya da widget'ın `widget-fiyat`'tan çektiği değerden
///   (hangisi yeniyse) alır. Altın/dövizde bu sayı kotasyonun ALIŞ'ıdır, yani
///   uygulamadaki "Bozdurursan" fiyatı (`PriceService` `regularMarketPrice`,
///   sunucu `yurt_ici_kotasyon.fiyat`); widget yeniden hesaplamaz.
/// - Kapsamdaki satırların bayat olanları TEK istekte gider (en çok 3
///   sembol; fonksiyon 5'e kadar alır) — Edge Function çağrısı tek varlık
///   widget'ıyla aynı sayıda.
/// - Kapsam dışı satır (BIST hissesi, endeks, emtia…) fiyat göstermez,
///   "Uygulamayı aç" der (Ar-Ge §2: "sunucu fiyatı yoksa satır uygulamayı
///   aç der"). Gerekçe: o satırın fiyatı yalnız uygulama açıldığında
///   yazılır; yanındaki satırlar yarım saatte bir tazelenirken onun eski
///   sayısı aynı vitrinde "şimdi" gibi dururdu. Uydurma sayı yok.
///
/// ## Dokunuş
/// Tek varlık widget'ıyla aynı bağlantı (`varlikWidgetClickURL` → Portföy
/// sekmesi). Satır başına bağlantı yok: URL varlık kimliği taşımıyor
/// (`DeepLinkRouter.varlikWidgetHost`), ve orta boyda satır başına
/// `Link` dokunma alanını 44 pt'nin altına düşürürdü.
///
/// iOS 17 API'leri koşulsuz (uzantı hedefi 17.0; bkz. `SandikVarlikWidget`
/// "Neden `@available` yok").

// MARK: - Seçim (App Intents)

/// Vitrin satırında seçilen varlık. Tek varlık widget'ının
/// `SandikVarlikEntity`'siyle aynı kimlik ve görünüm; ayrı tür olmasının
/// tek nedeni sorgusu (aşağıda, `defaultResult` yok).
struct SandikVitrinVarlikEntity: AppEntity {
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

    // Metin LİTERAL (App Intents meta veri çıkarıcısı derleme anında okur).
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Varlık" }

    static var defaultQuery: SandikVitrinQuery { SandikVitrinQuery() }

    var displayRepresentation: DisplayRepresentation {
        if let alt = alt, !alt.isEmpty {
            return DisplayRepresentation(title: "\(ad)", subtitle: "\(alt)")
        }
        return DisplayRepresentation(title: "\(ad)")
    }
}

/// Seçim listesi: tek varlık widget'ıyla aynı (portföy + takip listesi,
/// uygulamanın yazdığı paket; katalog araması yok).
///
/// `defaultResult` BİLEREK yok: varsayılan sonuç varlık türüne bağlıdır,
/// parametreye değil — üç satırın üçü de aynı varlıkla (listenin başı)
/// dolardı. Boş satırı sağlayıcı paketin `vitrin` alanından doldurur
/// (takip listesinin ilk üçü; karar Dart'ta, `varsayilanVitrin`).
struct SandikVitrinQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SandikVitrinVarlikEntity] {
        let ogeler = SandikVarlikPaketi.oku().ogeler
        return identifiers.compactMap { kimlik in
            ogeler.first(where: { $0.id == kimlik }).map { SandikVitrinVarlikEntity(oge: $0) }
        }
    }

    func suggestedEntities() async throws -> [SandikVitrinVarlikEntity] {
        SandikVarlikPaketi.oku().ogeler.map { SandikVitrinVarlikEntity(oge: $0) }
    }
}

struct SandikVitrinSecimi: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Vitrini düzenle" }

    static var description: IntentDescription {
        "Vitrinde alt alta görünecek üç varlığı seç. Boş bıraktığın satıra takip listenin başındaki varlık gelir."
    }

    @Parameter(title: "1. satır")
    var birinci: SandikVitrinVarlikEntity?

    @Parameter(title: "2. satır")
    var ikinci: SandikVitrinVarlikEntity?

    @Parameter(title: "3. satır")
    var ucuncu: SandikVitrinVarlikEntity?

    init() {}
}

// MARK: - Zaman çizelgesi

/// Vitrinin bir satırı.
struct SandikVitrinSatiri {
    /// Gösterilen öğe; `nil` = kullanıcının seçtiği varlık artık listede
    /// yok (takipten çıkarıldı / satıldı).
    let oge: SandikVarlikOgesi?
    let ad: String
    /// Fiyatın anı: widget'ın sunucudan çektiği daha yeniyse onun anı,
    /// değilse paketin yazım anı; bilinmiyorsa `nil`.
    var zaman: Date? = nil

    /// Fiyat bu satırda gösterilir mi (sunucu kapsamı; karar Dart'ta).
    var fiyatGosterilir: Bool { oge?.sunucu == true }
}

struct SandikVitrinEntry: TimelineEntry {
    let date: Date
    /// En çok üç satır; boşsa uygulama henüz liste yazmadı / oturum kapalı.
    let satirlar: [SandikVitrinSatiri]
    let isLight: Bool

    /// Fiyat bu kadar eskiyse saatin yerine tarih (tek varlık widget'ıyla
    /// aynı eşik).
    static let bayatlikEsigi = SandikVarlikEntry.bayatlikEsigi

    /// Fiyatı gösterilen satırların EN ESKİ anı — başlıktaki zaman. En eski:
    /// "14:05" diyen bir vitrinde hiçbir sayı 14:05'ten eski olmasın.
    var enEskiZaman: Date? {
        satirlar.filter { $0.fiyatGosterilir && $0.oge?.fiyat != nil }
            .compactMap { $0.zaman }
            .min()
    }

    func bayat(_ zaman: Date) -> Bool {
        date.timeIntervalSince(zaman) >= Self.bayatlikEsigi
    }

    /// "14:05"; 1 günden eskiyse "24 Eki 14:05".
    func zamanMetni(_ zaman: Date) -> String {
        bayat(zaman) ? SandikWidgetBicim.tarih(zaman) : SandikWidgetBicim.saat(zaman)
    }

    func ayniVeri(at tarihi: Date) -> SandikVitrinEntry {
        SandikVitrinEntry(date: tarihi, satirlar: satirlar, isLight: isLight)
    }

    /// Önizleme / yer tutucu. Fiyat UYDURULMAZ: "—".
    static let ornek = SandikVitrinEntry(
        date: Date(),
        satirlar: [
            SandikVitrinSatiri(
                oge: SandikVarlikOgesi(
                    id: "ALTIN_GRAM24", ad: "Gram altın", alt: nil,
                    fiyat: "—", degisim: nil, yon: nil, sunucu: true),
                ad: "Gram altın"),
            SandikVitrinSatiri(
                oge: SandikVarlikOgesi(
                    id: "USDTRY=X", ad: "Dolar", alt: nil,
                    fiyat: "—", degisim: nil, yon: nil, sunucu: true),
                ad: "Dolar"),
            SandikVitrinSatiri(
                oge: SandikVarlikOgesi(
                    id: "EURTRY=X", ad: "Euro", alt: nil,
                    fiyat: "—", degisim: nil, yon: nil, sunucu: true),
                ad: "Euro"),
        ],
        isLight: false
    )
}

struct SandikVitrinProvider: AppIntentTimelineProvider {
    static let satirSayisi = 3

    /// Satırlar: kullanıcının seçtiği yerinde kalır; boş satır paketin
    /// `vitrin` sırasından, o da yetmezse listenin başından dolar. Aynı
    /// varlık iki satırda gösterilmez (ikinci seçim boş sayılır).
    private func oku(_ secim: SandikVitrinSecimi) -> SandikVitrinEntry {
        let paket = SandikVarlikPaketi.oku()
        let isLight = UserDefaults(suiteName: VarlikWidgetKeys.suite)?
            .bool(forKey: VarlikWidgetKeys.isLightTheme) ?? false
        if paket.ogeler.isEmpty {
            return SandikVitrinEntry(date: Date(), satirlar: [], isLight: isLight)
        }
        let yazim = paket.zaman.map { Date(timeIntervalSince1970: $0 / 1000) }
        let depo = SandikWidgetFiyatServisi.depo()

        let secilen: [SandikVitrinVarlikEntity?] = [secim.birinci, secim.ikinci, secim.ucuncu]
        let secilenKimlikler = Set(secilen.compactMap { $0?.id })
        var yedek: [String] = []
        for kimlik in (paket.vitrin ?? []) + paket.ogeler.map({ $0.id })
        where !secilenKimlikler.contains(kimlik) && !yedek.contains(kimlik) {
            yedek.append(kimlik)
        }

        var satirlar: [SandikVitrinSatiri] = []
        var gosterilen = Set<String>()
        for s in secilen.prefix(Self.satirSayisi) {
            if let s = s, !gosterilen.contains(s.id) {
                gosterilen.insert(s.id)
                if let oge = paket.ogeler.first(where: { $0.id == s.id }) {
                    satirlar.append(satir(oge, yazim: yazim, depo: depo))
                } else {
                    satirlar.append(SandikVitrinSatiri(oge: nil, ad: s.ad))
                }
                continue
            }
            // Boş satır: sıradaki yedek.
            while !yedek.isEmpty {
                let kimlik = yedek.removeFirst()
                if gosterilen.contains(kimlik) { continue }
                if let oge = paket.ogeler.first(where: { $0.id == kimlik }) {
                    gosterilen.insert(kimlik)
                    satirlar.append(satir(oge, yazim: yazim, depo: depo))
                    break
                }
            }
        }
        return SandikVitrinEntry(date: Date(), satirlar: satirlar, isLight: isLight)
    }

    /// Widget'ın sunucudan çektiği fiyat uygulamanın yazdığından YENİYSE o
    /// gösterilir (tek varlık widget'ıyla aynı kural, `canliIle`).
    private func satir(
        _ oge: SandikVarlikOgesi, yazim: Date?, depo: [String: SandikCanliFiyat]
    ) -> SandikVitrinSatiri {
        if oge.sunucu == true, let c = depo[oge.id] {
            let dahaYeni: Bool
            if let yazim = yazim {
                dahaYeni = c.tarih > yazim
            } else {
                dahaYeni = true
            }
            if dahaYeni {
                return SandikVitrinSatiri(oge: oge.canliIle(c), ad: oge.ad, zaman: c.tarih)
            }
        }
        return SandikVitrinSatiri(oge: oge, ad: oge.ad, zaman: yazim)
    }

    func placeholder(in context: Context) -> SandikVitrinEntry { .ornek }

    func snapshot(for configuration: SandikVitrinSecimi, in context: Context) async -> SandikVitrinEntry {
        let girdi = oku(configuration)
        // Galeride liste boşsa örnek: boş kart widget'ın ne yaptığını anlatmaz.
        if context.isPreview, girdi.satirlar.isEmpty {
            return .ornek
        }
        return girdi
    }

    func timeline(for configuration: SandikVitrinSecimi, in context: Context) async -> Timeline<SandikVitrinEntry> {
        // Tek varlık widget'ıyla aynı karar, satır satır: kapsamdaki satırın
        // fiyatı 10 dk'dan eskiyse ve ritim izin veriyorsa (`SandikWidgetRitmi
        // .cekilmeli`: gece, hafta sonu, fon günde bir) çekilir — hepsi TEK
        // istekte. Yenileme anı satırların en erkeni. Kapsamda satır yoksa
        // widget ağa çıkmaz, `.never` (uygulama yazınca yeniler).
        var simdi = oku(configuration)
        let depo = SandikWidgetFiyatServisi.depo()
        var cekilecek: [String] = []
        for satir in simdi.satirlar {
            guard let oge = satir.oge, oge.sunucu == true else { continue }
            var bayat = true
            if let bilinen = satir.zaman {
                bayat = simdi.date.timeIntervalSince(bilinen) >= SandikWidgetFiyatServisi.tazeEsigi
            }
            if bayat, SandikWidgetRitmi.cekilmeli(oge.id, simdi: simdi.date, canliZaman: depo[oge.id]?.tarih) {
                cekilecek.append(oge.id)
            }
        }
        if !cekilecek.isEmpty {
            let cekilen = await SandikWidgetFiyatServisi.cekToplu(cekilecek)
            if !cekilen.isEmpty {
                simdi = oku(configuration)
            }
        }
        let guncelDepo = SandikWidgetFiyatServisi.depo()
        let yenileme = simdi.satirlar
            .compactMap { $0.oge }
            .filter { $0.sunucu == true }
            .map { SandikWidgetRitmi.sonraki($0.id, simdi: simdi.date, canliZaman: guncelDepo[$0.id]?.tarih) }
            .min()

        // İleri girdi: 1 günlük eşik (saat → tarih); uygulama açılmasa da
        // başlık doğru kalır. Kapsamdaki türler "Kapanış" almaz, seans anı yok.
        var ileri: [SandikVitrinEntry] = []
        if let zaman = simdi.enEskiZaman {
            let esik = zaman.addingTimeInterval(SandikVitrinEntry.bayatlikEsigi)
            if esik > simdi.date {
                ileri.append(simdi.ayniVeri(at: esik))
            }
        }
        if let yenileme = yenileme {
            return Timeline(entries: [simdi] + ileri, policy: .after(yenileme))
        }
        return Timeline(entries: [simdi] + ileri, policy: .never)
    }
}

// MARK: - Görünüm

struct SandikVitrinView: View {
    let entry: SandikVitrinEntry

    private var palette: SandikPalette { .resolved(isLight: entry.isLight) }

    var body: some View {
        icerik
            // iOS 17'de zorunlu (bkz. `SandikHomeWidget`).
            .containerBackground(for: .widget) {
                palette.background
            }
    }

    @ViewBuilder
    private var icerik: some View {
        if entry.satirlar.isEmpty {
            bilgi
        } else {
            liste
        }
    }

    private var liste: some View {
        VStack(alignment: .leading, spacing: 0) {
            baslik
                .padding(.bottom, 4)
            ForEach(Array(entry.satirlar.enumerated()), id: \.offset) { indeks, satir in
                if indeks > 0 {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 0.5)
                        .accessibilityHidden(true)
                }
                satirGorunumu(satir)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Logo + ad + en eski fiyatın anı. VoiceOver'da gizli: zaman her
    /// satırın cümlesinde zaten var, logo süs.
    private var baslik: some View {
        HStack(spacing: 6) {
            SandikLogoMark(width: 14)
            Text("sandık")
                .font(.sandikLabel(12, weight: .bold))
                .foregroundColor(palette.text58)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let zaman = entry.enEskiZaman {
                Text(entry.zamanMetni(zaman))
                    .font(.sandikNumber(10, weight: .medium))
                    .foregroundColor(palette.text20)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityHidden(true)
    }

    /// Ad solda (sığmazsa sondan kısalır), fiyat + değişim sağda (önce
    /// onlar yer alır: `layoutPriority`). Dynamic Type büyüdüğünde satır
    /// kısalır/küçülür, taşmaz (`lineLimit(1)` + `minimumScaleFactor`).
    private func satirGorunumu(_ satir: SandikVitrinSatiri) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(satir.ad)
                .font(.sandikLabel(13, weight: .semibold))
                .foregroundColor(palette.text90)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            sagTaraf(satir)
                .layoutPriority(1)
        }
        // Satır tek cümle okunur: "Gram altın, ₺4.215,30, günlük artış
        // +%0,42, 14:05 itibarıyla".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(erisimMetni(satir))
    }

    @ViewBuilder
    private func sagTaraf(_ satir: SandikVitrinSatiri) -> some View {
        if let oge = satir.oge {
            if satir.fiyatGosterilir {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(oge.fiyat ?? "—")
                        .font(.sandikNumber(15, weight: .semibold))
                        .foregroundColor(palette.text90)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    degisim(oge)
                }
            } else {
                // Kapsam dışı (BIST, endeks…): sayı yok, uydurma yok.
                bilgiEtiketi("Uygulamayı aç")
            }
        } else {
            bilgiEtiketi("Listende yok")
        }
    }

    /// Yön yalnız renkle verilmez: ▲/▼ ve işaretli yüzde birlikte.
    @ViewBuilder
    private func degisim(_ oge: SandikVarlikOgesi) -> some View {
        if let degisim = oge.degisim, !degisim.isEmpty {
            HStack(spacing: 2) {
                if let ok = okIsareti(oge.yon) {
                    Text(ok)
                        .font(.sandikLabel(9, weight: .bold))
                }
                Text(degisim)
                    .font(.sandikNumber(12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(renk(oge.yon))
            .frame(minWidth: 56, alignment: .trailing)
        } else {
            // Ölçüm yok: yüzde uydurulmaz.
            Text("değişim yok")
                .font(.sandikLabel(10, weight: .medium))
                .foregroundColor(palette.text36)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }

    private func bilgiEtiketi(_ metin: String) -> some View {
        Text(metin)
            .font(.sandikLabel(11, weight: .medium))
            .foregroundColor(palette.text58)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var bilgi: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SandikLogoMark(width: 14)
                Text("sandık")
                    .font(.sandikLabel(13, weight: .bold))
                    .foregroundColor(palette.text90)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("Uygulamayı aç; portföyündeki ve takip listendeki varlıklar burada alt alta görünür.")
                .font(.sandikLabel(11, weight: .medium))
                .foregroundColor(palette.text58)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func okIsareti(_ yon: Int?) -> String? {
        guard let yon = yon, yon != 0 else { return nil }
        return yon > 0 ? "▲" : "▼"
    }

    /// Değişim yoksa ya da yön bilinmiyorsa nötr ton (tek varlık widget'ıyla
    /// aynı kural: düz bir değeri kırmızı göstermek "kaybettim" okunur).
    private func renk(_ yon: Int?) -> Color {
        guard let yon = yon, yon != 0 else { return palette.text58 }
        return palette.statusColor(isPositive: yon > 0)
    }

    /// Satır başına tek cümle: ad, fiyat, günlük değişim, an.
    private func erisimMetni(_ satir: SandikVitrinSatiri) -> String {
        guard let oge = satir.oge else {
            return "\(satir.ad), artık listende yok"
        }
        guard satir.fiyatGosterilir else {
            return "\(oge.ad), fiyatı görmek için uygulamayı aç"
        }
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
        if oge.fiyat != nil, let zaman = satir.zaman {
            parcalar.append("\(entry.zamanMetni(zaman)) itibarıyla")
        }
        return parcalar.joined(separator: ", ")
    }
}

// MARK: - Widget tanımı

struct SandikVitrinWidget: Widget {
    /// `HomeWidgetService.iOSVitrinWidgetName` ile aynı olmalı.
    let kind = "SandikVitrinWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SandikVitrinSecimi.self,
            provider: SandikVitrinProvider()
        ) { entry in
            SandikVitrinView(entry: entry)
                .widgetURL(varlikWidgetClickURL)
        }
        .configurationDisplayName("Vitrin")
        .description("Üç varlık alt alta: fiyat ve günlük değişim. Gram altın, dolar, euro…")
        // Yalnız orta boy: üç satır küçükte sığmaz, büyükte boş kalır.
        .supportedFamilies([.systemMedium])
    }
}
