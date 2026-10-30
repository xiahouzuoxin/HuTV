import UIKit

@MainActor
final class ScreenAwakeManager {
    static let shared = ScreenAwakeManager()
    private var owners: Set<UUID> = []
    private var previous = false
    private let read: @MainActor () -> Bool
    private let write: @MainActor (Bool) -> Void

    init(read: @escaping @MainActor () -> Bool = { UIApplication.shared.isIdleTimerDisabled },
         write: @escaping @MainActor (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }) {
        self.read = read; self.write = write
    }
    func acquire() -> UUID {
        if owners.isEmpty { previous = read(); write(true) }
        let owner = UUID()
        owners.insert(owner)
        return owner
    }
    func refresh() { if !owners.isEmpty { write(true) } }
    func release(_ owner: UUID) {
        guard owners.remove(owner) != nil else { return }
        if owners.isEmpty { write(previous) }
    }
}
