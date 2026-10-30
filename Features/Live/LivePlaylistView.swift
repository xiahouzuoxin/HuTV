import SwiftUI

struct LivePlaylistView: View {
    let source: TVBoxLive
    @State private var channels: [LiveChannel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var playingChannel: LiveChannel?

    private var filteredChannels: [LiveChannel] {
        query.isEmpty ? channels : channels.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.group.localizedCaseInsensitiveContains(query)
        }
    }

    private var groups: [String] {
        Array(Set(filteredChannels.map(\.group))).sorted()
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载直播频道…")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("直播源加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load() } }
                }
            } else {
                List {
                    ForEach(groups, id: \.self) { group in
                        Section(group) {
                            ForEach(filteredChannels.filter { $0.group == group }) { channel in
                                Button {
                                    playingChannel = channel
                                } label: {
                                    HStack {
                                        AsyncImage(url: channel.logoURL) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            Image(systemName: "tv")
                                        }
                                        .frame(width: 38, height: 30)

                                        Text(channel.name)
                                        Spacer()
                                        if channel.streams.count > 1 {
                                            Text("\(channel.streams.count) 条线路")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "play.circle.fill")
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(source.name)
        .searchable(text: $query, prompt: "搜索频道")
        .task { await load() }
        .fullScreenCover(item: $playingChannel) { channel in
            LivePlayerView(channel: channel, source: source)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            channels = try await LivePlaylistLoader().load(from: source)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
