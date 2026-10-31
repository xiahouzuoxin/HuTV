import SwiftUI
import UIKit

/// A real UIControl keeps taps out of the video surface's gesture recognizers,
/// including on iPadOS 17. A long press cancels the corresponding button tap.
struct EpisodeStartControl: UIViewRepresentable {
    let seconds: Double
    let canRecord: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    func makeUIView(context: Context) -> EpisodeStartButton { EpisodeStartButton(frame: .zero) }
    func updateUIView(_ button: EpisodeStartButton, context: Context) {
        button.onRecord = onRecord
        button.onClear = onClear
        button.canRecord = canRecord
        let time = String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
        button.setTitle(seconds > 0 ? time : "起播", for: .normal)
        button.alpha = canRecord || seconds > 0 ? 1 : 0.4
        button.accessibilityLabel = "本剧起播位置，当前 \(time)"
        button.invalidateIntrinsicContentSize()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EpisodeStartButton, context: Context) -> CGSize? {
        CGSize(width: max(44, uiView.intrinsicContentSize.width + 12), height: 44)
    }
}

final class EpisodeStartButton: UIButton {
    var onRecord: () -> Void = {}
    var onClear: () -> Void = {}
    var canRecord = false
    private var consumedLongPress = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel?.font = .preferredFont(forTextStyle: .caption2)
        titleLabel?.adjustsFontForContentSizeCategory = true
        setTitleColor(.white.withAlphaComponent(0.8), for: .normal)
        setTitleColor(.white.withAlphaComponent(0.4), for: .highlighted)
        addTarget(self, action: #selector(touchBegan), for: .touchDown)
        addTarget(self, action: #selector(recordPosition), for: .touchUpInside)
        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.6
        press.cancelsTouchesInView = true
        addGestureRecognizer(press)
        accessibilityHint = "点击记录当前进度，长按直接清除"
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "清除起播位置", target: self,
                                                                  selector: #selector(accessibilityClear))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func touchBegan() { consumedLongPress = false }
    @objc private func recordPosition() {
        guard canRecord, !consumedLongPress else { return }
        onRecord()
    }
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { clearFromLongPress() }
    }
    func clearFromLongPress() { consumedLongPress = true; onClear() }
    @objc private func accessibilityClear() -> Bool { onClear(); return true }
    override func accessibilityActivate() -> Bool {
        guard canRecord else { return false }
        onRecord()
        return true
    }
}
