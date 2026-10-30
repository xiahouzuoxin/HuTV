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

extension SourceSearchResults {
    /// Successful nonempty sources first; ties preserve subscription order.
    static func ranked(_ groups: [SourceSearchResults]) -> [SourceSearchResults] {
        func rank(_ group: SourceSearchResults) -> Int {
            if !group.isLoading && group.error == nil && !group.items.isEmpty { return 0 }
            if group.isLoading { return 1 }
            return group.error == nil ? 2 : 3
        }
        return groups.enumerated().sorted { left, right in
            let lhs = rank(left.element), rhs = rank(right.element)
            if lhs != rhs { return lhs < rhs }
            if lhs == 0 && left.element.items.count != right.element.items.count {
                return left.element.items.count > right.element.items.count
            }
            return left.offset < right.offset
        }.map(\.element)
    }
}

@MainActor @Observable
final class SearchModel {
    private(set) var groups: [SourceSearchResults] = []
    var rankedGroups: [SourceSearchResults] { SourceSearchResults.ranked(groups) }
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
