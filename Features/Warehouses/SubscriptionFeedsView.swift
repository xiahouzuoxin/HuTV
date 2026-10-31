import SwiftUI

struct SubscriptionFeedsView: View {
    @Environment(WarehouseStore.self) private var store
    @State private var refreshing = Set<UUID>()
    var body: some View {
        List {
            if store.feeds.isEmpty {
                Text("通过在线 JSON 链接导入时开启“跟随链接更新订阅”，即可在这里管理。")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.feeds) { feed in
                Section {
                    Text(feed.url.absoluteString).font(.footnote).textSelection(.enabled)
                    Toggle("跟随更新", isOn: Binding(get: {
                        store.feeds.first(where: { $0.id == feed.id })?.enabled ?? false
                    }, set: { store.setFeedEnabled(feed.id, enabled: $0) }))
                    if let date = feed.updatedAt {
                        Text("检查于 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = feed.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(refreshing.contains(feed.id) ? "刷新中…" : "立即刷新列表") {
                        refreshing.insert(feed.id)
                        Task {
                            defer { refreshing.remove(feed.id) }
                            try? await store.refreshFeed(id: feed.id)
                        }
                    }.disabled(!feed.enabled || refreshing.contains(feed.id))
                    Button("停止跟随并移除链接", role: .destructive) { store.removeFeed(feed.id) }
                } footer: {
                    Text("移除链接不会删除已导入的订阅。远端移除的项暂时保留；手动编辑或删除的订阅不会被该列表恢复。")
                }
            }
        }.navigationTitle("在线 JSON 列表")
    }
}
