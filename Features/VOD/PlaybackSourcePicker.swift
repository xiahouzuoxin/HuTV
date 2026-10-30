import SwiftUI

struct PlaybackSourceSelection {
    let item: MediaItem
    let source: TVBoxSite
    let episodes: [MediaEpisode]
    let episode: MediaEpisode
    let keepPosition: Bool
}

struct PlaybackSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let source: TVBoxSite
    let episodes: [MediaEpisode]
    let current: MediaEpisode
    let onSelect: (PlaybackSourceSelection) -> Void
    @State private var keepPosition = true
    @State private var refreshedEpisodes: [MediaEpisode]?
    @State private var refreshError: String?
    @State private var loading = true
    @State private var refreshID = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("保留当前播放进度", isOn: $keepPosition)
                } footer: {
                    Text("不同源的片头、时长可能不同，切换后可手动调整进度。不会自动匹配或切换影片。")
                }
                Section("当前影片的播放线路") {
                    if loading {
                        ProgressView("更新当前影片线路…")
                    } else {
                        if let refreshError {
                            Text("更新失败：\(refreshError)").font(.footnote).foregroundStyle(.secondary)
                            Button("重试更新线路") { refreshID += 1 }
                        }
                        EpisodeSourceChoices(item: item, source: source, episodes: refreshedEpisodes ?? episodes,
                                             current: current, keepPosition: $keepPosition, onSelect: onSelect)
                    }
                }
                Section("其他订阅源") {
                    NavigationLink("搜索其他源中的同名影片") {
                        AlternateSourceSearch(title: item.title, current: current,
                                              keepPosition: $keepPosition, onSelect: onSelect)
                    }
                }
            }
            .navigationTitle("切换源")
            .task(id: refreshID) {
                loading = true; refreshError = nil
                defer { loading = false }
                do {
                    let result = try await StandardCMSProvider(id: item.sourceID, source: source).detail(id: item.detailID)
                    guard !Task.isCancelled else { return }
                    refreshedEpisodes = result.episodes
                } catch {
                    if !Task.isCancelled { refreshError = error.localizedDescription }
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct EpisodeSourceChoices: View {
    let item: MediaItem
    let source: TVBoxSite
    let episodes: [MediaEpisode]
    let current: MediaEpisode
    @Binding var keepPosition: Bool
    let onSelect: (PlaybackSourceSelection) -> Void
    private var lines: [String] { episodes.reduce(into: []) { if !$0.contains($1.line) { $0.append($1.line) } } }

    var body: some View {
        ForEach(lines, id: \.self) { line in
            NavigationLink {
                List {
                    Section {
                        Text(item.title).font(.headline)
                        Text(source.name).foregroundStyle(.secondary)
                        Toggle("保留当前播放进度", isOn: $keepPosition)
                    }
                    Section("请选择集数 · 当前观看 \(current.name)") {
                        ForEach(episodes.filter { $0.line == line }) { episode in
                            Button {
                                onSelect(PlaybackSourceSelection(item: item, source: source, episodes: episodes,
                                                               episode: episode, keepPosition: keepPosition))
                            } label: {
                                HStack {
                                    Text(episode.name)
                                    Spacer()
                                    if episode.name == current.name {
                                        Text("同名集数").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !episode.isDirectMedia {
                                        Text("需额外解析").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(!episode.isDirectMedia)
                        }
                    }
                }
                .navigationTitle(line)
            } label: {
                HStack {
                    Text(line)
                    Spacer()
                    Text("\(episodes.filter { $0.line == line }.count) 集").foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AlternateSourceSearch: View {
    @Environment(WarehouseStore.self) private var store
    let current: MediaEpisode
    @Binding var keepPosition: Bool
    let onSelect: (PlaybackSourceSelection) -> Void
    @State private var query: String
    @State private var submitted: String
    @State private var model = SearchModel()

    init(title: String, current: MediaEpisode, keepPosition: Binding<Bool>, onSelect: @escaping (PlaybackSourceSelection) -> Void) {
        self.current = current; _keepPosition = keepPosition; self.onSelect = onSelect
        _query = State(initialValue: title); _submitted = State(initialValue: title)
    }

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
        List {
            Section {
                Text("请核对影片名称、版本与集数，再选择播放。搜索不会中断当前视频。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if sources.isEmpty { Text("没有可搜索的点播订阅，请先添加点播 API。") }
            ForEach(model.groups) { group in
                Section(group.source.title) {
                    if group.isLoading { ProgressView("搜索中…") }
                    if let error = group.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    if !group.isLoading && group.error == nil && group.items.isEmpty { Text("没有匹配影片").foregroundStyle(.secondary) }
                    ForEach(group.items) { result in
                        NavigationLink(result.title) {
                            AlternateSourceDetail(provider: group.source.provider, item: result, current: current,
                                                  keepPosition: $keepPosition, onSelect: onSelect)
                        }
                    }
                }
            }
        }
        .navigationTitle("其他源")
        .searchable(text: $query, prompt: "修改影片名称后搜索")
        .onSubmit(of: .search) {
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { submitted = value }
        }
        .task(id: submitted) { await model.search(submitted, sources: sources) }
    }
}

private struct AlternateSourceDetail: View {
    let provider: any ContentProvider
    let item: MediaItem
    let current: MediaEpisode
    @Binding var keepPosition: Bool
    let onSelect: (PlaybackSourceSelection) -> Void
    @State private var detail: MediaDetail?
    @State private var error: String?
    @State private var retry = 0

    var body: some View {
        List {
            if let detail {
                Section {
                    Text(detail.title).font(.headline)
                    Text(detail.metadata).font(.caption).foregroundStyle(.secondary)
                    Text(provider.source.name).font(.caption).foregroundStyle(.secondary)
                }
                Section("确认影片后选择线路与集数") {
                    EpisodeSourceChoices(item: item, source: provider.source, episodes: detail.episodes,
                                         current: current, keepPosition: $keepPosition, onSelect: onSelect)
                    if detail.episodes.isEmpty { Text("没有可用集数") }
                }
            } else if let error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { retry += 1 }
            } else { ProgressView("获取线路与集数…") }
        }
        .navigationTitle(item.title)
        .task(id: retry) {
            error = nil
            do {
                let result = try await provider.detail(id: item.detailID)
                guard !Task.isCancelled else { return }
                detail = result
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
