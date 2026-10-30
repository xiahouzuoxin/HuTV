import Foundation

enum SubscriptionError: LocalizedError {
    case invalidResponse
    case tooLarge
    case noSources

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "订阅服务器返回异常"
        case .tooLarge: "订阅文件超过 5 MB"
        case .noSources: "配置中没有找到有效的点播源或直播列表"
        }
    }
}

struct SubscriptionLoader {
    let client: any HTTPDataLoading

    init(client: any HTTPDataLoading = BoundedHTTPClient()) { self.client = client }

    private let maxBytes = 5 * 1024 * 1024

    func load(from url: URL, kind: SubscriptionKind = .tvbox, name: String? = nil,
              replacing old: Warehouse? = nil) async throws -> Warehouse {
        let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? old?.name ?? url.host ?? kind.label
        if kind == .cms {
            let site = TVBoxSite(key: "cms", name: title, api: url.absoluteString)
            // Validate the response schema before saving an endpoint as a usable source.
            _ = try await StandardCMSProvider(id: site.key, source: site, client: client).categories()
            return Warehouse(id: old?.id ?? UUID(), name: title, kind: kind,
                             configURL: url, config: TVBoxConfig(sites: [site]),
                             importedAt: old?.importedAt ?? .now, updatedAt: .now)
        }
        if kind == .live {
            _ = try await LivePlaylistLoader(client: client).load(from: url.absoluteString)
            let live = TVBoxLive(name: title, url: url.absoluteString)
            return Warehouse(id: old?.id ?? UUID(), name: title, kind: kind,
                             configURL: url, config: TVBoxConfig(lives: [live]),
                             importedAt: old?.importedAt ?? .now, updatedAt: .now)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = old?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified = old?.lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await client.data(
                for: request, maximumBytes: maxBytes, additionalValidStatusCodes: [304]
            )
        } catch HTTPClientError.responseTooLarge {
            throw SubscriptionError.tooLarge
        } catch HTTPClientError.invalidResponse {
            throw SubscriptionError.invalidResponse
        }

        if response.statusCode == 304, var old {
            old.updatedAt = .now
            return old
        }

        let config = try TVBoxConfigDecoder().decode(data)
        guard !config.sites.isEmpty || !config.lives.isEmpty else { throw SubscriptionError.noSources }

        return Warehouse(
            id: old?.id ?? UUID(),
            name: title,
            kind: kind,
            configURL: url,
            config: config,
            importedAt: old?.importedAt ?? .now,
            updatedAt: .now,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }

}
