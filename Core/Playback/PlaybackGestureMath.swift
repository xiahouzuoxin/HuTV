import Foundation

enum PlaybackGestureMath {
    static func seekTarget(start: Double, delta: Double, duration: Double) -> Double {
        guard start.isFinite, delta.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(max(0, start + delta), max(0, duration - 0.25))
    }
    static func level(start: Double, verticalFraction: Double) -> Double {
        min(1, max(0, start - verticalFraction))
    }
}
