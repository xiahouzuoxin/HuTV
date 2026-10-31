import SwiftUI

struct RootView: View {
    @Environment(WarehouseStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("subscriptions.autoRefresh") private var autoRefresh = false
    @AppStorage("subscriptions.refreshHours") private var refreshHours = 6
    var body: some View {
        TabView {
            NavigationStack { WarehouseListView() }
                .tabItem { Label("订阅", systemImage: "shippingbox") }

            NavigationStack { SearchView() }
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            NavigationStack { HistoryView() }
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }

            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .task(id: "\(scenePhase)|\(autoRefresh)|\(refreshHours)") {
            guard scenePhase == .active, autoRefresh else { return }
            while !Task.isCancelled {
                await store.autoRefreshIfNeeded(intervalHours: refreshHours)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
}
