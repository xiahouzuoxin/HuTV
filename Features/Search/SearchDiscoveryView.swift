import SwiftUI

struct SearchDiscoveryView: View {
    let searches: [String]
    let hasSources: Bool
    let onSearch: (String) -> Void
    let onRemove: (String) -> Void
    let onClear: () -> Void
    @State private var category: DoubanHotCategory = .movie
    @State var hot = DoubanHotModel()
    @State private var refresh = 0
    @State private var movieTag = "热门"
    @State private var tvTag = "热门"
    private var selectedTag: String { category == .movie ? movieTag : tvTag }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if geometry.size.width >= 650 {
                    HStack(alignment: .top, spacing: 24) {
                        history.frame(width: min(200, geometry.size.width * 0.22))
                        popular.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(16)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        history
                        popular
                    }.padding(16)
                }
            }
        }
        .task(id: "\(category.rawValue)|\(selectedTag)|\(refresh)") { await hot.load(category, tag: selectedTag) }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("搜索历史").font(.headline)
                Spacer()
                if !searches.isEmpty {
                    Button("清空", action: onClear).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if searches.isEmpty {
                Text("还没有搜索记录").font(.subheadline).foregroundStyle(.secondary)
            } else {
                SearchTagLayout(spacing: 8) {
                    ForEach(searches, id: \.self) { value in
                        Button { onSearch(value) } label: {
                            Text(value).font(.subheadline).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除", role: .destructive) { onRemove(value) }
                        }
                        .accessibilityHint("搜索此关键词，长按可删除")
                    }
                }
            }
            if !hasSources {
                Text("先在订阅页添加点播源，再搜索影片。").font(.footnote).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var popular: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("豆瓣热门").font(.headline)
                Spacer()
                Button { hot.invalidate(category, tag: selectedTag); refresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .foregroundStyle(.secondary).disabled(hot.isLoading)
                    .accessibilityLabel("刷新豆瓣热门")
            }
            Picker("热门类型", selection: $category) {
                ForEach(DoubanHotCategory.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(category.tags, id: \.self) { tag in
                        Button {
                            if category == .movie { movieTag = tag } else { tvTag = tag }
                        } label: {
                            Text(tag).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selectedTag == tag ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(selectedTag == tag ? Color.accentColor : Color.primary)
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selectedTag == tag ? .isSelected : [])
                    }
                }
            }
            if selectedTag == "可播放" {
                Text("豆瓣的可播放标记不代表当前订阅源一定提供该影片。").font(.caption).foregroundStyle(.secondary)
            }
            if hot.isLoading && hot.items.isEmpty {
                ProgressView("加载热门…").frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            if let error = hot.errorMessage {
                HStack {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { hot.invalidate(category, tag: selectedTag); refresh += 1 }.font(.footnote)
                }
            } else if !hot.isLoading && hot.items.isEmpty {
                Text("暂无热门影片").font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 12)], alignment: .leading, spacing: 14) {
                ForEach(hot.items) { item in
                    Button { onSearch(item.title) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            DoubanPosterView(url: item.cover)
                                .overlay(alignment: .topTrailing) {
                                    if let rating = item.rating { MediaRatingBadge(rating: rating).padding(5) }
                                }
                            Text(item.title).font(.subheadline).lineLimit(2, reservesSpace: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                        .accessibilityHint("在已订阅资源中搜索")
                        .contextMenu {
                            if let url = item.url, url.host == "movie.douban.com" { Link("在豆瓣查看", destination: url) }
                        }
                }
            }
            Link("数据来自豆瓣 · 点击影片搜索订阅源", destination: URL(string: "https://movie.douban.com/")!)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SearchTagLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in layout.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: min(bounds.width, subviews[index].sizeThatFits(.unspecified).width), height: nil))
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = max(0, width.isFinite ? width : 320)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, view.sizeThatFits(.unspecified).width), height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
