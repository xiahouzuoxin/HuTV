import Foundation

/// A remote JSON list and the subscriptions it owns. User choices survive refreshes.
struct SubscriptionFeed: Codable, Identifiable, Sendable {
    var id = UUID()
    var url: URL
    var enabled = true
    var updatedAt: Date?
    var lastError: String?
    var members: [String: UUID] = [:]
    var excluded: Set<String> = []

    static func key(_ entry: BatchSubscriptionEntry) -> String {
        // Same kind/name is treated as the same feed entry when its URL changes.
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(data: try! JSONEncoder().encode([entry.kind?.rawValue ?? "", name]), encoding: .utf8)!
    }
}
