import Foundation

enum EpisodeResolver {
    static func resolve(item: MediaItem, source: TVBoxSite, episode: MediaEpisode,
                        provider: (any ContentProvider)? = nil) async throws -> (MediaDetail, MediaEpisode) {
        guard let provider = provider ?? ContentProviderFactory.make(for: source) else { throw ProviderError.invalidData }
        let detail = try await provider.detail(id: item.detailID)
        try Task.checkCancellation()
        guard let current = detail.episodes.first(where: { $0.line == episode.line && $0.name == episode.name }),
              let url = URL(string: current.url), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw ProviderError.invalidData
        }
        return (detail, current)
    }
}
