import SwiftUI

struct SourceBrowserView: View {
    let site: TVBoxSite
    var namespace: String? = nil
    @State private var model = SourceBrowserModel()

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
        .onDisappear { model.cancel() }
        .task {
            if let provider, model.isLoading || model.items.isEmpty { await model.load(provider: provider) }
        }
        .alert("加载内容失败", isPresented: Binding(
            get: { model.paginationError != nil }, set: { if !$0 { model.paginationError = nil } }
        )) { Button("好") {} } message: { Text(model.paginationError ?? "") }
    }

    @ViewBuilder
    private func content(provider: any ContentProvider) -> some View {
        if model.isLoading {
            ProgressView("加载内容…")
        } else if let errorMessage = model.errorMessage {
            ContentUnavailableView {
                Label("数据源加载失败", systemImage: "exclamationmark.triangle")
            } description: { Text(errorMessage) } actions: {
                Button("重试") { Task { await model.load(provider: provider) } }
            }
        } else {
            ScrollView {
                if !model.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            categoryButton("推荐", id: nil, provider: provider)
                            ForEach(model.categories) { category in
                                categoryButton(category.name, id: category.id, provider: provider)
                            }
                        }.padding(.horizontal)
                    }.padding(.vertical, 8)
                }

                if model.isLoadingItems { ProgressView("加载分类…") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 12, alignment: .top)], alignment: .center, spacing: 16) {
                    ForEach(model.items) { item in
                        NavigationLink {
                            MediaDetailView(provider: provider, item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // The grid determines the poster width; loaded image dimensions
                                // must never participate in sizing the card.
                                Rectangle().fill(.quaternary)
                                    .frame(height: 155)
                                    .overlay {
                                        GeometryReader { geometry in
                                            AsyncImage(url: item.posterURL) { image in
                                                image.resizable().scaledToFill()
                                            } placeholder: { Color.clear }
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        if let rating = item.rating { MediaRatingBadge(rating: rating).padding(5) }
                                    }
                                Text(item.title).font(.subheadline).lineLimit(2, reservesSpace: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                        .onAppear {
                            if item.id == model.items.last?.id { Task { await model.loadNextPage(provider: provider) } }
                        }
                    }
                    if model.isLoadingMore { ProgressView().gridCellColumns(3) }
                }.padding(.horizontal)
            }
        }
    }

    private func categoryButton(_ title: String, id: String?, provider: any ContentProvider) -> some View {
        Button(title) { model.select(id, provider: provider) }
            .buttonStyle(.borderedProminent)
            .tint(model.selectedCategory == id ? .accentColor : .secondary)
    }
}

struct MediaRatingBadge: View {
    let rating: MediaRating
    var body: some View {
        HStack(spacing: 3) {
            Text(rating.source.hasPrefix("豆瓣") ? "豆瓣" : "源")
                .foregroundStyle(rating.source.hasPrefix("豆瓣")
                    ? Color(red: 0.65, green: 0.82, blue: 0.70) : Color.white.opacity(0.65))
            Text(rating.text).foregroundStyle(.white.opacity(0.85))
        }
            .font(.caption2)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(rating.source)，\(rating.text) 分，满分 10 分")
    }
}
