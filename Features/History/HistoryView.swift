import SwiftUI

struct HistoryView: View {
    @Environment(HistoryStore.self) private var history
    @State private var confirmingClear = false
    @State private var playingLive: WatchRecord?
    var body: some View {
        Group {
            if history.records.isEmpty {
                ContentUnavailableView("还没有观看记录", systemImage: "clock.arrow.circlepath",
                                       description: Text("成功打开视频后会自动记录，可在这里继续观看"))
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)],
                              alignment: .leading, spacing: 12) {
                        ForEach(history.records) { record in
                            historyEntry(record)
                            .buttonStyle(.plain)
                            .overlay(alignment: .topTrailing) {
                                Menu {
                                    Button("删除记录", systemImage: "trash", role: .destructive) {
                                        history.removeRecord(record.id)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.headline).foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(.black.opacity(0.55), in: Circle())
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("管理 \(record.target.title) 的观看记录")
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .fullScreenCover(item: $playingLive) { record in
            if case .live(let channel, let source) = record.target {
                LivePlayerView(channel: channel, source: source)
            }
        }
        .navigationTitle("观看历史")
        .toolbar { if !history.records.isEmpty { Button("清空") { confirmingClear = true } } }
        .confirmationDialog("清空所有观看记录？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空记录", role: .destructive) { history.clearRecords() }
        }
        .alert("历史记录保存失败", isPresented: Binding(get: { history.persistenceError != nil },
            set: { if !$0 { history.clearError() } })) { Button("好") { history.clearError() } }
            message: { Text(history.persistenceError ?? "") }
    }

    private func historyCard(_ record: WatchRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(.tertiarySystemFill))
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    AsyncImage(url: record.target.posterURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "play.rectangle")
                                .font(.largeTitle).foregroundStyle(.secondary)
                        }
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(record.target.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(record.target.subtitle).font(.caption2)
                    .foregroundStyle(.secondary).lineLimit(1)
                if case .vod = record.target {
                    Text("看到 \(time(record.position))" + (record.duration > 0 ? " / \(time(record.duration))" : ""))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    ProgressView(value: record.duration > 0 ? min(max(record.position / record.duration, 0), 1) : 0)
                        .tint(.accentColor)
                } else {
                    Label("直播", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(record.watchedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func historyEntry(_ record: WatchRecord) -> some View {
        switch record.target {
        case .vod(let item, let source, _):
            NavigationLink {
                MediaDetailView(provider: StandardCMSProvider(id: item.sourceID, source: source), item: item, resumeRecord: record)
            } label: {
                historyCard(record)
            }
        case .live:
            Button { playingLive = record } label: {
                historyCard(record)
            }
        }
    }
    private func time(_ value: Double) -> String {
        let seconds = value.isFinite && value > 0 ? Int(min(value, Double(Int.max / 2))) : 0
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
