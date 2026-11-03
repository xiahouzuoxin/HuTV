import Foundation

struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let title: String
    let posterURL: URL?
    let detailID: String
    var rating: MediaRating? = nil
}

struct MediaCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct MediaEpisode: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: String
    let line: String

    var isM3U8: Bool {
        guard let url = URL(string: url), ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
        return url.pathExtension.lowercased() == "m3u8"
    }

    /// Rank whole lines, preserving episode order and the source order of equally ranked lines.
    static func prioritized(_ episodes: [MediaEpisode]) -> [MediaEpisode] {
        var lines: [String] = []
        var groups: [String: [MediaEpisode]] = [:]
        var ranks: [String: Int] = [:]
        for episode in episodes {
            if groups[episode.line] == nil { lines.append(episode.line) }
            groups[episode.line, default: []].append(episode)
            let rank = episode.isM3U8 ? 0 : (episode.isDirectMedia ? 1 : 2)
            ranks[episode.line] = min(ranks[episode.line] ?? 2, rank)
        }
        return lines.enumerated().sorted {
            let left = ranks[$0.element]!, right = ranks[$1.element]!
            return left == right ? $0.offset < $1.offset : left < right
        }.flatMap { groups[$0.element] ?? [] }
    }

    var isDirectMedia: Bool {
        guard let url = URL(string: url) else { return false }
        return ["m3u8", "mp4", "m4v", "mov", "mp3", "m4a"].contains(url.pathExtension.lowercased())
    }
}

struct MediaDetail: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let posterURL: URL?
    let summary: String
    let metadata: String
    let episodes: [MediaEpisode]
    var director: String = ""
    var actors: String = ""
    var language: String = ""
    var releaseDate: String = ""
    var runningTime: String = ""
    var category: String = ""
    var rating: MediaRating? = nil
}

protocol ContentProvider: Sendable {
    var id: String { get }
    var source: TVBoxSite { get }
    func categories() async throws -> [MediaCategory]
    func items(categoryID: String?, page: Int) async throws -> [MediaItem]
    func search(keyword: String) async throws -> [MediaItem]
    func detail(id: String) async throws -> MediaDetail
}

enum ContentProviderFactory {
    static func make(for site: TVBoxSite, namespace: String? = nil) -> (any ContentProvider)? {
        guard site.runtime == .nativeAPI else { return nil }
        return StandardCMSProvider(id: [namespace, site.key].compactMap { $0 }.joined(separator: "/"), source: site)
    }
}

/// Ratings are supplied by the subscription, including any claimed Douban score.
struct MediaRating: Codable, Hashable, Sendable {
    let value: Double
    let source: String
    var text: String { String(format: "%.1f", value) }

    init?(raw: String, source: String) {
        guard let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > 0, value <= 10 else { return nil }
        self.value = value
        self.source = source
    }
}
