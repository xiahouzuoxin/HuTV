import SwiftUI
import UniformTypeIdentifiers

struct BatchImportView: View {
    private enum InputMode: String, CaseIterable, Identifiable {
        case link = "在线链接", text = "粘贴 JSON", file = "本地文件"
        var id: String { rawValue }
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(WarehouseStore.self) private var store
    @State private var mode = InputMode.link
    @State private var link = ""
    @State private var text = ""
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var choosingFile = false
    @State private var entries: [BatchSubscriptionEntry]?
    @State private var selected: Set<Int> = []
    @State private var outcomes: [BatchImportOutcome]?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("JSON 来源") {
                    Picker("输入方式", selection: $mode) {
                        ForEach(InputMode.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    switch mode {
                    case .link:
                        TextField("JSON 直链或 GitHub 文件链接", text: $link)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    case .text:
                        TextEditor(text: $text).frame(minHeight: 150).font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityLabel("JSON 订阅列表")
                    case .file:
                        Button(fileName.isEmpty ? "选择 JSON 文件" : fileName) { choosingFile = true }
                    }
                    Text("数组中每项使用 name 和 api（或 url）。可选 kind：cms、live、tvbox。未填类型时，M3U/TXT 地址识别为直播，其他地址按点播 API 验证。支持注释、尾逗号；最多 200 项、5 MB。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("读取列表") { readList() }.disabled(!canRead)
                }.disabled(busy)

                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                if busy { Section { ProgressView(entries == nil ? "读取 JSON…" : "正在验证订阅，最多同时验证 4 项…") } }

                if let outcomes {
                    Section("导入结果") {
                        Text("添加 \(outcomes.filter { $0.status == .added }.count) · 跳过 \(outcomes.filter { $0.status == .skipped }.count) · 失败 \(outcomes.filter { $0.status == .failed }.count)")
                        ForEach(outcomes) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                Text(result.message).font(.caption)
                                    .foregroundStyle(result.status == .failed ? Color.red : Color.secondary)
                            }
                        }
                    }
                } else if let entries {
                    Section("选择订阅（\(selected.count)/\(entries.count)）") {
                        if entries.isEmpty { Text("列表为空") }
                        ForEach(entries) { entry in
                            if let issue = entry.issue {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name)
                                    Text(issue).font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: {
                                    if $0 { selected.insert(entry.id) } else { selected.remove(entry.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.name)
                                        Text(entry.kind?.label ?? "").font(.caption).foregroundStyle(.secondary)
                                        Text(entry.address).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                        }
                    }.disabled(busy)
                }
            }
            .navigationTitle("JSON 批量导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(busy ? "取消操作" : "关闭") {
                        if busy { operation?.cancel() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if outcomes != nil {
                        Button("完成") { dismiss() }
                    } else {
                        Button("导入所选") { importSelected() }.disabled(busy || selected.isEmpty)
                    }
                }
            }
            .onChange(of: mode) { resetPreview() }
            .onChange(of: link) { resetPreview() }
            .onChange(of: text) { resetPreview() }
            .onDisappear { operation?.cancel() }
            .interactiveDismissDisabled(busy)
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.json, .plainText]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: BatchSubscriptionList.maximumBytes + 1) ?? Data()
                    guard data.count <= BatchSubscriptionList.maximumBytes else { throw BatchListError.tooLarge }
                    fileData = data; fileName = url.lastPathComponent; resetPreview()
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private var canRead: Bool {
        switch mode {
        case .link: !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .text: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file: fileData != nil
        }
    }
    private func resetPreview() { entries = nil; selected = []; outcomes = nil; errorMessage = nil }

    private func readList() {
        busy = true; resetPreview()
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let reader = BatchSubscriptionList()
                let loaded: [BatchSubscriptionEntry]
                switch mode {
                case .link: loaded = try await reader.load(from: link)
                case .text: loaded = try reader.decode(Data(text.utf8))
                case .file: loaded = try reader.decode(fileData ?? Data())
                }
                try Task.checkCancellation()
                entries = loaded
                selected = Set(loaded.filter { $0.issue == nil }.map(\.id))
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
    private func importSelected() {
        guard let entries else { return }
        busy = true; errorMessage = nil
        let chosen = entries.filter { selected.contains($0.id) || $0.issue != nil }
        operation = Task { @MainActor in
            defer { busy = false }
            do { outcomes = try await store.importBatch(chosen) }
            catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
}
