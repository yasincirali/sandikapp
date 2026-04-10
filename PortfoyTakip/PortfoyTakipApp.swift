import SwiftUI
import SwiftData

@main
struct PortfoyTakipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Asset.self)
    }
}
