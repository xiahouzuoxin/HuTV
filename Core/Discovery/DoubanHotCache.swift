import Foundation

actor DoubanHotCache {
    struct Record: Codable, Sendable {
        let date: Date
        let data: Data
    }
    static let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DoubanDiscovery", isDirectory: true)
    static let shared = DoubanHotCache(directory: directory)
    private let directory: URL?
    init(directory: URL?) { self.directory = directory }

    private func file(_ key: String) -> URL? {
        let name = key.utf8.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name + ".json")
    }
    func read(_ key: String) -> Record? {
        guard let url = file(key),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
    func write(_ record: Record, key: String) {
        guard let directory, let url = file(key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: url, options: .atomic)
        } catch { /* Cache failures must not interrupt discovery. */ }
    }
}
