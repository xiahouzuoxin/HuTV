import SwiftUI

enum PlayerPageKind {
    case onDemand, live
}

/// Shared player shell. Playback-specific state stays in the owning session.
struct PlayerPage<Content: View>: View {
    let title: String
    let subtitle: String
    let programInfo: String?
    let kind: PlayerPageKind
    let isChoosingSource: Bool
    let onSwitchSource: () -> Void
    private let fullscreen: Binding<Bool>?
    private let onClose: (() -> Void)?
    private let onExitFullscreen: @MainActor () -> Void
    private var isFullscreen: Bool { fullscreen?.wrappedValue ?? true }
    private let content: (Binding<Bool>) -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = false
    @State private var interacting = false
    @GestureState private var headerTouch = false
    @State private var activityRevision = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    init(title: String, subtitle: String, programInfo: String? = nil, kind: PlayerPageKind, isChoosingSource: Bool = false,
         onSwitchSource: @escaping () -> Void, fullscreen: Binding<Bool>? = nil, onClose: (() -> Void)? = nil,
         onExitFullscreen: @escaping @MainActor () -> Void = PlaybackOrientation.returnToPortrait,
         @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        self.fullscreen = fullscreen; self.onClose = onClose
        self.onExitFullscreen = onExitFullscreen
        self.title = title; self.subtitle = subtitle; self.programInfo = programInfo
        self.kind = kind; self.isChoosingSource = isChoosingSource; self.onSwitchSource = onSwitchSource; self.content = content
    }

    var body: some View {
        player
        .background(isFullscreen ? Color.black : Color(.systemBackground))
        .environment(\.playerFullscreen, isFullscreen)
        .environment(\.playerToggleFullscreen, {
            if isFullscreen { onExitFullscreen() }
            if let fullscreen { fullscreen.wrappedValue.toggle() }
            else { close() }
            controlsVisible = true
            registerInteraction(.activity)
        })
        .statusBarHidden(isFullscreen && !controlsVisible)
        .persistentSystemOverlays(isFullscreen && !controlsVisible ? .hidden : .automatic)
    }

    private var player: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            content($controlsVisible)
            if controlsVisible {
                HStack(spacing: 16) {
                    Button { close() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title)
                    }
                    .accessibilityLabel("关闭播放器")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline).lineLimit(1)
                        Text(subtitle).font(.caption).lineLimit(1)
                        if let programInfo {
                            Label(programInfo, systemImage: "clock").font(.caption2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(action: onSwitchSource) {
                        Label("切换源", systemImage: "arrow.triangle.swap").font(.subheadline)
                    }
                    PlayerSettingsMenu(kind: kind)
                }
                .foregroundStyle(.white).padding()
                .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))
                .transition(.opacity)
                .simultaneousGesture(DragGesture(minimumDistance: 0)
                    .updating($headerTouch) { _, touching, _ in touching = true })
            }
        }
        .onChange(of: headerTouch) { _, active in registerInteraction(active ? .began : .ended) }
        .environment(\.playerControlsInteraction, registerInteraction)
        .task(id: "\(controlsVisible)|\(interacting)|\(activityRevision)|\(isChoosingSource)|\(scenePhase)|\(voiceOver)") {
            guard controlsVisible, !interacting, !isChoosingSource, scenePhase == .active, !voiceOver else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { controlsVisible = false }
        }

    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private func registerInteraction(_ event: PlayerControlsInteraction) {
        switch event {
        case .activity: break
        case .began: interacting = true
        case .ended: interacting = false
        }
        activityRevision = UUID()
    }
}

private struct PlayerSettingsMenu: View {
    let kind: PlayerPageKind
    @Environment(\.playerControlsInteraction) private var interaction
    @AppStorage("playback.engine") private var engine: PlaybackEngine = .avPlayer
    @AppStorage("playback.autoAdvance") private var autoAdvance = true
    @AppStorage("playback.forwardBufferSeconds") private var bufferSeconds = 30.0

    var body: some View {
        Menu {
            Picker("播放内核", selection: $engine) {
                ForEach(PlaybackEngine.allCases) { Text($0.label).tag($0) }
            }
            if kind == .onDemand {
                Toggle("自动连播", isOn: $autoAdvance)
                Picker("点播预缓冲", selection: $bufferSeconds) {
                    Text("系统自动").tag(0.0)
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(engine.label).font(.caption)
                Image(systemName: "slider.horizontal.3").font(.title2)
            }
        }
        .accessibilityLabel("播放设置，当前内核 \(engine.label)")
        .onChange(of: engine) { interaction(.activity) }
        .onChange(of: autoAdvance) { interaction(.activity) }
        .onChange(of: bufferSeconds) { interaction(.activity) }
    }
}
