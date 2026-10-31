import Foundation
import Observation

enum WatchTarget: Codable, Sendable {
    case vod(item: MediaItem, source: TVBoxSite, episode: MediaEpisode)
    case live(channel: LiveChannel, source: TVBoxLive)

    var id: String {
        switch self {
        case .vod(let item, _, _): "vod|\(item.sourceID)|\(item.detailID)"
        case .live(let channel, let source): "live|\(source.url)|\(channel.id)"
        }
    }
    var title: String {
        switch self {
        case .vod(let item, _, _): item.title
        case .live(let channel, _): channel.name
        }
    }
    var subtitle: String {
        switch self {
        case .vod(_, let source, let episode): "\(source.name) · \(episode.line) · \(episode.name)"
        case .live(_, let source): "直播 · \(source.name)"
        }
    }
    var posterURL: URL? {
        switch self {
        case .vod(let item, _, _): item.posterURL
        case .live(let channel, _): channel.logoURL
        }
    }
}

struct WatchRecord: Codable, Identifiable, Sendable {
    var target: WatchTarget
    var position: Double
    var duration: Double
    var watchedAt: Date
    var id: String { target.id }
    var resumePosition: Double {
        duration > 0 && duration - position < 15 ? 0 : position
    }
}

@MainActor @Observable
final class HistoryStore {
    private(set) var searches: [String] = []
    private(set) var records: [WatchRecord] = []
    private(set) var persistenceError: String?
    private(set) var episodeStarts: [String: Double] = [:]
    private let storageURL: URL

    private struct Snapshot: Codable {
        var searches: [String]
        var records: [WatchRecord]
        var episodeStarts: [String: Double]?
    }

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory,
            in: .userDomainMask).first!.appendingPathComponent("TVBoxiOS/history.json")
        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            do {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.storageURL))
                searches = snapshot.searches
                records = snapshot.records
                episodeStarts = snapshot.episodeStarts ?? [:]
            } catch { persistenceError = "读取历史失败：\(error.localizedDescription)" }
        }
    }

    func addSearch(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        searches.removeAll { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
        searches.insert(value, at: 0)
        searches = Array(searches.prefix(30))
        save()
    }
    func removeSearch(_ value: String) { searches.removeAll { $0 == value }; save() }
    func clearSearches() { searches = []; save() }
    func record(_ target: WatchTarget, position: Double, duration: Double) {
        guard position.isFinite, position >= 0 else { return }
        records.removeAll { $0.id == target.id }
        records.insert(WatchRecord(target: target, position: position,
                                  duration: duration.isFinite && duration > 0 ? duration : 0,
                                  watchedAt: .now), at: 0)
        records = Array(records.prefix(200))
        save()
    }
    func resumeRecord(sourceID: String, detailID: String, episode: MediaEpisode? = nil) -> WatchRecord? {
        records.first { record in
            guard case .vod(let item, _, let saved) = record.target,
                  item.sourceID == sourceID, item.detailID == detailID else { return false }
            return episode.map { $0.line == saved.line && $0.name == saved.name } ?? true
        }
    }

    private func seriesKey(_ item: MediaItem) -> String {
        // JSON array encoding avoids separator collisions in source/detail identifiers.
        String(data: try! JSONEncoder().encode([item.sourceID, item.detailID]), encoding: .utf8)!
    }
    func episodeStart(for item: MediaItem) -> Double { episodeStarts[seriesKey(item)] ?? 0 }
    func setEpisodeStart(_ seconds: Double, for item: MediaItem) {
        guard seconds.isFinite, seconds >= 0 else { return }
        if seconds < 1 { episodeStarts.removeValue(forKey: seriesKey(item)) }
        else { episodeStarts[seriesKey(item)] = min(seconds.rounded(.down), 86_400) }
        save()
    }

    func removeRecord(_ id: String) { records.removeAll { $0.id == id }; save() }
    func clearRecords() { records = []; save() }
    func clearError() { persistenceError = nil }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(Snapshot(searches: searches, records: records, episodeStarts: episodeStarts))
                .write(to: storageURL, options: .atomic)
        } catch { persistenceError = "保存历史失败：\(error.localizedDescription)" }
    }
}
