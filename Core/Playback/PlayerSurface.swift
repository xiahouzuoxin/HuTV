import AVKit
import MobileVLCKit
import SwiftUI

/// Pan recognition excludes transport controls and does not swallow taps.
struct PlayerSurface: UIViewControllerRepresentable {
    let player: AVPlayer?
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onPan: (UIGestureRecognizer.State, CGPoint, CGPoint, CGSize) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPan: onPan, onTap: onTap, onDoubleTap: onDoubleTap) }
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        context.coordinator.installGestures(in: controller.view)
        return controller
    }
    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        context.coordinator.onPan = onPan
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
    }
    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var vlcPlayer: VLCMediaPlayer?
        var onPan: (UIGestureRecognizer.State, CGPoint, CGPoint, CGSize) -> Void
        var onTap: () -> Void
        var onDoubleTap: () -> Void
        init(onPan: @escaping (UIGestureRecognizer.State, CGPoint, CGPoint, CGSize) -> Void,
             onTap: @escaping () -> Void, onDoubleTap: @escaping () -> Void) {
            self.onPan = onPan; self.onTap = onTap; self.onDoubleTap = onDoubleTap
        }
        func installGestures(in view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            let single = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            single.require(toFail: pan)
            double.require(toFail: pan)
            for gesture in [pan, single, double] {
                gesture.delegate = self
                gesture.cancelsTouchesInView = false
                view.addGestureRecognizer(gesture)
            }
        }
        @objc func singleTap(_ gesture: UITapGestureRecognizer) { onTap() }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) { onDoubleTap() }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            onPan(gesture.state, gesture.translation(in: view), gesture.location(in: view), view.bounds.size)
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = gesture.view else { return false }
            let point = touch.location(in: view)
            guard point.y > 72, point.y < view.bounds.height - 88 else { return false }
            var target = touch.view
            while let current = target, current !== view {
                if current is UIControl { return false }
                target = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
