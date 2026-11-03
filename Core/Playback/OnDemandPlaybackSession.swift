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

    func setEpisodeStart(_ seconds: Double) { episodeStart = Self.validStart(seconds) }
    private static func validStart(_ value: Double) -> Double {
        value.isFinite ? min(86_400, max(0, value.rounded(.down))) : 0
    }

    private func resetEpisodePosition() {
        startPosition = episodeStart; position = episodeStart; duration = 0; revision = UUID()
    }
}
