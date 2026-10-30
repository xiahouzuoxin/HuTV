import MobileVLCKit
import SwiftUI

struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer?
    let drawable: UIView
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onPan: (UIGestureRecognizer.State, CGPoint, CGPoint, CGSize) -> Void
    func makeCoordinator() -> PlayerSurface.Coordinator { PlayerSurface.Coordinator(onPan: onPan, onTap: onTap, onDoubleTap: onDoubleTap) }
    func makeUIView(context: Context) -> UIView {
        let view = drawable
        view.backgroundColor = .black
        context.coordinator.installGestures(in: view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        if context.coordinator.vlcPlayer !== player { context.coordinator.vlcPlayer?.drawable = nil }
        context.coordinator.vlcPlayer = player
        player?.drawable = view
    }
    static func dismantleUIView(_ view: UIView, coordinator: PlayerSurface.Coordinator) {
        for gesture in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(gesture) }
        if let drawable = coordinator.vlcPlayer?.drawable as? UIView, drawable === view {
            coordinator.vlcPlayer?.drawable = nil
        }
    }
}

struct PlaybackTransportControls: View {
    @Environment(\.playerControlsInteraction) private var interaction
    @ObservedObject var controller: PlaybackController
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var canPrevious: Bool
    var canNext: Bool
    @Binding var playbackRate: Double
    @State private var editing = false
    @State private var preview = 0.0
    private var total: Double { controller.duration.isFinite && controller.duration > 0 ? controller.duration : 1 }
    private var current: Double { controller.position.isFinite ? min(max(0, controller.position), total) : 0 }
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                if controller.vlcPlayer == nil && controller.bufferedAhead > 0 {
                    Text("已缓冲至 " + time(min(total, current + controller.bufferedAhead)))
                } else if controller.isBuffering { Text("缓冲中…") }
                Spacer()
                Menu {
                    Button {
                        interaction(.activity)
                        controller.selectQuality(nil)
                    } label: {
                        if controller.selectedQualityID == nil { Label("自动", systemImage: "checkmark") }
                        else { Text("自动") }
                    }
                    ForEach(controller.qualityOptions) { option in
                        Button {
                            interaction(.activity)
                            controller.selectQuality(option.id)
                        } label: {
                            if controller.selectedQualityID == option.id { Label(option.menuLabel, systemImage: "checkmark") }
                            else { Text(option.menuLabel) }
                        }
                    }
                    if controller.detectingQuality {
                        Text("正在检测可用清晰度…")
                    } else if controller.qualityOptions.isEmpty {
                        Text("当前源或内核未提供可切换清晰度")
                    } else {
                        Text(controller.vlcPlayer == nil ? "按分辨率和码率上限选择，实际画质随网络调整" : "选择源提供的视频轨，自动恢复默认视频轨")
                    }
                } label: {
                    Text(controller.qualityLabel).padding(.horizontal, 8).frame(minHeight: 32)
                }
                .accessibilityLabel("清晰度，当前 \(controller.qualityLabel)")
                .simultaneousGesture(TapGesture().onEnded { interaction(.activity) })
                Menu {
                    Picker("播放速度", selection: $playbackRate) {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                            Text("\(rate.formatted())×").tag(rate)
                        }
                    }
                } label: {
                    Text("\(playbackRate.formatted())×").padding(.horizontal, 8).frame(minHeight: 32)
                }
                .accessibilityLabel("播放速度，当前 \(playbackRate.formatted()) 倍")
                .simultaneousGesture(TapGesture().onEnded { interaction(.activity) })
            }.font(.caption2).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 6) {
                transportButtons
                Text(time(editing ? preview : current)).font(.caption2).monospacedDigit().fixedSize()
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                        ForEach(Array(controller.bufferedRanges.enumerated()), id: \.offset) { _, range in
                            Capsule().fill(.white.opacity(0.55))
                                .frame(width: max(0, min(total, range.upperBound) - min(total, range.lowerBound)) / total * geometry.size.width, height: 4)
                                .offset(x: min(total, range.lowerBound) / total * geometry.size.width)
                        }
                        Capsule().fill(Color.accentColor)
                            .frame(width: (editing ? preview : current) / total * geometry.size.width, height: 4)
                        Slider(value: Binding(get: { editing ? preview : current }, set: { preview = $0 }),
                               in: 0...total, onEditingChanged: { active in
                            interaction(active ? .began : .ended)
                            if active { preview = current }
                            editing = active
                            if !active { Task { await controller.seek(to: preview) } }
                        })
                        .tint(.clear)
                        .disabled(!controller.canSeek)
                        .accessibilityLabel("播放进度")
                    }.frame(height: geometry.size.height)
                }.frame(minWidth: 60).frame(height: 32)
                Text(time(controller.duration)).font(.caption2).monospacedDigit().fixedSize()
            }

        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.65))
        .onChange(of: playbackRate) { interaction(.activity) }
    }
    private var transportButtons: some View {
        HStack(spacing: 0) {
            if onPrevious != nil || onNext != nil {
                Button { interaction(.activity); onPrevious?() } label: {
                    Image(systemName: "backward.end.fill").font(.title3).frame(width: 44, height: 44)
                }.disabled(!canPrevious).opacity(canPrevious ? 1 : 0.3).accessibilityLabel("上一集")
            }
            Button { interaction(.activity); controller.togglePlay() } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2).frame(width: 44, height: 44)
            }.accessibilityLabel(controller.isPlaying ? "暂停" : "播放")
            if onPrevious != nil || onNext != nil {
                Button { interaction(.activity); onNext?() } label: {
                    Image(systemName: "forward.end.fill").font(.title3).frame(width: 44, height: 44)
                }.disabled(!canNext).opacity(canNext ? 1 : 0.3).accessibilityLabel("下一集")
            }

        }
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
