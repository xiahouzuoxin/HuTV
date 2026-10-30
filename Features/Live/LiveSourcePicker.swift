import SwiftUI

struct LiveSourceSelection {
    let channel: LiveChannel
    let source: TVBoxLive
    let line: Int
}

struct LiveSourcePicker: View {
    @Environment(\.dismiss) private var dismiss
    let channel: LiveChannel
    let source: TVBoxLive
    let selectedLine: Int
    let onSelect: (LiveSourceSelection) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("当前频道 · \(channel.name)") {
                    ForEach(channel.streams.indices, id: \.self) { index in
                        Button {
                            onSelect(LiveSourceSelection(channel: channel, source: source, line: index))
                        } label: {
                            HStack {
                                Text(channel.streams[index].name ?? "线路 \(index + 1)")
                                Spacer()
                                if index == selectedLine { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Section {
                    NavigationLink("从其他直播订阅选择频道") {
                        AlternateLiveSources(currentName: channel.name, currentSource: source, onSelect: onSelect)
                    }
                } footer: {
                    Text("直播切换后从新线路的当前直播位置播放，不保留时间进度。不同来源的同名频道可能是不同版本，请手动确认。")
                }
            }
            .navigationTitle("切换源")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

private struct LiveSourceGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let source: TVBoxLive
    var channels: [LiveChannel] = []
    var loading = true
    var error: String?
}

private struct AlternateLiveSources: View {
    @Environment(WarehouseStore.self) private var store
    let currentSource: TVBoxLive
    let onSelect: (LiveSourceSelection) -> Void
    @State private var query: String
    @State private var groups: [LiveSourceGroup] = []
    @State private var reload = 0

    init(currentName: String, currentSource: TVBoxLive, onSelect: @escaping (LiveSourceSelection) -> Void) {
        self.currentSource = currentSource; self.onSelect = onSelect
        _query = State(initialValue: currentName)
    }

    private var sources: [LiveSourceGroup] {
        var seen: Set<String> = [currentSource.url]
        return store.warehouses.flatMap { warehouse in
            warehouse.config.lives.compactMap { source in
                guard seen.insert(source.url).inserted else { return nil }
                return LiveSourceGroup(id: "\(warehouse.id)/\(source.url)",
                    title: warehouse.config.lives.count == 1 ? warehouse.name : "\(warehouse.name) · \(source.name)", source: source)
            }
        }
    }

    var body: some View {
        List {
            Section {
                Text("默认按当前频道名筛选。没有结果时可清空或修改搜索词，手动选择其他频道；加载列表不会中断当前播放。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if groups.isEmpty { Text("没有其他直播订阅，请先添加直播列表。") }
            ForEach(groups) { group in
                Section(group.title) {
                    if group.loading { ProgressView("加载频道…") }
                    if let error = group.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    let channels = group.channels.filter {
                        query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.group.localizedCaseInsensitiveContains(query)
                    }
                    if !group.loading && group.error == nil && channels.isEmpty {
                        Text("没有匹配频道，可修改搜索词").foregroundStyle(.secondary)
                    }
                    ForEach(channels) { channel in
                        NavigationLink {
                            List {
                                Section {
                                    Text(channel.name).font(.headline)
                                    Text(group.title).foregroundStyle(.secondary)
                                }
                                Section("选择播放线路") {
                                    ForEach(channel.streams.indices, id: \.self) { index in
                                        Button(channel.streams[index].name ?? "线路 \(index + 1)") {
                                            onSelect(LiveSourceSelection(channel: channel, source: group.source, line: index))
                                        }
                                    }
                                }
                            }
                            .navigationTitle("确认频道")
                        } label: {
                            VStack(alignment: .leading) {
                                Text(channel.name)
                                Text(channel.group).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("其他直播源")
        .searchable(text: $query, prompt: "搜索频道，清空可查看全部")
        .toolbar { Button("重新加载", systemImage: "arrow.clockwise") { reload += 1 } }
        .task(id: reload) {
            let candidates = sources
            groups = candidates
            await withTaskGroup(of: LiveSourceGroup.self) { tasks in
                for candidate in candidates {
                    tasks.addTask {
                        var result = candidate
                        do { result.channels = try await LivePlaylistLoader().load(from: candidate.source) }
                        catch { result.error = error.localizedDescription }
                        result.loading = false
                        return result
                    }
                }
                for await result in tasks {
                    guard !Task.isCancelled else { tasks.cancelAll(); return }
                    if let index = groups.firstIndex(where: { $0.id == result.id }) { groups[index] = result }
                }
            }
        }
    }
}
