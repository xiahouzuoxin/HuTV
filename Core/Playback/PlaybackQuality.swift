import Foundation

struct PlaybackQualityOption: Identifiable, Equatable, Sendable {
    let width: Int
    let height: Int
    let peakBitRate: Double
    var videoTrackIndex: Int32? = nil
    var id: String { videoTrackIndex.map { "track:\($0)" } ?? "limit:\(width)x\(height)" }
    var label: String { "\(min(width, height))p" }
    var menuLabel: String { videoTrackIndex == nil ? "最高 \(label)" : "\(label)（\(width)×\(height)）" }

    /// Audio-only, missing-size and single-resolution variants are not quality choices.
    static func choices(_ options: [PlaybackQualityOption]) -> [PlaybackQualityOption] {
        let valid = options.filter { $0.width > 0 && $0.height > 0 && $0.width < 100_000 && $0.height < 100_000 && ($0.videoTrackIndex ?? 0) >= 0 }
        var unique: [String: PlaybackQualityOption] = [:]
        for option in valid {
            let key = "\(option.width)x\(option.height)"
            if let old = unique[key], old.peakBitRate >= option.peakBitRate { continue }
            unique[key] = option
        }
        guard unique.count > 1 else { return [] }
        return unique.values.sorted {
            let left = Int64($0.width) * Int64($0.height), right = Int64($1.width) * Int64($1.height)
            return left == right ? $0.id < $1.id : left < right
        }
    }
}
