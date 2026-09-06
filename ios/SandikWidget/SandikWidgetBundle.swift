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

        // Kullanılan ActivityKit API'leri (`ActivityContent`, `staleDate`)
        // iOS 16.2+ ister; hedef minimumu 17.0. Koşul pratikte hep doğrudur
        // ama bırakılır ki hedef ileride düşürülürse derleme kırılsın,
        // uzantı sessizce boş kalmasın.
        if #available(iOS 17.0, *) {
            SandikLiveActivity()
        }
    }
}
