import SwiftUI

struct MediaDetailView: View {
    @Environment(HistoryStore.self) private var history
    let provider: any ContentProvider
    let item: MediaItem
    var resumeRecord: WatchRecord? = nil
    @State private var selectedItem: MediaItem?
    @State private var selectedSource: TVBoxSite?
    private var activeItem: MediaItem { selectedItem ?? item }
    private var activeSource: TVBoxSite { selectedSource ?? provider.source }

    @State private var addressEpisode: MediaEpisode?
    @State private var expandedSummary = true
    @State private var detail: MediaDetail?
    @State private var errorMessage: String?
    @State private var playbackError: String?
    @State private var isPreparingPlayback = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var didHandleInitialResume = false
    @State private var playback: OnDemandPlaybackSession?
    @State private var isFullscreen = true

    private var orderedLines: [String] {
        guard let detail else { return [] }
        return MediaEpisode.prioritized(detail.episodes).reduce(into: []) {
            if !$0.contains($1.line) { $0.append($1.line) }
        }
    }

    var body: some View {
        PlaybackDetailLayout(isPlaying: playback != nil, fullscreen: $isFullscreen) {
            if let playback {
                OnDemandPlayerView(playback: playback, isFullscreen: $isFullscreen, onClose: { self.playback = nil }, onSourceSelected: { selection in
                    preparationTask?.cancel()
                    selectedItem = selection.item
                    selectedSource = selection.source
                    if let updated = selection.detail { detail = updated }
                    addressEpisode = nil
                })
            }
        } detail: {
            detailContent
        }
        .background(playback != nil && isFullscreen ? Color.black : Color(.systemBackground))
        .toolbar(playback != nil && isFullscreen ? .hidden : .visible, for: .navigationBar, .tabBar)
        .navigationBarBackButtonHidden(playback != nil && isFullscreen)
        .onDisappear { preparationTask?.cancel() }
        .navigationTitle(activeItem.title).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $addressEpisode) { episode in
            NavigationStack {
                Form {
                    LabeledContent("线路", value: episode.line)
                    LabeledContent("集数", value: episode.name)
                    Text(episode.url).textSelection(.enabled)
                    Button("复制播放地址") { UIPasteboard.general.string = episode.url }
                    Text("地址来自订阅，可能包含临时令牌或过期；请勿公开分享含凭证的地址。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.navigationTitle("播放地址")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { addressEpisode = nil } } }
            }
        }
        .alert("无法播放此线路", isPresented: Binding(
            get: { playbackError != nil }, set: { if !$0 { playbackError = nil } }
        )) { Button("好") {} } message: { Text(playbackError ?? "") }
    }

    private var detailContent: some View {
        Group {
            if let detail {
                List {
                    Section {
                        HStack(alignment: .top, spacing: 14) {
                            AsyncImage(url: detail.posterURL) { $0.resizable().scaledToFill() }
                                placeholder: { Rectangle().fill(.quaternary) }
                                .frame(width: 110, height: 160).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.title).font(.title3.bold())
                                if !detail.metadata.isEmpty { Text(detail.metadata).foregroundStyle(.secondary) }
                            }
                        }
                        if let rating = detail.rating {
                            LabeledContent(rating.source, value: "\(rating.text) / 10")
                        }
                        if !detail.category.isEmpty { LabeledContent("类型", value: detail.category) }
                        if !detail.language.isEmpty { LabeledContent("语言", value: detail.language) }
                        if !detail.releaseDate.isEmpty { LabeledContent("上映日期", value: detail.releaseDate) }
                        if !detail.runningTime.isEmpty { LabeledContent("片长（源提供）", value: detail.runningTime) }
                        if !detail.director.isEmpty { LabeledContent("导演", value: detail.director) }
                        if !detail.actors.isEmpty {
                            LabeledContent("演员") {
                                Text(detail.actors.count > 80 ? String(detail.actors.prefix(80)) + "…" : detail.actors)
                                    .lineLimit(3).truncationMode(.tail)
                            }
                        }
                        if !detail.summary.isEmpty {
                            DisclosureGroup("内容介绍", isExpanded: $expandedSummary) {
                                Text(detail.summary).textSelection(.enabled)
                            }
                        }
                        if let record = history.resumeRecord(sourceID: activeItem.sourceID, detailID: activeItem.detailID),
                           case .vod(_, _, let saved) = record.target,
                           let episode = detail.episodes.first(where: { $0.line == saved.line && $0.name == saved.name }) {
                            Button("继续观看 · \(episode.name) · \(Int(record.position) / 60):\(String(format: "%02d", Int(record.position) % 60))") {
                                play(episode, startPosition: record.resumePosition)
                            }
                            .buttonStyle(.borderedProminent)
                        } else if let episode = MediaEpisode.prioritized(detail.episodes).first(where: { $0.isDirectMedia }) {
                            Button("开始观看") { play(episode) }
                                .buttonStyle(.borderedProminent)
                        }
                    }

                    ForEach(orderedLines, id: \.self) { line in
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                                ForEach(detail.episodes.filter { $0.line == line }) { episode in
                                    Button { play(episode) } label: {
                                        Text(episode.name)
                                            .font(.subheadline).lineLimit(2)
                                            .frame(maxWidth: .infinity, minHeight: 38)
                                            .padding(.horizontal, 5).padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(playback?.item.id == activeItem.id && playback?.queue.current.id == episode.id ? 0.25 : 0.09), in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .contextMenu {
                                        Button("查看播放地址") { addressEpisode = episode }
                                        Button("复制播放地址") { UIPasteboard.general.string = episode.url }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("\(line)，\(episode.name)")
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text(line)
                        } footer: {
                            Text("优先选择 M3U8 / MP4 线路。网页播放页和加密播放标识需要额外解析。")
                        }
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView("详情加载失败", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
            } else {
                ProgressView("加载详情…")
            }
        }
        .disabled(isPreparingPlayback)
        .overlay {
            if isPreparingPlayback {
                ProgressView("正在获取最新播放地址…").padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @MainActor private func load() async {
        guard detail == nil else { return }
        do {
            let loaded = try await provider.detail(id: item.detailID)
            guard !Task.isCancelled, selectedItem == nil else { return }
            detail = loaded
            if !didHandleInitialResume, let record = resumeRecord, case .vod(_, _, let saved) = record.target {
                didHandleInitialResume = true
                // Resolve the latest episode URL rather than reusing an expiring media URL.
                if let episode = loaded.episodes.first(where: { $0.line == saved.line && $0.name == saved.name }) {
                    play(episode, startPosition: record.resumePosition)
                } else { playbackError = "上次观看的集数已变化，请重新选择集数。" }
            }
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func play(_ episode: MediaEpisode, startPosition: Double? = nil) {
        guard !isPreparingPlayback else { return }
        let item = activeItem
        let source = activeSource
        guard let activeProvider = selectedSource == nil ? provider : ContentProviderFactory.make(for: source) else {
            playbackError = "当前订阅源不可用。"
            return
        }
        isPreparingPlayback = true
        preparationTask = Task { @MainActor in
            defer { isPreparingPlayback = false }
            do {
                let fresh = try await activeProvider.detail(id: item.detailID)
                guard !Task.isCancelled else { return }
                guard let current = fresh.episodes.first(where: { $0.line == episode.line && $0.name == episode.name }),
                      let url = URL(string: current.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
                    playbackError = "该集已变化或需要额外解析，请重新选择线路。"
                    return
                }
                detail = fresh
                let position = startPosition ?? history.resumeRecord(sourceID: item.sourceID, detailID: item.detailID,
                                                                       episode: current)?.resumePosition ?? 0
                if let playback {
                    history.record(.vod(item: playback.item, source: playback.source, episode: playback.queue.current),
                                   position: playback.position, duration: playback.duration)
                    playback.select(item: item, source: source, episodes: fresh.episodes,
                                    episode: current, keepPosition: false, episodeStart: history.episodeStart(for: item),
                                    resumePosition: position)
                } else {
                    isFullscreen = true
                    playback = OnDemandPlaybackSession(item: item, source: source,
                        episodes: fresh.episodes, selected: current, position: position,
                        episodeStart: history.episodeStart(for: item))
                }
            } catch {
                if !Task.isCancelled { playbackError = "获取播放地址失败：\(error.localizedDescription)" }
            }
        }
    }

}

private struct OnDemandPlayerView: View {
    @AppStorage("playback.autoAdvance") private var autoAdvance = true
    @AppStorage("playback.forwardBufferSeconds") private var bufferSeconds = 0.0
    @Environment(HistoryStore.self) private var history
    @Bindable var playback: OnDemandPlaybackSession
    @Binding var isFullscreen: Bool
    let onClose: () -> Void
    let onSourceSelected: (PlaybackSourceSelection) -> Void
    @State private var finished = false
    @State private var showingSourcePicker = false

    var body: some View {
        let episode = playback.queue.current
        let run = playback.revision
        let activeItem = playback.item
        let activeSource = playback.source
        PlayerPage(title: playback.item.title,
                   subtitle: "\(playback.source.name) · \(episode.line) · \(episode.name)" + (finished ? " · 已播完" : ""),
                   kind: .onDemand, isChoosingSource: showingSourcePicker, onSwitchSource: { showingSourcePicker = true },
                   fullscreen: $isFullscreen, onClose: onClose) { controls in
            if let url = URL(string: episode.url), ["http", "https"].contains(url.scheme?.lowercased()) {
                NativePlayerView(resource: PlaybackResource(url: url), controlsVisible: controls,
                    startPosition: playback.startPosition,
                    preferredBufferDuration: bufferSeconds,
                    onProgress: { position, duration in
                        if playback.acceptProgress(position, duration: duration, revision: run) {
                            history.record(.vod(item: activeItem, source: activeSource, episode: episode),
                                           position: position, duration: duration, deferred: true)
                        }
                    },
                    onEnded: {
                        guard playback.revision == run else { return }
                        finished = true
                        if autoAdvance { advance(after: episode.id) }
                    },
                    onPrevious: { if playback.revision == run { retreat(before: episode.id) } },
                    onNext: { if playback.revision == run { advance(after: episode.id) } },
                    canPrevious: playback.queue.hasPrevious, canNext: playback.queue.hasNext,
                    episodeStart: playback.episodeStart,
                    onSetEpisodeStart: { seconds in
                        history.setEpisodeStart(seconds, for: playback.item)
                        playback.setEpisodeStart(history.episodeStart(for: playback.item))
                    }, onCheckpoint: { history.flushPending() }, onReload: {
                        let (_, fresh) = try await EpisodeResolver.resolve(item: activeItem, source: activeSource, episode: episode)
                        return PlaybackResource(url: URL(string: fresh.url)!)
                    })
                    .id(run)
            } else {
                Text("此集需要额外解析，请切换线路。")
                    .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { controls.wrappedValue.toggle() } }
            }
        }
        .onChange(of: run) { finished = false }
        .onDisappear { history.flushPending() }
        .sheet(isPresented: $showingSourcePicker) {
            PlaybackSourcePicker(item: playback.item, source: playback.source,
                                 episodes: playback.allEpisodes, current: playback.queue.current) { selection in
                history.record(.vod(item: playback.item, source: playback.source, episode: playback.queue.current),
                               position: playback.position, duration: playback.duration)
                playback.select(item: selection.item, source: selection.source, episodes: selection.episodes,
                                episode: selection.episode, keepPosition: selection.keepPosition,
                                episodeStart: history.episodeStart(for: selection.item))
                onSourceSelected(selection)
                finished = false
                showingSourcePicker = false
            }
        }
    }

    private func retreat(before id: String) {
        history.flushPending()
        if playback.retreat(before: id) { finished = false }
    }

    private func advance(after id: String) {
        history.flushPending()
        if playback.advance(after: id) { finished = false }
    }

}
