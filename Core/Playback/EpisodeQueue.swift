import Foundation

/// Keeps playback within the selected line, in the order supplied by the source.
struct EpisodeQueue {
    let episodes: [MediaEpisode]
    private(set) var index: Int

    init(episodes: [MediaEpisode], selected: MediaEpisode) {
        let lineEpisodes = episodes.filter { $0.line == selected.line }
        if let index = lineEpisodes.firstIndex(where: { $0.id == selected.id }) {
            self.episodes = lineEpisodes
            self.index = index
        } else {
            self.episodes = [selected]
            self.index = 0
        }
    }

    var current: MediaEpisode { episodes[index] }
    var hasPrevious: Bool { index > 0 }
    var hasNext: Bool { index + 1 < episodes.count }

    @discardableResult mutating func retreat(before episodeID: String) -> Bool {
        guard current.id == episodeID, hasPrevious else { return false }
        index -= 1
        return true
    }

    @discardableResult mutating func advance(after episodeID: String) -> Bool {
        guard current.id == episodeID, hasNext else { return false }
        index += 1
        return true
    }
}
