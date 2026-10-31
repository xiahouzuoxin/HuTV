import SwiftUI

struct WarehouseListView: View {
    @Environment(WarehouseStore.self) private var store
    @State private var showingImporter = false
    @State private var editingSubscription: Warehouse?
    @State private var editMode: EditMode = .inactive
    @State private var refreshError: String?

    var body: some View {
        List {
            if !store.feeds.isEmpty {
                Section {
                    NavigationLink("在线 JSON 列表（\(store.feeds.count)）") { SubscriptionFeedsView() }
                }
            }
            if store.isRefreshingAll { ProgressView("正在更新订阅…") }
            if store.warehouses.isEmpty {
                ContentUnavailableView(
                    "还没有订阅",
                    systemImage: "shippingbox",
                    description: Text("点击右上角加号，添加点播 API、直播列表或 TVBox 配置")
                )
            } else {
                subscriptionSection(.cms, title: "点播源")
                subscriptionSection(.live, title: "直播源")
                subscriptionSection(.tvbox, title: "聚合配置")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                Text("点击订阅修改名称和链接；拖动右侧手柄排序。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(10).background(.regularMaterial)
            }
        }
        .navigationTitle("视频订阅")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "完成" : "编辑") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .disabled(store.warehouses.isEmpty && !editMode.isEditing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("导入", systemImage: "plus") { showingImporter = true }
                    .disabled(editMode.isEditing)
            }
        }
        .sheet(item: $editingSubscription) { EditSubscriptionView(warehouse: $0) }
        .sheet(isPresented: $showingImporter) { ImportSubscriptionView() }
        .refreshable { await refreshAll() }
        .alert("刷新失败", isPresented: Binding(
            get: { refreshError != nil }, set: { if !$0 { refreshError = nil } }
        )) { Button("好") {} } message: { Text(refreshError ?? "") }
        .alert("保存失败", isPresented: Binding(
            get: { store.lastPersistenceError != nil },
            set: { if !$0 { store.clearPersistenceError() } }
        )) { Button("好") { store.clearPersistenceError() } } message: {
            Text(store.lastPersistenceError ?? "")
        }
        .navigationDestination(for: UUID.self) { id in
            if let warehouse = store.warehouses.first(where: { $0.id == id }) {
                switch warehouse.kind {
                case .cms:
                    if let site = warehouse.config.sites.first {
                        SourceBrowserView(site: site, namespace: warehouse.id.uuidString)
                    }
                case .live:
                    if let live = warehouse.config.lives.first {
                        LivePlaylistView(source: live)
                    }
                case .tvbox:
                    SourceListView(warehouse: warehouse)
                }
            }
        }
    }

    @ViewBuilder
    private func subscriptionSection(_ kind: SubscriptionKind, title: String) -> some View {
        let subscriptions = store.warehouses.filter { $0.kind == kind }
        if !subscriptions.isEmpty {
            Section("\(title)（\(subscriptions.count)）") {
                ForEach(subscriptions) { warehouse in
                    Group {
                        if editMode.isEditing {
                            Button { editingSubscription = warehouse } label: {
                                subscriptionLabel(warehouse)
                            }.buttonStyle(.plain)
                        } else {
                            NavigationLink(value: warehouse.id) {
                                subscriptionLabel(warehouse)
                            }
                        }
                    }
                    .contextMenu {
                        Button("查看与编辑链接", systemImage: "pencil") { editingSubscription = warehouse }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("编辑", systemImage: "pencil") { editingSubscription = warehouse }.tint(.blue)
                        Button("删除", systemImage: "trash", role: .destructive) {
                            store.delete(id: warehouse.id)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button("刷新", systemImage: "arrow.clockwise") {
                            Task { await refresh(warehouse.id) }
                        }.tint(.blue)
                    }
                }
                .onDelete { store.delete(at: $0, kind: kind) }
                .onMove { store.move(from: $0, to: $1, kind: kind) }
            }
        }
    }

    private func subscriptionLabel(_ warehouse: Warehouse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(warehouse.name).font(.headline)
            Text("\(warehouse.kind.label) · \(warehouse.config.sites.count) 个点播源 · \(warehouse.config.lives.count) 组直播")
                .font(.caption).foregroundStyle(.secondary)
            if editMode.isEditing {
                Text(warehouse.configURL.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text("更新于 \(warehouse.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @MainActor private func refreshAll() async {
        refreshError = nil
        let failures = await store.refreshAll()
        if !failures.isEmpty { refreshError = failures.joined(separator: "\n") }
    }

    @MainActor private func refresh(_ id: UUID) async {
        do { try await store.refresh(id: id) }
        catch { refreshError = error.localizedDescription }
    }
}

private struct SourceListView: View {
    let warehouse: Warehouse

    var body: some View {
        List {
            if !warehouse.config.lives.isEmpty {
                Section("直播") {
                    ForEach(warehouse.config.lives, id: \.self) { live in
                        NavigationLink {
                            LivePlaylistView(source: live)
                        } label: {
                            Label(live.name, systemImage: "dot.radiowaves.left.and.right")
                        }
                    }
                }
            }

            if warehouse.config.sites.contains(where: { $0.runtime == .gatewayRequired }) {
                Section {
                    Text("此订阅包含爬虫数据源，需要独立的 TVBox 网关。当前版本可保存和刷新配置，但尚未接入网关，以下爬虫源暂时无法浏览或播放。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("影视数据源") {
                ForEach(warehouse.config.sites) { site in
                    NavigationLink {
                        SourceBrowserView(site: site, namespace: warehouse.id.uuidString)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(site.name)
                            HStack {
                                Text(site.api).lineLimit(1)
                                Spacer()
                                Text(site.runtime.label)
                            }
                            .font(.caption)
                            .foregroundStyle(site.runtime == .nativeAPI ? .green : .secondary)
                        }
                    }
                    .disabled(site.runtime != .nativeAPI)
                }
            }
        }
        .navigationTitle(warehouse.name)
    }
}
