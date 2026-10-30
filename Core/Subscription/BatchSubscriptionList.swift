import Foundation

struct BatchSubscriptionEntry: Identifiable, Sendable {
    let id: Int
    let name: String
    let address: String
    let kind: SubscriptionKind?
    let issue: String?
}

enum BatchListError: LocalizedError {
    case invalidJSON, tooMany, tooLarge, invalidURL
    var errorDescription: String? {
        switch self {
        case .invalidJSON: "需要 JSON 数组，例如 [{\"name\":\"我的源\",\"api\":\"https://example.com/api\"}]。"
        case .tooMany: "单次最多导入 200 个订阅。"
        case .tooLarge: "JSON 列表不能超过 5 MB。"
        case .invalidURL: "请输入 HTTP(S) JSON 地址或 GitHub 文件链接。"
        }
    }
}

struct BatchSubscriptionList {
    static let maximumBytes = 5 * 1024 * 1024

    func decode(_ data: Data) throws -> [BatchSubscriptionEntry] {
        guard data.count <= Self.maximumBytes else { throw BatchListError.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw BatchListError.invalidJSON }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        guard let list = try? JSONSerialization.jsonObject(with: Data(JSONTextNormalizer.normalize(text).utf8)) as? [Any] else {
            throw BatchListError.invalidJSON
        }
        guard list.count <= 200 else { throw BatchListError.tooMany }
        return list.enumerated().map { index, value in
            guard let object = value as? [String: Any] else {
                return BatchSubscriptionEntry(id: index, name: "第 \(index + 1) 项", address: "", kind: nil, issue: "此项不是 JSON 对象")
            }
            let address = ((object["api"] as? String) ?? (object["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(string: address)
            let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? url?.host ?? "第 \(index + 1) 项"
            guard let url, url.host != nil, ["http", "https"].contains(url.scheme?.lowercased()) else {
                return BatchSubscriptionEntry(id: index, name: displayName, address: address, kind: nil, issue: "地址缺失或协议不支持（例如 cms://、爬虫或本地文件）")
            }
            let type = object["kind"] ?? object["type"]
            let kind: SubscriptionKind?
            if let type {
                switch String(describing: type).lowercased() {
                case "cms", "vod", "1": kind = .cms
                case "live", "m3u", "m3u8", "txt": kind = .live
                case "tvbox": kind = .tvbox
                default: kind = nil
                }
            } else {
                kind = ["m3u", "m3u8", "txt"].contains(url.pathExtension.lowercased()) ? .live : .cms
            }
            return BatchSubscriptionEntry(id: index, name: displayName, address: address, kind: kind,
                                          issue: kind == nil ? "不支持此订阅类型" : nil)
        }
    }

    static func downloadURL(_ text: String) throws -> URL {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil else { throw BatchListError.invalidURL }
        if components.host?.lowercased() == "github.com" {
            var parts = components.path.split(separator: "/").map(String.init)
            guard parts.count >= 5, parts[2] == "blob" else { throw BatchListError.invalidURL }
            parts.remove(at: 2)
            components.scheme = "https"
            components.host = "raw.githubusercontent.com"
            components.path = "/" + parts.joined(separator: "/")
            components.query = nil; components.fragment = nil
        }
        guard let url = components.url else { throw BatchListError.invalidURL }
        return url
    }

    func load(from text: String, client: any HTTPDataLoading = BoundedHTTPClient()) async throws -> [BatchSubscriptionEntry] {
        var request = URLRequest(url: try Self.downloadURL(text))
        request.timeoutInterval = 20
        let (data, _) = try await client.data(for: request, maximumBytes: Self.maximumBytes)
        return try decode(data)
    }
}

struct BatchImportOutcome: Identifiable, Sendable {
    enum Status: Equatable, Sendable { case added, skipped, failed }
    let id: Int
    let name: String
    let status: Status
    let message: String
}
