import MobileVLCKit
import SwiftUI

struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer?
    let drawable: UIView
    var scaling: PlaybackScaling = .fit
    var viewport: CGSize = .zero
    var controlsVisible = false
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
        context.coordinator.controlsVisible = controlsVisible
        context.coordinator.onPan = onPan
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        if context.coordinator.vlcPlayer !== player {
            context.coordinator.vlcPlayer?.drawable = nil
            context.coordinator.scalingSignature = ""
        }
        context.coordinator.vlcPlayer = player
        if (player?.drawable as? UIView) !== view { player?.drawable = view }
        let signature = "\(scaling.rawValue)|\(viewport)|\(player?.hasVideoOut ?? false)"
        if let player, viewport.width > 0, viewport.height > 0, context.coordinator.scalingSignature != signature {
            context.coordinator.scalingSignature = signature
            player.scaleFactor = 0
            player.videoAspectRatio = nil
            player.videoCropGeometry = nil
            let ratio = "\(Int(viewport.width.rounded())):\(Int(viewport.height.rounded()))"
            if scaling == .crop {
                ratio.withCString { player.videoCropGeometry = UnsafeMutablePointer(mutating: $0) }
            } else if scaling != .fit {
                ratio.withCString { player.videoAspectRatio = UnsafeMutablePointer(mutating: $0) }
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: PlayerSurface.Coordinator) {
        for gesture in view.gestureRecognizers ?? [] { view.removeGestureRecognizer(gesture) }
        if let drawable = coordinator.vlcPlayer?.drawable as? UIView, drawable === view {
            coordinator.vlcPlayer?.drawable = nil
        }
    }
}

struct PlaybackTransportControls: View {
    @AppStorage("playback.scaling") private var scaling: PlaybackScaling = .fit
    @Environment(\.playerControlsInteraction) private var interaction
    @Environment(\.playerFullscreen) private var fullscreen
    @Environment(\.playerToggleFullscreen) private var toggleFullscreen
    @ObservedObject var controller: PlaybackController
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var canPrevious: Bool
    var canNext: Bool
    @Binding var playbackRate: Double
    var episodeStart: Double = 0
    var onSetEpisodeStart: ((Double) -> Void)? = nil
    @State private var scrub = PlaybackScrubState()
    private var total: Double { controller.duration.isFinite && controller.duration > 0 ? controller.duration : 1 }
    private var current: Double { controller.position.isFinite ? min(max(0, controller.position), total) : 0 }
    private var displayedPosition: Double { scrub.displayedPosition(current: current, duration: total) }
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                if controller.vlcPlayer == nil && controller.bufferedAhead > 0 {
                    Text("已缓冲至 " + time(min(total, current + controller.bufferedAhead))).lineLimit(1).minimumScaleFactor(0.7)
                } else if controller.isBuffering { Text("缓冲中…") }
                Spacer()
                if let onSetEpisodeStart {
                    EpisodeStartControl(seconds: episodeStart, canRecord: controller.canSeek,
                        onRecord: {
                            interaction(.activity)
                            onSetEpisodeStart(controller.position)
                        }, onClear: {
                            interaction(.activity)
                            onSetEpisodeStart(0)
                        })
                }
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
                Menu {
                    Picker("画面缩放", selection: $scaling) {
                        ForEach(PlaybackScaling.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Image(systemName: "aspectratio").frame(width: 36, height: 32)
                }
                .accessibilityLabel("画面缩放，当前 \(scaling.label)")
                .simultaneousGesture(TapGesture().onEnded { interaction(.activity) })
            }.font(.caption2).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 6) {
                transportButtons
                Text(time(displayedPosition)).font(.caption2).monospacedDigit().fixedSize()
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                        ForEach(Array(controller.bufferedRanges.enumerated()), id: \.offset) { _, range in
                            Capsule().fill(.white.opacity(0.55))
                                .frame(width: max(0, min(total, range.upperBound) - min(total, range.lowerBound)) / total * geometry.size.width, height: 4)
                                .offset(x: min(total, range.lowerBound) / total * geometry.size.width)
                        }
                        Capsule().fill(Color.accentColor)
                            .frame(width: (displayedPosition) / total * geometry.size.width, height: 4)
                        Slider(value: Binding(get: { displayedPosition }, set: { scrub.update(to: $0) }),
                               in: 0...total, onEditingChanged: { active in
                            if active {
                                scrub.begin(at: current)
                                interaction(.began)
                            } else if let request = scrub.commit() {
                                Task {
                                    await controller.seek(to: request.position)
                                    if scrub.complete(request.id) { interaction(.ended) }
                                }
                            }
                        })
                        .tint(.clear)
                        .disabled(!controller.canSeek)
                        .accessibilityLabel("播放进度")
                    }.frame(height: geometry.size.height)
                }.frame(minWidth: 60).frame(height: 32)
                    .transaction { $0.animation = nil }
                Text(time(controller.duration)).font(.caption2).monospacedDigit().fixedSize()
                Button {
                    interaction(.activity)
                    toggleFullscreen()
                } label: {
                    Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                }.accessibilityLabel(fullscreen ? "退出全屏" : "进入全屏")
            }

        }
        .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.65))
        .onChange(of: playbackRate) { interaction(.activity) }
        .onDisappear { scrub.reset(); interaction(.ended) }
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
