import AVKit
import SwiftUI

enum PlaybackEngine: String, CaseIterable, Identifiable {
    case avPlayer, vlc
    var id: String { rawValue }
    var label: String { self == .avPlayer ? "AVPlayer" : "VLC" }
}
struct PlaybackResource: Sendable {
    let url: URL
    var headers: [String: String] = [:]
}

struct NativePlayerView: View {
    let resource: PlaybackResource
    @Binding var controlsVisible: Bool
    var startPosition: Double = 0
    var preferredBufferDuration: Double = 0
    var onProgress: ((Double, Double) -> Void)? = nil
    var onEnded: (() -> Void)? = nil
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    var canPrevious = false
    var canNext = false
    var episodeStart: Double = 0
    var onSetEpisodeStart: ((Double) -> Void)? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.playerControlsInteraction) private var interaction
    @StateObject private var controller = PlaybackController()
    @AppStorage("playback.engine") private var engine: PlaybackEngine = .avPlayer
    @AppStorage("playback.volume") private var volume = 1.0
    @AppStorage("playback.rate") private var playbackRate = 1.0
    @State private var retryGeneration = 0
    @State private var requestedPosition: Double?
    @State private var gestureMode: GestureMode?
    @State private var gestureStart = 0.0
    @State private var seekPreview = 0.0
    @State private var gestureLabel: String?
    @State private var originalBrightness: CGFloat?

    private enum GestureMode { case seek, volume, brightness }
    private var screen: UIScreen {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.screen ?? UIScreen.main
    }

    var body: some View {
        ZStack {
            if engine == .vlc {
                VLCVideoSurface(player: controller.vlcPlayer, drawable: controller.vlcDrawable, onTap: toggleControls, onDoubleTap: togglePlayback, onPan: handlePan).ignoresSafeArea()
            } else {
                PlayerSurface(player: controller.player, onTap: toggleControls, onDoubleTap: togglePlayback, onPan: handlePan).ignoresSafeArea()
            }
            if controlsVisible {
                VStack { Spacer(); PlaybackTransportControls(controller: controller,
                    onPrevious: onPrevious, onNext: onNext, canPrevious: canPrevious, canNext: canNext, playbackRate: $playbackRate,
                    episodeStart: episodeStart, onSetEpisodeStart: onSetEpisodeStart) }
                    .transition(.opacity)
            }
            if controller.isPaused && controller.ready && controller.errorMessage == nil {
                HStack(spacing: 28) {
                    Button {
                        interaction(.activity)
                        Task { await controller.seek(to: controller.position - 10) }
                    } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 32)).frame(width: 60, height: 64)
                    }.disabled(!controller.canSeek).accessibilityLabel("后退 10 秒")
                    Button { togglePlayback() } label: {
                        Image(systemName: "play.fill").font(.system(size: 44)).frame(width: 76, height: 76)
                    }.accessibilityLabel("继续播放")
                    Button {
                        interaction(.activity)
                        Task { await controller.seek(to: controller.position + 10) }
                    } label: {
                        Image(systemName: "goforward.10").font(.system(size: 32)).frame(width: 60, height: 64)
                    }.disabled(!controller.canSeek).accessibilityLabel("快进 10 秒")
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
            }
            if controller.isBuffering && controller.errorMessage == nil && !controller.isPaused {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text(controller.ready ? "缓冲中…" : "正在连接媒体…")
                    if controller.bufferedAhead > 0 { Text("已缓冲约 \(Int(controller.bufferedAhead)) 秒").font(.caption) }
                }
                .foregroundStyle(.white).padding()
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
            if let error = controller.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center)
                    HStack(spacing: 24) {
                        Button(engine == .avPlayer ? "改用 VLC" : "改用 AVPlayer") {
                            engine = engine == .avPlayer ? .vlc : .avPlayer
                        }
                        Button("重试") { requestedPosition = controller.retryPosition; retryGeneration += 1 }
                        if controller.retryPosition > 0 {
                            Button("从头播放") { requestedPosition = 0; retryGeneration += 1 }
                        }
                    }.buttonStyle(.borderedProminent)
                }.foregroundStyle(.white).padding()
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            }
            if let gestureLabel {
                Text(gestureLabel).monospacedDigit().font(.headline)
                    .foregroundStyle(.white).padding()
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
        .task(id: "\(resource.url.absoluteString)|\(retryGeneration)") {
            if playbackRate > 2 { playbackRate = 2 }
            controller.setRate(playbackRate)
            controller.setForeground(scenePhase == .active)
            await controller.start(resource: resource, position: requestedPosition ?? startPosition,
                                   buffer: preferredBufferDuration, volume: volume,
                                   onProgress: onProgress, onEnded: onEnded, engine: engine)
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) {
            if let item = $0.object as? AVPlayerItem { controller.didEnd(item) }
        }
        .onChange(of: preferredBufferDuration) { _, value in controller.setBuffer(value) }
        .onChange(of: playbackRate) { _, value in controller.setRate(value) }
        .onChange(of: volume) { _, value in controller.setVolume(value) }
        .onChange(of: engine) { _, _ in
            controller.saveProgress()
            requestedPosition = controller.retryPosition
            retryGeneration += 1
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.saveProgress() }
            controller.setForeground(phase == .active)
        }
        .onDisappear {
            interaction(.ended)
            controller.stop()
            if let originalBrightness { screen.brightness = originalBrightness }
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.15)) { controlsVisible.toggle() }
    }

    private func togglePlayback() {
        interaction(.activity)
        guard controller.ready, controller.errorMessage == nil else { return }
        controller.togglePlay()
        controller.saveProgress()
    }

    private func handlePan(_ state: UIGestureRecognizer.State, _ delta: CGPoint, _ location: CGPoint, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if state == .began {
            interaction(.began)
            gestureMode = nil
            gestureLabel = nil
        }
        if state == .changed {
            if gestureMode == nil {
                guard max(abs(delta.x), abs(delta.y)) > 10 else { return }
                if abs(delta.x) > abs(delta.y) {
                    guard controller.canSeek else {
                        gestureLabel = "当前视频不支持进度跳转"
                        return
                    }
                    gestureMode = .seek
                    gestureStart = controller.position
                } else if location.x - delta.x >= size.width / 2 {
                    gestureMode = .volume
                    gestureStart = volume
                } else {
                    gestureMode = .brightness
                    if originalBrightness == nil { originalBrightness = screen.brightness }
                    gestureStart = Double(screen.brightness)
                }
            }
            switch gestureMode {
            case .seek:
                let seconds = Double(delta.x / size.width) * min(180, max(60, controller.duration * 0.1))
                seekPreview = PlaybackGestureMath.seekTarget(start: gestureStart, delta: seconds, duration: controller.duration)
                gestureLabel = "\(seconds >= 0 ? "快进" : "快退")  \(time(seekPreview)) / \(time(controller.duration))"
            case .volume:
                volume = PlaybackGestureMath.level(start: gestureStart, verticalFraction: Double(delta.y / size.height) * 1.5)
                gestureLabel = "视频音量 \(Int(volume * 100))%"
            case .brightness:
                let value = PlaybackGestureMath.level(start: gestureStart, verticalFraction: Double(delta.y / size.height) * 1.5)
                screen.brightness = value
                gestureLabel = "亮度 \(Int(value * 100))%"
            case nil: break
            }
        } else if state == .ended || state == .cancelled || state == .failed {
            interaction(.ended)
            if state == .ended, gestureMode == .seek {
                let target = seekPreview
                Task { await controller.seek(to: target) }
            }
            gestureMode = nil
            gestureLabel = nil
        }
    }

    private func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
