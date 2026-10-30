import AVKit
import SwiftUI

struct LivePlayerView: View {
    @Environment(HistoryStore.self) private var history
    let channel: LiveChannel
    let source: TVBoxLive
    @State private var selectedLine = 0
    @State private var activeChannel: LiveChannel?
    @State private var activeSource: TVBoxLive?
    @State private var playbackRevision = UUID()
    @State private var showingSourcePicker = false
    @State private var recorded = false
    @State private var programs: [EPGProgram] = []

    var body: some View {
        let channel = activeChannel ?? self.channel
        let source = activeSource ?? self.source
        let run = playbackRevision
        let programInfo = programs.first.map { "\($0.start)–\($0.end)  \($0.title)" }
        PlayerPage(title: channel.name, subtitle: source.name, programInfo: programInfo,
                   kind: .live, onSwitchSource: { showingSourcePicker = true }) { controls in

            if channel.streams.indices.contains(selectedLine) {
                NativePlayerView(resource: PlaybackResource(url: channel.streams[selectedLine].url,
                                                            headers: channel.streams[selectedLine].headers), controlsVisible: controls, onProgress: { _, _ in
                    if playbackRevision == run && !recorded {
                        history.record(.live(channel: channel, source: source), position: 0, duration: 0)
                        recorded = true
                    }
                })
                .id(run)
            } else {
                Text("此频道没有可播放线路，请切换源。")
                    .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { controls.wrappedValue.toggle() } }
            }
        }
        .task(id: run) { await loadEPG(channel: channel, source: source) }
        .sheet(isPresented: $showingSourcePicker) {
            LiveSourcePicker(channel: channel, source: source, selectedLine: selectedLine) { selection in
                guard selection.channel.streams.indices.contains(selection.line) else { return }
                activeChannel = selection.channel
                activeSource = selection.source
                selectedLine = selection.line
                recorded = false
                programs = []
                playbackRevision = UUID()
                showingSourcePicker = false
            }
        }
    }

    @MainActor private func loadEPG(channel: LiveChannel, source: TVBoxLive) async {
        programs = []
        guard let template = source.epg, !template.isEmpty else { return }
        let loaded = (try? await EPGLoader().load(template: template, channelName: channel.name)) ?? []
        guard !Task.isCancelled else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let now = formatter.string(from: .now)
        if let index = loaded.firstIndex(where: { $0.start <= now && now < $0.end }) {
            programs = Array(loaded[index...])
        } else { programs = loaded }
    }
}
