import Foundation

enum ProviderError: LocalizedError {
    case invalidURL
    case invalidData
    case noPlayableEpisodes

    var errorDescription: String? {
        switch self {
        case .invalidURL: "数据源 API 地址无效"
        case .invalidData: "数据源返回了无法识别的数据"
        case .noPlayableEpisodes: "没有找到可播放线路"
        }
    }
}

struct StandardCMSProvider: ContentProvider {
    let id: String
    let source: TVBoxSite
    let client: any HTTPDataLoading

    init(id: String, source: TVBoxSite, client: any HTTPDataLoading = BoundedHTTPClient()) {
        self.id = id; self.source = source; self.client = client
    }

    private let maxBytes = 8 * 1024 * 1024

    func categories() async throws -> [MediaCategory] {
        let response: CMSResponse = try await request(["ac": "list"])
        return response.classes.map { MediaCategory(id: $0.id, name: $0.name) }
    }

    func items(categoryID: String?, page: Int) async throws -> [MediaItem] {
        var query = ["ac": "detail", "pg": String(max(1, page))]
        if let categoryID, !categoryID.isEmpty { query["t"] = categoryID }
        let response: CMSResponse = try await request(query)
        return response.list.map(mediaItem)
    }

    func search(keyword: String) async throws -> [MediaItem] {
        let response: CMSResponse = try await request(["ac": "detail", "wd": keyword])
        return response.list.map(mediaItem)
    }

    func detail(id: String) async throws -> MediaDetail {
        let response: CMSResponse = try await request(["ac": "detail", "ids": id])
        guard let vod = response.list.first else { throw ProviderError.invalidData }
        let lines = vod.playFrom.components(separatedBy: "$$$")
        let playlists = vod.playURL.components(separatedBy: "$$$")
        var episodes: [MediaEpisode] = []

        for (lineIndex, playlist) in playlists.enumerated() {
            let line = lines.indices.contains(lineIndex) ? lines[lineIndex] : "线路 \(lineIndex + 1)"
            for (episodeIndex, entry) in playlist.components(separatedBy: "#").enumerated() {
                let parts = entry.split(separator: "$", maxSplits: 1).map(String.init)
                guard parts.count == 2, !parts[1].isEmpty else { continue }
                episodes.append(MediaEpisode(
                    id: "\(lineIndex)|\(episodeIndex)|\(parts[1])",
                    name: parts[0].isEmpty ? "第 \(episodeIndex + 1) 集" : parts[0],
                    url: parts[1],
                    line: line
                ))
            }
        }

        return MediaDetail(
            id: vod.id,
            title: vod.name,
            posterURL: URL(string: vod.picture),
            summary: vod.content.removingHTML,
            metadata: [vod.year, vod.area, vod.remarks].filter { !$0.isEmpty }.joined(separator: " · "),
            episodes: episodes
        )
    }

    private func mediaItem(_ vod: CMSVod) -> MediaItem {
        MediaItem(id: "\(id)|\(vod.id)", sourceID: id, title: vod.name,
                  posterURL: URL(string: vod.picture), detailID: vod.id)
    }

    private func request<T: Decodable>(_ query: [String: String]) async throws -> T {
        guard var components = URLComponents(string: source.api) else { throw ProviderError.invalidURL }
        var items = components.queryItems ?? []
        for (name, value) in query {
            items.removeAll { $0.name == name }
            items.append(URLQueryItem(name: name, value: value))
        }
        components.queryItems = items
        guard let url = components.url else { throw ProviderError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await client.data(for: request, maximumBytes: maxBytes)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.invalidData
        }
    }
}

struct CMSResponse: Decodable {
    var classes: [CMSClass] = []
    var list: [CMSVod] = []

    enum CodingKeys: String, CodingKey { case classes = "class", list }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        guard box.contains(.classes) || box.contains(.list) else {
            throw ProviderError.invalidData
        }
        classes = try box.decodeIfPresent([CMSClass].self, forKey: .classes) ?? []
        list = try box.decodeIfPresent([CMSVod].self, forKey: .list) ?? []
    }
}

struct CMSClass: Decodable {
    let id: String
    let name: String
    enum CodingKeys: String, CodingKey { case id = "type_id", name = "type_name" }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.flexibleString(.id)
        name = box.flexibleString(.name)
    }
}

struct CMSVod: Decodable {
    let id: String
    let name: String
    let picture: String
    let remarks: String
    let year: String
    let area: String
    let content: String
    let playFrom: String
    let playURL: String

    enum CodingKeys: String, CodingKey {
        case id = "vod_id", name = "vod_name", picture = "vod_pic", remarks = "vod_remarks"
        case year = "vod_year", area = "vod_area", content = "vod_content"
        case playFrom = "vod_play_from", playURL = "vod_play_url"
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = box.flexibleString(.id)
        name = box.flexibleString(.name)
        picture = box.flexibleString(.picture)
        remarks = box.flexibleString(.remarks)
        year = box.flexibleString(.year)
        area = box.flexibleString(.area)
        content = box.flexibleString(.content)
        playFrom = box.flexibleString(.playFrom)
        playURL = box.flexibleString(.playURL)
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(_ key: Key) -> String {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        return ""
    }
}

private extension String {
    var removingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
