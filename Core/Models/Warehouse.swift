import Foundation

enum SubscriptionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cms, live, tvbox
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cms: "点播 API"
        case .live: "直播 M3U / TXT"
        case .tvbox: "TVBox 配置"
        }
    }
    var hint: String {
        switch self {
        case .cms: "填写标准 CMS JSON 接口，可浏览分类、搜索和选集。优先使用返回 M3U8 或 MP4 的接口。"
        case .live: "填写 M3U 或 TVBox TXT 频道列表地址，添加后可浏览和搜索直播频道。"
        case .tvbox: "填写包含 sites 或 lives 的配置直链。支持图片包装配置；JAR 爬虫源暂不能在本机运行。"
        }
    }
    var placeholder: String {
        switch self {
        case .cms: "https://example.com/api.php/provide/vod/"
        case .live: "https://example.com/playlist.m3u"
        case .tvbox: "https://example.com/config.json"
        }
    }
}

struct Warehouse: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: SubscriptionKind
    var configURL: URL
    var config: TVBoxConfig
    var importedAt: Date
    var updatedAt: Date
    var etag: String?
    var lastModified: String?

    init(id: UUID = UUID(), name: String, kind: SubscriptionKind = .tvbox,
         configURL: URL, config: TVBoxConfig, importedAt: Date = .now,
         updatedAt: Date? = nil, etag: String? = nil, lastModified: String? = nil) {
        self.id = id; self.name = name; self.kind = kind
        self.configURL = configURL; self.config = config
        self.importedAt = importedAt; self.updatedAt = updatedAt ?? importedAt
        self.etag = etag; self.lastModified = lastModified
    }
}
