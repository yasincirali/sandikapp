import SwiftUI
import WidgetKit

/// Uzantının giriş noktası.
///
/// `@main` bu hedefte YALNIZCA burada bulunur. Bir widget bundle'ı altına
/// ileride ana ekran widget'ı da eklenebilir (`HomeWidgetService` iOS
/// tarafı için `kind = "SandikWidget"` bekliyor) — o zaman buraya ikinci
/// bir satır eklenir, yeni bir `@main` açılmaz.
@main
struct SandikWidgetBundle: WidgetBundle {
    var body: some Widget {
        // Live Activity iOS 16.1+ ister. Hedef minimumu 17.0 olduğu için
        // koşul pratikte hep doğrudur; `if #available` yine de bırakılır ki
        // hedef ileride düşürülürse derleme kırılsın, sessizce boş kalmasın.
        if #available(iOS 16.1, *) {
            SandikLiveActivity()
        }
    }
}
