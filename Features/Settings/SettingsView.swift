import SwiftUI

struct SettingsView: View {
    @Environment(WarehouseStore.self) private var store
    @State private var defaultsAdded = false
    @AppStorage("playback.engine") private var engine: PlaybackEngine = .avPlayer
    @AppStorage("playback.autoAdvance") private var autoAdvance = true
    @AppStorage("playback.forwardBufferSeconds") private var bufferSeconds = 30.0

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("关于 HuTV") {
                NavigationLink("隐私与数据") { PrivacyView() }
                LabeledContent("版本", value: appVersion)
            }
            Section("点播播放") {
                Toggle("自动连播下一集", isOn: $autoAdvance)
                Picker("预缓冲", selection: $bufferSeconds) {
                    Text("系统自动").tag(0.0)
                    Text("30 秒").tag(30.0)
                    Text("60 秒").tag(60.0)
                }
                Text("AVPlayer 使用所选前向缓冲目标；VLC 使用最多 3 秒网络缓冲，避免开播等待过长。实际效果取决于视频源。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("默认订阅源") {
                Button("添加缺少的默认源") {
                    store.addDefaultSubscriptions()
                    defaultsAdded = true
                }
                Text("包含点播接口和中文/国际直播列表。可在订阅页删除；已添加的源不会重复添加。直播列表部分频道可能受地区或源站限制。")
                    .font(.footnote).foregroundStyle(.secondary)
                if defaultsAdded { Text(store.lastPersistenceError ?? "默认源已添加").font(.footnote) }
            }
            Section("播放器内核") {
                NavigationLink("开源许可") { OpenSourceLicensesView() }
                Picker("播放内核", selection: $engine) {
                    ForEach(PlaybackEngine.allCases) { Text($0.label).tag($0) }
                }
                Text("AVPlayer 使用系统播放能力；VLC 用于对比和播放其他兼容格式。播放中切换会尝试保留进度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
    }
}
