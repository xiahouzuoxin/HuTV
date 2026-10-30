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

    init(item: MediaItem, source: TVBoxSite, episodes: [MediaEpisode], selected: MediaEpisode, position: Double) {
        self.item = item; self.source = source; allEpisodes = episodes
        queue = EpisodeQueue(episodes: episodes, selected: selected)
        let initialPosition = position.isFinite ? max(0, position) : 0
        startPosition = initialPosition
        self.position = initialPosition
    }

    func acceptProgress(_ position: Double, duration: Double, revision: UUID) -> Bool {
        guard self.revision == revision, position.isFinite, position >= 0 else { return false }
        self.position = position
        self.duration = duration.isFinite ? max(0, duration) : 0
        return true
    }

    func select(item: MediaItem, source: TVBoxSite, episodes: [MediaEpisode], episode: MediaEpisode, keepPosition: Bool) {
        startPosition = keepPosition ? position : 0
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

    private func resetEpisodePosition() {
        startPosition = 0; position = 0; duration = 0; revision = UUID()
    }
}
