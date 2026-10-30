import CoreFoundation
import Foundation

enum LivePlaylistError: LocalizedError {
    case invalidURL, invalidResponse, emptyPlaylist, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidURL: "直播源 URL 无效"
        case .invalidResponse: "直播源服务器返回异常"
        case .emptyPlaylist: "没有解析到可播放的频道"
        case .tooLarge: "直播列表超过 10 MB"
        }
    }
}

struct LivePlaylistLoader {
    let client: any HTTPDataLoading

    init(client: any HTTPDataLoading = BoundedHTTPClient()) { self.client = client }

    private let maxBytes = 10 * 1024 * 1024

    func load(from text: String) async throws -> [LiveChannel] {
        guard let url = URL(string: text) else { throw LivePlaylistError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let data: Data
        do {
            (data, _) = try await client.data(for: request, maximumBytes: maxBytes)
        } catch HTTPClientError.responseTooLarge {
            throw LivePlaylistError.tooLarge
        } catch HTTPClientError.invalidResponse {
            throw LivePlaylistError.invalidResponse
        }

        let content = decodeText(data)
        let channels = content.contains("#EXTM3U") ? parseM3U(content) : parseTVBoxText(content)
        guard !channels.isEmpty else { throw LivePlaylistError.emptyPlaylist }
        return channels
    }

    func load(from source: TVBoxLive) async throws -> [LiveChannel] {
        let channels = try await load(from: source.url)
        guard let template = source.logo, !template.isEmpty else { return channels }
        return channels.map { channel in
            guard channel.logoURL == nil else { return channel }
            let value = template.replacingOccurrences(of: "{name}", with: channel.name)
            return LiveChannel(id: channel.id, name: channel.name, group: channel.group,
                               streams: channel.streams, logoURL: URL(string: value))
        }
    }

    func parseM3U(_ content: String) -> [LiveChannel] {
        var channels: [LiveChannel] = []
        var metadata: (name: String, group: String, logo: URL?, headers: [String: String])?

        for line in normalizedLines(content) {
            if line.hasPrefix("#EXTINF:") {
                metadata = (
                    line.split(separator: ",", maxSplits: 1).last.map(String.init) ?? "未命名频道",
                    attribute("group-title", in: line) ?? "其他",
                    attribute("tvg-logo", in: line).flatMap(URL.init(string:)),
                    [:]
                )
            } else if line.hasPrefix("#EXTVLCOPT:"), metadata != nil {
                let parts = line.dropFirst("#EXTVLCOPT:".count).split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let mapping = ["http-user-agent": "User-Agent", "http-referrer": "Referer",
                                   "http-referer": "Referer", "http-cookie": "Cookie"]
                    if let header = mapping[parts[0].lowercased()] { metadata?.headers[header] = parts[1] }
                }
            } else if line.hasPrefix("#EXTHTTP:"), metadata != nil, let start = line.firstIndex(of: "{") {
                if let values = try? JSONDecoder().decode([String: String].self, from: Data(line[start...].utf8)) {
                    metadata?.headers.merge(values) { _, new in new }
                }
            } else if !line.hasPrefix("#"), let pending = metadata,
                      let stream = parseStream(line, fallbackHeaders: pending.headers) {
                channels.append(makeChannel(name: pending.name, group: pending.group,
                                            streams: [stream], logo: pending.logo))
                metadata = nil
            }
        }
        return mergeDuplicateChannels(channels)
    }

    func parseTVBoxText(_ content: String) -> [LiveChannel] {
        var group = "其他"
        var channels: [LiveChannel] = []
        for line in normalizedLines(content) where !line.hasPrefix("//") {
            let parts = line.split(separator: ",", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if value == "#genre#" { group = name; continue }
            let streams = splitStreamEntries(value).compactMap { parseStream($0) }
            if !streams.isEmpty {
                channels.append(makeChannel(name: name, group: group, streams: streams, logo: nil))
            }
        }
        return mergeDuplicateChannels(channels)
    }

    private func makeChannel(name: String, group: String, streams: [LiveStream], logo: URL?) -> LiveChannel {
        LiveChannel(id: "\(group)|\(name)", name: name, group: group, streams: streams, logoURL: logo)
    }

    private func mergeDuplicateChannels(_ channels: [LiveChannel]) -> [LiveChannel] {
        var order: [String] = []
        var values: [String: LiveChannel] = [:]
        for channel in channels {
            if let old = values[channel.id] {
                var seen = Set<LiveStream>()
                let streams = (old.streams + channel.streams).filter { seen.insert($0).inserted }
                values[channel.id] = LiveChannel(id: old.id, name: old.name, group: old.group,
                                                 streams: streams, logoURL: old.logoURL ?? channel.logoURL)
            } else {
                order.append(channel.id); values[channel.id] = channel
            }
        }
        return order.compactMap { values[$0] }
    }

    private func parseStream(_ text: String, fallbackHeaders: [String: String] = [:]) -> LiveStream? {
        let headerParts = text.trimmingCharacters(in: .whitespaces).split(separator: "|", maxSplits: 1).map(String.init)
        var address = headerParts[0]
        var headers = fallbackHeaders
        if headerParts.count == 2 {
            for pair in headerParts[1].split(separator: "&") {
                let values = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard values.count == 2 else { continue }
                headers[values[0].removingPercentEncoding ?? values[0]] = values[1].removingPercentEncoding ?? values[1]
            }
        }
        var lineName: String?
        if let marker = address.lastIndex(of: "$"), marker != address.startIndex {
            let candidate = String(address[..<marker])
            let suffix = String(address[address.index(after: marker)...])
            if URL(string: candidate)?.scheme != nil, !suffix.isEmpty { address = candidate; lineName = suffix }
        }
        guard let url = URL(string: address),
              ["http", "https", "rtsp", "rtmp"].contains(url.scheme?.lowercased()) else { return nil }
        return LiveStream(url: url, name: lineName, headers: headers)
    }

    private func splitStreamEntries(_ value: String) -> [String] {
        var result: [String] = []
        var remaining = value[...]
        let markers = ["#http://", "#https://", "#rtmp://", "#rtsp://"]
        while let match = markers.compactMap({ remaining.range(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound }) {
            result.append(String(remaining[..<match.lowerBound]))
            remaining = remaining[remaining.index(after: match.lowerBound)...]
        }
        result.append(String(remaining))
        return result
    }

    private func normalizedLines(_ content: String) -> [String] {
        content.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func attribute(_ name: String, in line: String) -> String? {
        let marker = "\(name)=\""
        guard let start = line.range(of: marker)?.upperBound,
              let end = line[start...].firstIndex(of: "\"") else { return nil }
        return String(line[start..<end])
    }

    private func decodeText(_ data: Data) -> String {
        if let value = String(data: data, encoding: .utf8) { return value }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: encoding) ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }
}
