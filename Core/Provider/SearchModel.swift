import Foundation
import Observation

struct SearchSource: Identifiable, Sendable {
    let provider: any ContentProvider
    let title: String
    var id: String { provider.id }
}

struct SourceSearchResults: Identifiable, Sendable {
    let source: SearchSource
    var items: [MediaItem] = []
    var isLoading = true
    var error: String?
    var id: String { source.id }
}

@MainActor @Observable
final class SearchModel {
    private(set) var groups: [SourceSearchResults] = []
    private(set) var hasSearched = false
    private(set) var searchedKeyword = ""
    private var generation = UUID()

    func reset() {
        generation = UUID()
        groups = []
        hasSearched = false
        searchedKeyword = ""
    }

    func search(_ keyword: String, sources: [SearchSource]) async {
        guard !Task.isCancelled else { return }
        let run = UUID()
        generation = run
        hasSearched = true
        searchedKeyword = keyword
        groups = sources.map { SourceSearchResults(source: $0) }
        await withTaskGroup(of: (String, [MediaItem], String?).self) { group in
            for source in sources {
                group.addTask {
                    do { return (source.id, try await source.provider.search(keyword: keyword), nil) }
                    catch { return (source.id, [], error.localizedDescription) }
                }
            }
            for await (id, items, error) in group {
                guard !Task.isCancelled, generation == run else { group.cancelAll(); return }
                if let index = groups.firstIndex(where: { $0.id == id }) {
                    groups[index].items = items
                    groups[index].isLoading = false
                    groups[index].error = error
                }
            }
        }
    }
}
