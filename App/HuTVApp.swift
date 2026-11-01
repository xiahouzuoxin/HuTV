import SwiftUI

@main
struct HuTVApp: App {
    @State private var sessionID = UUID()
    @State private var store = WarehouseStore()

    @State private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(history)
                .id(sessionID)
                .onReceive(NotificationCenter.default.publisher(for: AppMaintenance.didReset)) { _ in
                    store.retire(); history.retire()
                    store = WarehouseStore()
                    history = HistoryStore()
                    sessionID = UUID()
                }
        }
    }
}
