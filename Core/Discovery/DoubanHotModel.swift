import Foundation
import Observation

enum DoubanHotCategory: String, CaseIterable, Identifiable {
    case movie, tv
    var id: String { rawValue }
    var title: String { self == .movie ? "电影" : "剧集" }
    var tags: [String] {
        self == .movie
            ? ["热门", "最新", "经典", "豆瓣高分", "冷门佳片", "华语", "欧美", "韩国", "日本", "动作", "喜剧", "爱情", "科幻", "悬疑", "恐怖", "治愈", "可播放"]
            : ["热门", "美剧", "英剧", "韩剧", "日剧", "国产剧", "港剧", "日本动画", "综艺", "纪录片"]
    }
}

struct DoubanHotItem: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let cover: URL?
    let url: URL?
    let rating: MediaRating?

    enum CodingKeys: String, CodingKey { case id, title, cover, url, rate }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? box.decode(String.self, forKey: .id) { id = value }
        else { id = String(try box.decode(Int.self, forKey: .id)) }
        title = try box.decode(String.self, forKey: .title)
        func httpsURL(_ key: CodingKeys) -> URL? {
            guard let raw = try? box.decode(String.self, forKey: key), let url = URL(string: raw),
                  url.scheme == "https" else { return nil }
            return url
        }
        cover = httpsURL(.cover)
        url = httpsURL(.url)
        let raw: String
        if let string = try? box.decode(String.self, forKey: .rate) { raw = string }
        else if let number = try? box.decode(Double.self, forKey: .rate) { raw = String(number) }
        else { raw = "" }
        rating = MediaRating(raw: raw, source: "豆瓣评分")
    }
}

private struct DoubanHotResponse: Decodable { let subjects: [DoubanHotItem] }

@MainActor @Observable
final class DoubanHotModel {
    private(set) var items: [DoubanHotItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private let client: any HTTPDataLoading
    private let diskCache: DoubanHotCache
    private let now: () -> Date
    private var cache: [String: (date: Date, items: [DoubanHotItem])] = [:]
    private var generation = UUID()
    static let cacheLifetime: TimeInterval = 24 * 60 * 60

    init(client: any HTTPDataLoading = BoundedHTTPClient(), diskCache: DoubanHotCache = .shared,
         now: @escaping () -> Date = Date.init) {
        self.client = client; self.diskCache = diskCache; self.now = now
    }

    func invalidate(_ category: DoubanHotCategory, tag: String = "热门") {
        let key = "\(category.rawValue)|\(tag)"
        if let cached = cache[key] { cache[key] = (.distantPast, cached.items) }
    }

    func load(_ category: DoubanHotCategory, tag: String = "热门") async {
        guard category.tags.contains(tag) else { return }
        let key = "\(category.rawValue)|\(tag)"
        let run = UUID()
        generation = run
        errorMessage = nil
        items = cache[key]?.items ?? []
        isLoading = true
        defer { if generation == run { isLoading = false } }
        if cache[key] == nil, let record = await diskCache.read(key),
           let response = try? JSONDecoder().decode(DoubanHotResponse.self, from: record.data) {
            guard generation == run, !Task.isCancelled else { return }
            cache[key] = (record.date, Self.unique(response.subjects))
        }
        guard generation == run, !Task.isCancelled else { return }
        items = cache[key]?.items ?? []
        if let cached = cache[key] {
            let age = now().timeIntervalSince(cached.date)
            if age >= 0 && age < Self.cacheLifetime { return }
        }
        var components = URLComponents(string: "https://movie.douban.com/j/search_subjects")!
        components.queryItems = [URLQueryItem(name: "type", value: category.rawValue),
            URLQueryItem(name: "tag", value: tag), URLQueryItem(name: "sort", value: "recommend"),
            URLQueryItem(name: "page_limit", value: "20"), URLQueryItem(name: "page_start", value: "0")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await client.data(for: request, maximumBytes: 1024 * 1024)
            let response = try JSONDecoder().decode(DoubanHotResponse.self, from: data)
            guard generation == run, !Task.isCancelled else { return }
            items = Self.unique(response.subjects)
            let date = now()
            cache[key] = (date, items)
            await diskCache.write(.init(date: date, data: data), key: key)
        } catch {
            guard generation == run, !Task.isCancelled else { return }
            errorMessage = "暂时无法获取此分类，请稍后重试。"
        }
    }
    private static func unique(_ values: [DoubanHotItem]) -> [DoubanHotItem] {
        var seen = Set<String>()
        return Array(values.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted }.prefix(20))
    }

}
