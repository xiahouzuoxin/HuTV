import SwiftUI

enum PlayerPageKind {
    case onDemand, live
}

/// Shared fullscreen shell. Playback-specific state stays in the owning session.
struct PlayerPage<Content: View>: View {
    let title: String
    let subtitle: String
    let programInfo: String?
    let kind: PlayerPageKind
    let onSwitchSource: () -> Void
    private let content: (Binding<Bool>) -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var controlsVisible = false

    init(title: String, subtitle: String, programInfo: String? = nil, kind: PlayerPageKind,
         onSwitchSource: @escaping () -> Void,
         @ViewBuilder content: @escaping (Binding<Bool>) -> Content) {
        self.title = title; self.subtitle = subtitle; self.programInfo = programInfo
        self.kind = kind; self.onSwitchSource = onSwitchSource; self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            content($controlsVisible)
            if controlsVisible {
                HStack(spacing: 16) {
                    Button { dismiss() } label: {
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
            }
        }
        .statusBarHidden(!controlsVisible)
        .persistentSystemOverlays(controlsVisible ? .automatic : .hidden)
    }
}

private struct PlayerSettingsMenu: View {
    let kind: PlayerPageKind
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
    }
}
