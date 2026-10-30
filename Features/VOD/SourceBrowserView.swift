import SwiftUI

struct SourceBrowserView: View {
    let site: TVBoxSite
    var namespace: String? = nil
    @State private var categories: [MediaCategory] = []
    @State private var items: [MediaItem] = []
    @State private var selectedCategory: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var page = 1
    @State private var canLoadMore = true
    @State private var isLoadingMore = false
    @State private var paginationError: String?

    private var provider: (any ContentProvider)? { ContentProviderFactory.make(for: site, namespace: namespace) }

    var body: some View {
        Group {
            if let provider {
                content(provider: provider)
            } else {
                ContentUnavailableView("暂不支持", systemImage: "puzzlepiece.extension",
                                       description: Text("该数据源需要 Gateway 或尚无原生 Provider"))
            }
        }
        .navigationTitle(site.name)
        .alert("加载下一页失败", isPresented: Binding(
            get: { paginationError != nil }, set: { if !$0 { paginationError = nil } }
        )) { Button("好") {} } message: { Text(paginationError ?? "") }
    }

    @ViewBuilder
    private func content(provider: any ContentProvider) -> some View {
        if isLoading {
            ProgressView("加载内容…")
                .task { await load(provider: provider) }
        } else if let errorMessage {
            ContentUnavailableView {
                Label("数据源加载失败", systemImage: "exclamationmark.triangle")
            } description: { Text(errorMessage) } actions: {
                Button("重试") { Task { await load(provider: provider) } }
            }
        } else {
            ScrollView {
                if !categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            categoryButton("推荐", id: nil, provider: provider)
                            ForEach(categories) { category in
                                categoryButton(category.name, id: category.id, provider: provider)
                            }
                        }.padding(.horizontal)
                    }.padding(.vertical, 8)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12)], spacing: 16) {
                    ForEach(items) { item in
                        NavigationLink {
                            MediaDetailView(provider: provider, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: item.posterURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { Rectangle().fill(.quaternary) }
                                .frame(height: 155).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(item.title).font(.subheadline).lineLimit(2)
                            }
                        }.buttonStyle(.plain)
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadNextPage(provider: provider) } }
                        }
                    }
                    if isLoadingMore { ProgressView().gridCellColumns(3) }
                }.padding(.horizontal)
            }
        }
    }

    private func categoryButton(_ title: String, id: String?, provider: any ContentProvider) -> some View {
        Button(title) {
            selectedCategory = id
            page = 1
            canLoadMore = true
            Task { await loadItems(provider: provider) }
        }
        .buttonStyle(.borderedProminent)
        .tint(selectedCategory == id ? .accentColor : .secondary)
    }

    @MainActor private func load(provider: any ContentProvider) async {
        isLoading = true; errorMessage = nil
        do {
            async let loadedCategories = provider.categories()
            async let loadedItems = provider.items(categoryID: selectedCategory, page: 1)
            (categories, items) = try await (loadedCategories, loadedItems)
            page = 1
            canLoadMore = !items.isEmpty
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    @MainActor private func loadItems(provider: any ContentProvider) async {
        do {
            items = try await provider.items(categoryID: selectedCategory, page: 1)
            page = 1
            canLoadMore = !items.isEmpty
            errorMessage = nil
        }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func loadNextPage(provider: any ContentProvider) async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await provider.items(categoryID: selectedCategory, page: page + 1)
            guard !next.isEmpty else { canLoadMore = false; return }
            let known = Set(items.map(\.id))
            let unique = next.filter { !known.contains($0.id) }
            if unique.isEmpty { canLoadMore = false }
            else { items.append(contentsOf: unique); page += 1 }
        } catch { paginationError = error.localizedDescription }
    }
}
