import Foundation
import Observation

/// A playback identity includes the source and episode, not just an episode URL.
@MainActor @Observable
final class OnDemandPlaybackSession {
    private(set) var item: MediaItem
    private(set) var source: TVBoxSite
    private(set) var allEpisodes: [MediaEpisode]
    private(set) var queue: EpisodeQueue
    private(set) var revision = UUID()
    private(set) var startPosition: Double
    private(set) var position: Double
    private(set) var duration = 0.0
    private(set) var isResolving = false
    var resolutionError: String?
    private(set) var episodeStart: Double

    init(item: MediaItem, source: TVBoxSite, episodes: [MediaEpisode], selected: MediaEpisode, position: Double, episodeStart: Double = 0) {
        self.item = item; self.source = source; allEpisodes = episodes
        queue = EpisodeQueue(episodes: episodes, selected: selected)
        let initialPosition = position.isFinite ? max(0, position) : 0
        let opening = Self.validStart(episodeStart)
        self.episodeStart = opening
        startPosition = max(initialPosition, opening)
        self.position = max(initialPosition, opening)
    }

    func acceptProgress(_ position: Double, duration: Double, revision: UUID) -> Bool {
        guard self.revision == revision, position.isFinite, position >= 0 else { return false }
        self.position = position
        self.duration = duration.isFinite ? max(0, duration) : 0
        return true
    }

    func select(item: MediaItem, source: TVBoxSite, episodes: [MediaEpisode], episode: MediaEpisode, keepPosition: Bool, episodeStart: Double = 0, resumePosition: Double = 0) {
        self.episodeStart = Self.validStart(episodeStart)
        let resume = resumePosition.isFinite ? max(0, resumePosition) : 0
        startPosition = max(keepPosition ? position : resume, self.episodeStart)
        position = startPosition; duration = 0
        self.item = item; self.source = source; allEpisodes = episodes
        queue = EpisodeQueue(episodes: episodes, selected: episode)
        revision = UUID()
    }

    @discardableResult func advance(after id: String) -> Bool {
        guard queue.advance(after: id) else { return false }
        resetEpisodePosition(); return true
    }

    @discardableResult func retreat(before id: String) -> Bool {
        guard queue.retreat(before: id) else { return false }
        resetEpisodePosition(); return true
    }

    @discardableResult
    func move(by offset: Int, provider: (any ContentProvider)? = nil) async -> Bool {
        let index = queue.index + offset
        guard !isResolving, queue.episodes.indices.contains(index) else { return false }
        isResolving = true; resolutionError = nil
        defer { isResolving = false }
        let run = revision
        let oldItem = item, oldSource = source
        do {
            let (detail, episode) = try await EpisodeResolver.resolve(item: oldItem, source: oldSource,
                episode: queue.episodes[index], provider: provider)
            guard !Task.isCancelled, revision == run else { return false }
            select(item: oldItem, source: oldSource, episodes: detail.episodes, episode: episode,
                   keepPosition: false, episodeStart: episodeStart)
            return true
        } catch {
            if !Task.isCancelled, revision == run { resolutionError = "获取最新播放地址失败：\(error.localizedDescription)" }
            return false
        }
    }

    func setEpisodeStart(_ seconds: Double) { episodeStart = Self.validStart(seconds) }
    private static func validStart(_ value: Double) -> Double {
        value.isFinite ? min(86_400, max(0, value.rounded(.down))) : 0
    }

    private func resetEpisodePosition() {
        startPosition = episodeStart; position = episodeStart; duration = 0; revision = UUID()
    }
}
