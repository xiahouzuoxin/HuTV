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
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            sourceSidebar
                                .frame(width: min(220, max(108, geometry.size.width * 0.23)))
                            Divider()
                            if let group = activeGroup {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text(group.source.title).font(.headline).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if !group.isLoading && group.error == nil {
                                            Text("\(group.items.count) 个结果").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(12)
                                    results(group).frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
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

    private var activeGroup: SourceSearchResults? {
        model.groups.first(where: { $0.id == selectedSource }) ?? model.rankedGroups.first
    }

    private var sourceSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("资源").font(.headline)
                Spacer(minLength: 0)
            }.padding(12)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.rankedGroups) { group in
                        Button { selectedSource = group.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.source.title).font(.subheadline).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 4) {
                                    if group.isLoading {
                                        ProgressView().controlSize(.mini)
                                        Text("搜索中")
                                    } else if group.error != nil {
                                        Image(systemName: "exclamationmark.circle")
                                        Text("失败")
                                    } else {
                                        Text("\(group.items.count) 个结果").monospacedDigit()
                                    }
                                }.font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                            .background(activeGroup?.id == group.id ? Color.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(activeGroup?.id == group.id ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(activeGroup?.id == group.id ? .isSelected : [])
                    }
                }.padding(.horizontal, 6).padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    @ViewBuilder private func results(_ group: SourceSearchResults) -> some View {
        if group.isLoading {
            ProgressView("正在搜索…")
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
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 200), spacing: 12)],
                          alignment: .leading, spacing: 12) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            MediaDetailView(provider: group.source.provider, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Rectangle().fill(Color(.tertiarySystemFill))
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    .overlay {
                                        AsyncImage(url: item.posterURL) { phase in
                                            if let image = phase.image { image.resizable().scaledToFill() }
                                            else { Image(systemName: "film").font(.largeTitle).foregroundStyle(.secondary) }
                                        }
                                    }.clipped()
                                Text(item.title).font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary).lineLimit(2, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .id(group.id)
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
        selectedSource = nil
        searchTask = Task { await model.search(value, sources: snapshot) }
    }
}
