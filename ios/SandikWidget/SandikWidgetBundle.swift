import SwiftUI
import WidgetKit

/// Uzantının giriş noktası.
///
/// `@main` bu hedefte YALNIZCA burada bulunur. Bundle altına yeni bir
/// widget eklendiğinde buraya bir satır eklenir, yeni bir `@main` açılmaz.
@main
struct SandikWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Ana ekran widget'ı — `HomeWidgetService` iOS tarafı için
        // `kind = "SandikWidget"` bekliyor.
        SandikHomeWidget()

        // Kilit ekranı widget'ı (satır + yuvarlak, karar 4.1/4.3) —
        // `HomeWidgetService._iOSKilitWidgetName` = "SandikKilitWidget".
        SandikKilitWidget()

        // Tek varlık widget'ı (Ar-Ge 2026-10-24 §1) — varlık App Intents ile
        // seçilir. iOS 17 API'si; hedef minimumu 17.0 olduğu için koşulsuz
        // (bkz. `SandikVarlikWidget.swift` "Neden `@available` yok").
        // `HomeWidgetService.iOSVarlikWidgetName` = "SandikVarlikWidget".
        SandikVarlikWidget()

        // Vitrin: üç varlık alt alta, orta boy (Ar-Ge 2026-10-29 §2). Tek
        // varlık widget'ıyla aynı paket ve seçim listesi, ayrı tür ve intent
        // (gerekçe `SandikVitrinWidget.swift`).
        // `HomeWidgetService.iOSVitrinWidgetName` = "SandikVitrinWidget".
        SandikVitrinWidget()

        // Kullanılan ActivityKit API'leri (`ActivityContent`, `staleDate`)
        // iOS 16.2+ ister; hedef minimumu 17.0. Koşul pratikte hep doğrudur
        // ama bırakılır ki hedef ileride düşürülürse derleme kırılsın,
        // uzantı sessizce boş kalmasın.
        if #available(iOS 17.0, *) {
            SandikLiveActivity()
        }
    }
}
