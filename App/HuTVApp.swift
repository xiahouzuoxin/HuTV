import SwiftUI

@main
struct HuTVApp: App {
    @State private var store = WarehouseStore()

    @State private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(history)
        }
    }
}
