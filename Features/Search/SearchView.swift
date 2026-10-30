import SwiftUI

struct SearchView: View {
    @Environment(WarehouseStore.self) private var store
    @Environment(HistoryStore.self) private var history
    @State private var keyword = ""
    @State private var model = SearchModel()
    @State private var selectedSource: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var confirmingClear = false

    private var sources: [SearchSource] {
        store.warehouses.flatMap { warehouse in
            warehouse.config.sites.compactMap { site in
                ContentProviderFactory.make(for: site, namespace: warehouse.id.uuidString).map {
                    SearchSource(provider: $0, title: warehouse.config.sites.count == 1 ? warehouse.name : "\(warehouse.name) · \(site.name)")
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.hasSearched {
                if model.groups.isEmpty {
                    ContentUnavailableView("没有点播源", systemImage: "shippingbox",
                                           description: Text("请先在订阅页添加点播 API"))
                } else {
                    sourceTabs
                    if let group = model.groups.first(where: { $0.id == selectedSource }) ?? model.groups.first {
                        results(group)
                    }
                }
            } else {
                searchHistory
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "搜索影片")
        .onSubmit(of: .search) { submit(keyword) }
        .onChange(of: keyword) { _, value in
            if value.isEmpty { searchTask?.cancel(); model.reset(); selectedSource = nil }
        }
        .onChange(of: sources.map(\.id)) { searchTask?.cancel(); model.reset(); selectedSource = nil }
        .confirmationDialog("清空搜索历史？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) { history.clearSearches() }
        }
    }

    private var sourceTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.groups) { group in
                    Button { selectedSource = group.id } label: {
                        HStack(spacing: 6) {
                            Text(group.source.title).lineLimit(1)
                            if group.isLoading { ProgressView().controlSize(.mini) }
                            else if group.error != nil { Image(systemName: "exclamationmark.circle") }
                            else { Text("\(group.items.count)").monospacedDigit() }
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(selectedSource == group.id ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                        .foregroundStyle(selectedSource == group.id ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSource == group.id ? .isSelected : [])
                }
            }.padding(.horizontal).padding(.vertical, 10)
        }
    }

    @ViewBuilder private func results(_ group: SourceSearchResults) -> some View {
        if group.isLoading {
            Spacer(); ProgressView("正在搜索 \(group.source.title)…"); Spacer()
        } else if let error = group.error {
            ContentUnavailableView {
                Label("该源搜索失败", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("重新搜索") { submit(model.searchedKeyword) }
            }
        } else if group.items.isEmpty {
            ContentUnavailableView("该源没有找到结果", systemImage: "magnifyingglass",
                                   description: Text("试试其他订阅源或更换关键词"))
        } else {
            List(group.items) { item in
                NavigationLink {
                    MediaDetailView(provider: group.source.provider, item: item)
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: item.posterURL) { $0.resizable().scaledToFill() }
                            placeholder: { Rectangle().fill(.quaternary) }
                            .frame(width: 54, height: 76).clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(item.title)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var searchHistory: some View {
        List {
            if history.searches.isEmpty {
                ContentUnavailableView("搜索影片", systemImage: "magnifyingglass",
                    description: Text(sources.isEmpty ? "先添加点播订阅，再搜索喜欢的影片" : "搜索结果将按订阅源分开展示"))
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(history.searches, id: \.self) { value in
                        Button { keyword = value; submit(value) } label: {
                            Label(value, systemImage: "clock").foregroundStyle(.primary)
                        }
                        .swipeActions { Button("删除", role: .destructive) { history.removeSearch(value) } }
                    }
                } header: {
                    HStack {
                        Text("搜索历史")
                        Spacer()
                        Button("清空") { confirmingClear = true }
                    }
                }
            }
        }.listStyle(.plain)
    }

    private func submit(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        searchTask?.cancel()
        history.addSearch(value)
        let snapshot = sources
        selectedSource = snapshot.first?.id
        searchTask = Task { await model.search(value, sources: snapshot) }
    }
}
