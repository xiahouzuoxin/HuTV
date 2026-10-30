import Foundation

enum DefaultSubscriptions {
    static let version = 3
    static let sources: [(name: String, api: String)] = [
        ("暴风资源", "https://bfzyapi.com/api.php/provide/vod/"),
        ("非凡资源", "https://api.ffzyapi.com/api.php/provide/vod/"),
        ("索尼资源", "https://suoniapi.com/api.php/provide/vod/"),
        ("魔都动漫", "https://www.mdzyapi.com/api.php/provide/vod/"),
        ("量子资源", "https://cj.lziapi.com/api.php/provide/vod/"),
        ("红牛资源", "https://www.hongniuzy2.com/api.php/provide/vod/"),
        ("360资源", "https://360zy.com/api.php/provide/vod/"),
        ("无尽资源", "https://api.wujinapi.com/api.php/provide/vod/"),
        ("极速资源", "https://jszyapi.com/api.php/provide/vod/"),
        ("光速资源", "https://api.guangsuapi.com/api.php/provide/vod/"),
        ("ikun资源", "https://ikunzyapi.com/api.php/provide/vod/"),
        ("U酷资源", "https://api.ukuapi.com/api.php/provide/vod/"),
        ("闪电资源", "https://sdzyapi.com/api.php/provide/vod/")
    ]

    static let liveSources: [(name: String, url: String)] = [
        ("IPTV-org 中文直播", "https://iptv-org.github.io/iptv/languages/zho.m3u"),
        ("Free-TV 国际直播", "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8"),
        ("IPTV-org 新闻直播", "https://iptv-org.github.io/iptv/categories/news.m3u")
    ]

    static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        func canonical(_ url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.host = components.host?.lowercased()
            while components.path.hasSuffix("/") { components.path.removeLast() }
            return components.string ?? url.absoluteString
        }
        return canonical(lhs) == canonical(rhs)
    }

    // Version 1: four CMS sources; version 2: eight CMS and two live lists.
    // Preserve this append order. Upgrade only adds new presets,
    // so presets deliberately deleted by existing users are not resurrected.
    static func make(since version: Int = 0) -> [Warehouse] {
        guard version < Self.version else { return [] }
        let cms = Array(sources.dropFirst(version >= 2 ? 8 : version >= 1 ? 4 : 0))
        let live = Array(liveSources.dropFirst(version >= 2 ? 2 : 0))
        return cms.map { preset in
            let url = URL(string: preset.api)!
            let site = TVBoxSite(key: "cms", name: preset.name, api: preset.api)
            return Warehouse(name: preset.name, kind: .cms, configURL: url,
                             config: TVBoxConfig(sites: [site]))
        } + live.map { preset in
            Warehouse(name: preset.name, kind: .live, configURL: URL(string: preset.url)!,
                      config: TVBoxConfig(lives: [TVBoxLive(name: preset.name, url: preset.url)]))
        }
    }
}
