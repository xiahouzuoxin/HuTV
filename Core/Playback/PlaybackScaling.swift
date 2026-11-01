import AVFoundation
import SwiftUI

enum PlaybackScaling: String, CaseIterable, Identifiable {
    case fit, crop, stretch, widescreen, standard
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fit: "适应屏幕"
        case .crop: "裁剪铺满"
        case .stretch: "拉伸铺满"
        case .widescreen: "16:9"
        case .standard: "4:3"
        }
    }
    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: .resizeAspect
        case .crop: .resizeAspectFill
        default: .resize
        }
    }
    func frame(in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let ratio: CGFloat
        switch self {
        case .widescreen: ratio = 16 / 9
        case .standard: ratio = 4 / 3
        default: return size
        }
        let width = min(size.width, size.height * ratio)
        return CGSize(width: width, height: width / ratio)
    }
}
