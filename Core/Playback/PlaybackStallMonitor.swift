import Foundation

struct PlaybackStallMonitor {
    var timeout: TimeInterval = 30
    private var lastPosition: Double?
    private var lastAdvance: TimeInterval?
    mutating func stalled(position: Double, now: TimeInterval, monitoring: Bool) -> Bool {
        guard monitoring, position.isFinite else { lastPosition = nil; lastAdvance = nil; return false }
        if lastPosition == nil || abs(position - lastPosition!) >= 0.1 {
            lastPosition = position; lastAdvance = now
        }
        guard let lastAdvance else { return false }
        return now - lastAdvance >= timeout
    }
}
