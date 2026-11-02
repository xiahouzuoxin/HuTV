import SwiftUI

@main
struct HuTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sessionID = UUID()
    @State private var store = WarehouseStore()

    @State private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(history)
                .id(sessionID)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { history.flushPending() }
                }
                .onReceive(NotificationCenter.default.publisher(for: AppMaintenance.didReset)) { _ in
                    store.retire(); history.retire()
                    store = WarehouseStore()
                    history = HistoryStore()
                    sessionID = UUID()
                }
        }
    }
}
