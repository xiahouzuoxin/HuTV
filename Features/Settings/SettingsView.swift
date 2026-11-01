import SwiftUI

struct SettingsView: View {
    @Environment(WarehouseStore.self) private var store
    @AppStorage("playback.engine") private var engine: PlaybackEngine = .avPlayer
    @AppStorage("playback.autoAdvance") private var autoAdvance = true
    @AppStorage("playback.forwardBufferSeconds") private var bufferSeconds = 30.0
    @AppStorage("playback.rate") private var rate = 1.0
    @AppStorage("playback.scaling") private var scaling: PlaybackScaling = .fit
    @AppStorage("subscriptions.autoRefresh") private var autoRefresh = false
    @AppStorage("subscriptions.refreshHours") private var refreshHours = 6
    @AppStorage("search.concurrency") private var searchConcurrency = 4
    @State private var defaultsAdded = false
    @State private var showingFeeds = false
    @State private var showingPrivacy = false
    @State private var showingLicenses = false

    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            SettingsGroup("播放设置") {
                SettingsOption("AVPlayer 使用系统播放能力；VLC 兼容更多格式。切换内核会尝试保留进度。") {
                    Picker("播放内核", selection: $engine) {
                        ForEach(PlaybackEngine.allCases) { Text($0.label).tag($0) }
                    }.tint(Color.secondary)
                }
                Toggle("自动连播下一集", isOn: $autoAdvance)
                SettingsOption("AVPlayer 使用所选缓冲目标；VLC 最多缓冲 3 秒。实际效果取决于视频源。") {
                    Picker("预缓冲", selection: $bufferSeconds) {
                        Text("系统自动").tag(0.0)
                        Text("30 秒").tag(30.0)
                        Text("60 秒").tag(60.0)
                    }.tint(Color.secondary)
                }
                Picker("播放速度", selection: $rate) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { Text("\($0.formatted())×").tag($0) }
                }.tint(Color.secondary)
                SettingsOption("速度和画面缩放与播放页同步，记住后用于下次播放。") {
                    Picker("画面缩放", selection: $scaling) {
                        ForEach(PlaybackScaling.allCases) { Text($0.label).tag($0) }
                    }.tint(Color.secondary)
                }
            }
            SettingsGroup("订阅与搜索") {
                SettingsOption(autoRefresh
                    ? "仅在前台定时刷新；在线 JSON 列表需开启跟随链接。"
                    : "已关闭自动刷新。可在订阅页下拉手动更新。") {
                    Toggle("自动刷新订阅", isOn: $autoRefresh)
                }
                if autoRefresh {
                    Picker("刷新间隔", selection: $refreshHours) {
                        ForEach([1, 6, 12, 24], id: \.self) { hours in
                            Text("\(hours) 小时").tag(hours)
                        }
                    }.tint(Color.secondary)
                }
                SettingsLink("在线 JSON 列表（\(store.feeds.count)）") { showingFeeds = true }
                if !store.lastRefreshErrors.isEmpty {
                    Text("部分订阅更新失败，可下拉重试，原有内容已保留。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                SettingsOption("添加缺少的点播和直播源，不重复添加已有订阅。") {
                    Button("添加缺少的默认源") {
                        store.addDefaultSubscriptions()
                        defaultsAdded = true
                    }
                }
                if defaultsAdded { Text(store.lastPersistenceError ?? "默认源已添加").font(.footnote) }
                SettingsOption("其余源排队，下次搜索生效。并发过高可能增加网络和设备负担。") {
                    Picker("搜索并发数", selection: $searchConcurrency) {
                        ForEach([2, 4, 6, 8], id: \.self) { Text("\($0) 个源").tag($0) }
                    }.tint(Color.secondary)
                }
            }
            StorageSettingsSections()
            SettingsGroup("关于 HuTV") {
                LabeledContent("版本", value: version)
                SettingsLink("隐私说明") { showingPrivacy = true }
                SettingsLink("开源许可") { showingLicenses = true }
            }
        }
        .environment(\.defaultMinListRowHeight, 44)
        .navigationTitle("设置")
        .navigationDestination(isPresented: $showingFeeds) { SubscriptionFeedsView() }
        .navigationDestination(isPresented: $showingPrivacy) { PrivacyView() }
        .navigationDestination(isPresented: $showingLicenses) { OpenSourceLicensesView() }
    }
}

/// Keep an option and its explanation in one native Form row.
struct SettingsOption<Content: View>: View {
    let explanation: String
    let content: Content
    init(_ explanation: String, @ViewBuilder content: () -> Content) {
        self.explanation = explanation
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content.frame(minHeight: 28)
            Text(explanation).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 2)
    }
}

/// One Form row per group avoids the system's per-row vertical padding.
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        Section(title) {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.borderless)
            .pickerStyle(.menu)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }
}

struct SettingsLink: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }.frame(minHeight: 36).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
