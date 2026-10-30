import Foundation

struct MediaItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let sourceID: String
    let title: String
    let posterURL: URL?
    let detailID: String
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
