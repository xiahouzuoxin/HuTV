import SwiftUI

struct StorageSettingsSections: View {
    @Environment(WarehouseStore.self) private var store
    @Environment(HistoryStore.self) private var history
    @State private var confirmClear = false
    @State private var cacheBytes = 0
    @State private var action: Action?
    @State private var message: String?
    private enum Action: String, Identifiable {
        case preferences, all
        var id: String { rawValue }
        var title: String { self == .preferences ? "恢复默认设置？" : "删除全部本机数据？" }
    }
    var body: some View {
        Group {
            SettingsGroup("存储与数据") {
                LabeledContent("网络缓存（内存与磁盘）", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                SettingsOption("保留订阅、历史和设置；不清理正在播放的缓冲，也不会缩小安装包。") {
                    Button("清空网络缓存") {
                        AppMaintenance.clearCache()
                        cacheBytes = AppMaintenance.cacheBytes()
                        message = "已清空 App 网络缓存。系统或播放器自行管理的缓冲不在此范围内。"
                    }
                }
                LabeledContent("搜索历史", value: "\(history.searches.count) 条")
                LabeledContent("观看历史", value: "\(history.records.count) 条")
                SettingsOption("删除搜索与观看历史、播放进度；保留订阅、设置和剧集起播位置。") {
                    Button("清空搜索与观看历史", role: .destructive) { confirmClear = true }
                        .disabled(history.searches.isEmpty && history.records.isEmpty)
                }
                if let error = history.persistenceError { Text(error).foregroundStyle(.red) }
                SettingsOption("仅恢复偏好，保留订阅、历史和剧集起播位置。") {
                    Button("恢复默认设置") { action = .preferences }
                }
                SettingsOption("清除订阅、JSON 跟随列表、历史、进度、起播位置及设置。无法恢复，需确认后执行。") {
                    Button("删除全部本机数据", role: .destructive) { action = .all }
                }
            }
        }
        .onAppear { cacheBytes = AppMaintenance.cacheBytes() }
        .confirmationDialog(action?.title ?? "重置", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
            if let selected = action {
                Button(selected == .preferences ? "恢复默认设置" : "删除全部本机数据", role: .destructive) { perform(selected) }
            }
            Button("取消", role: .cancel) { action = nil }
        } message: {
            Text(action == .all ? "删除后无法恢复。不会删除 App 或改变签名。" : "播放器、搜索和订阅自动刷新偏好将恢复默认值。")
        }
        .confirmationDialog("清空搜索与观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                history.clearError()
                history.clearSearches()
                history.clearRecords()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除本机搜索记录、观看记录和播放进度，无法恢复。订阅、设置及起播位置保留。")
        }
        .alert("操作结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func perform(_ selected: Action) {
        action = nil
        if selected == .preferences {
            AppMaintenance.resetPreferences()
            message = "已恢复默认设置。"
            return
        }
        do {
            try history.clearAll()
            try store.clearAll()
            AppMaintenance.resetPreferences()
            AppMaintenance.clearCache()
            NotificationCenter.default.post(name: AppMaintenance.didReset, object: nil)
        } catch {
            message = "未能完成全部清理，部分数据可能已删除：\(error.localizedDescription)"
        }
    }
}
