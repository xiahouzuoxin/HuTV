import Foundation

/// One queue orders periodic writes, explicit saves and deletion barriers.
final class HistoryWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "HuTV.history", qos: .utility)
    private let url: URL
    init(url: URL) { self.url = url }
    func write<T: Encodable & Sendable>(_ snapshot: T) throws {
        try queue.sync { try persist(snapshot) }
    }
    func enqueue<T: Encodable & Sendable>(_ snapshot: T, completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            do { try self.persist(snapshot); completion(nil) }
            catch { completion(error.localizedDescription) }
        }
    }
    func drain() { queue.sync {} }
    private func persist<T: Encodable>(_ snapshot: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
