import Foundation

/// Holds the user's preview until the matching seek finishes.
struct PlaybackScrubState {
    private(set) var isDragging = false
    private(set) var preview: Double?
    private var revision = UUID()

    func displayedPosition(current: Double, duration: Double) -> Double {
        let value = preview ?? current
        return min(max(0, value.isFinite ? value : 0), max(0, duration.isFinite ? duration : 0))
    }

    mutating func begin(at current: Double) {
        guard !isDragging else { return }
        revision = UUID()
        if preview == nil { preview = current }
        isDragging = true
    }

    mutating func update(to value: Double) {
        // Slider may write its binding before delivering onEditingChanged(true).
        if !isDragging { begin(at: value) }
        preview = value
    }

    mutating func commit() -> (id: UUID, position: Double)? {
        guard isDragging, let preview else { return nil }
        isDragging = false
        return (revision, preview)
    }

    @discardableResult mutating func complete(_ id: UUID) -> Bool {
        guard revision == id, !isDragging else { return false }
        preview = nil
        revision = UUID()
        return true
    }

    mutating func reset() {
        revision = UUID()
        isDragging = false
        preview = nil
    }
}
