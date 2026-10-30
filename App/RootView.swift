import SwiftUI

struct RootView: View {
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
    }
}
