import Foundation
import Observation

@MainActor @Observable
final class SourceBrowserModel {
    private(set) var categories: [MediaCategory] = []
    private(set) var items: [MediaItem] = []
    private(set) var selectedCategory: String?
    private(set) var isLoading = true
    private(set) var isLoadingItems = false
    private(set) var errorMessage: String?
    private(set) var page = 1
    private(set) var canLoadMore = true
    private(set) var isLoadingMore = false
    var paginationError: String?
    private var generation = UUID()
    private var selectionTask: Task<Void, Never>?

    func cancel() {
        generation = UUID()
        selectionTask?.cancel(); selectionTask = nil
        isLoadingItems = false; isLoadingMore = false
    }

    func load(provider: any ContentProvider) async {
        cancel()
        let run = generation
        isLoading = true; errorMessage = nil
        do {
            async let loadedCategories = provider.categories()
            async let loadedItems = provider.items(categoryID: selectedCategory, page: 1)
            let result = try await (loadedCategories, loadedItems)
            guard run == generation, !Task.isCancelled else { return }
            categories = result.0; items = unique(result.1)
            page = 1; canLoadMore = !items.isEmpty
        } catch {
            guard run == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        if run == generation { isLoading = false }
    }

    func select(_ category: String?, provider: any ContentProvider) {
        cancel()
        selectedCategory = category; page = 1; items = []
        isLoadingItems = true; canLoadMore = false; paginationError = nil
        let run = generation
        selectionTask = Task {
            do {
                let result = try await provider.items(categoryID: category, page: 1)
                guard run == generation, !Task.isCancelled else { return }
                items = unique(result); canLoadMore = !items.isEmpty; errorMessage = nil
            } catch {
                guard run == generation, !Task.isCancelled else { return }
                paginationError = error.localizedDescription
            }
            if run == generation { isLoadingItems = false }
        }
    }

    func loadNextPage(provider: any ContentProvider) async {
        guard !isLoading, !isLoadingItems, canLoadMore, !isLoadingMore else { return }
        let run = generation, category = selectedCategory, nextPage = page + 1
        isLoadingMore = true
        defer { if run == generation { isLoadingMore = false } }
        do {
            let next = try await provider.items(categoryID: category, page: nextPage)
            guard run == generation, !Task.isCancelled else { return }
            let known = Set(items.map(\.id))
            let additions = unique(next).filter { !known.contains($0.id) }
            if additions.isEmpty { canLoadMore = false }
            else { items.append(contentsOf: additions); page = nextPage }
        } catch {
            guard run == generation, !Task.isCancelled else { return }
            paginationError = error.localizedDescription
        }
    }

    private func unique(_ values: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
}
