import SwiftUI

struct MediaDetailView: View {
    @Environment(HistoryStore.self) private var history
    let provider: any ContentProvider
    let item: MediaItem
    var resumeRecord: WatchRecord? = nil
    @State private var detail: MediaDetail?
    @State private var errorMessage: String?
    @State private var playbackError: String?
    @State private var isPreparingPlayback = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var didHandleInitialResume = false
    @State private var playingResource: IdentifiedPlaybackResource?

    private var orderedLines: [String] {
        guard let detail else { return [] }
        let groups = Dictionary(grouping: detail.episodes, by: \MediaEpisode.line)
        return groups.keys.sorted {
            let left = groups[$0]!.contains(where: \.isDirectMedia)
            let right = groups[$1]!.contains(where: \.isDirectMedia)
            return left == right ? $0 < $1 : left && !right
        }
    }

    var body: some View {
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
                        if !detail.summary.isEmpty { Text(detail.summary) }
                        if let record = history.resumeRecord(sourceID: item.sourceID, detailID: item.detailID),
                           case .vod(_, _, let saved) = record.target,
                           let episode = detail.episodes.first(where: { $0.line == saved.line && $0.name == saved.name }) {
                            Button("继续观看 · \(episode.name) · \(Int(record.position) / 60):\(String(format: "%02d", Int(record.position) % 60))") {
                                play(episode, startPosition: record.resumePosition)
                            }
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
                                            .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
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
        .onDisappear { preparationTask?.cancel() }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("无法播放此线路", isPresented: Binding(
            get: { playbackError != nil }, set: { if !$0 { playbackError = nil } }
        )) { Button("好") {} } message: { Text(playbackError ?? "") }
        .fullScreenCover(item: $playingResource) { value in
            OnDemandPlayerView(item: item, source: provider.source, session: value, episodeStart: history.episodeStart(for: item))
        }
    }

    @MainActor private func load() async {
        do {
            let loaded = try await provider.detail(id: item.detailID)
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
        isPreparingPlayback = true
        preparationTask = Task { @MainActor in
            defer { isPreparingPlayback = false }
            do {
                let fresh = try await provider.detail(id: item.detailID)
                guard !Task.isCancelled else { return }
                guard let current = fresh.episodes.first(where: { $0.line == episode.line && $0.name == episode.name }),
                      let url = URL(string: current.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
                    playbackError = "该集已变化或需要额外解析，请重新选择线路。"
                    return
                }
                detail = fresh
                let position = startPosition ?? history.resumeRecord(sourceID: item.sourceID, detailID: item.detailID,
                                                                       episode: current)?.resumePosition ?? 0
                playingResource = IdentifiedPlaybackResource(episode: current, episodes: fresh.episodes, startPosition: position)
            } catch {
                if !Task.isCancelled { playbackError = "获取播放地址失败：\(error.localizedDescription)" }
            }
        }
    }

}

struct IdentifiedPlaybackResource: Identifiable {
    let id = UUID()
    let episode: MediaEpisode
    let episodes: [MediaEpisode]
    let startPosition: Double
}

private struct OnDemandPlayerView: View {
    @AppStorage("playback.autoAdvance") private var autoAdvance = true
    @AppStorage("playback.forwardBufferSeconds") private var bufferSeconds = 30.0
    @Environment(HistoryStore.self) private var history
    @State private var playback: OnDemandPlaybackSession
    @State private var finished = false
    @State private var showingSourcePicker = false

    init(item: MediaItem, source: TVBoxSite, session: IdentifiedPlaybackResource, episodeStart: Double) {
        _playback = State(initialValue: OnDemandPlaybackSession(item: item, source: source,
            episodes: session.episodes, selected: session.episode, position: session.startPosition, episodeStart: episodeStart))
    }

    var body: some View {
        let episode = playback.queue.current
        let run = playback.revision
        let activeItem = playback.item
        let activeSource = playback.source
        PlayerPage(title: playback.item.title,
                   subtitle: "\(playback.source.name) · \(episode.line) · \(episode.name)" + (finished ? " · 已播完" : ""),
                   kind: .onDemand, isChoosingSource: showingSourcePicker, onSwitchSource: { showingSourcePicker = true }) { controls in
            if let url = URL(string: episode.url), ["http", "https"].contains(url.scheme?.lowercased()) {
                NativePlayerView(resource: PlaybackResource(url: url), controlsVisible: controls,
                    startPosition: playback.startPosition,
                    preferredBufferDuration: bufferSeconds,
                    onProgress: { position, duration in
                        if playback.acceptProgress(position, duration: duration, revision: run) {
                            history.record(.vod(item: activeItem, source: activeSource, episode: episode),
                                           position: position, duration: duration)
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
                    })
                    .id(run)
            } else {
                Text("此集需要额外解析，请切换线路。")
                    .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { controls.wrappedValue.toggle() } }
            }
        }
        .sheet(isPresented: $showingSourcePicker) {
            PlaybackSourcePicker(item: playback.item, source: playback.source,
                                 episodes: playback.allEpisodes, current: playback.queue.current) { selection in
                history.record(.vod(item: playback.item, source: playback.source, episode: playback.queue.current),
                               position: playback.position, duration: playback.duration)
                playback.select(item: selection.item, source: selection.source, episodes: selection.episodes,
                                episode: selection.episode, keepPosition: selection.keepPosition,
                                episodeStart: history.episodeStart(for: selection.item))
                finished = false
                showingSourcePicker = false
            }
        }
    }

    private func retreat(before id: String) {
        if playback.retreat(before: id) { finished = false }
    }

    private func advance(after id: String) {
        if playback.advance(after: id) { finished = false }
    }
}
