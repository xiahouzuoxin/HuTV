import SwiftUI

struct PrivacyView: View {
    @Environment(HistoryStore.self) private var history
    @State private var confirmClear = false

    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私说明无法读取，请通过 App Store 产品页的 App 支持联系发布者。"
        }
        return text
    }

    var body: some View {
        List {
            Section("本机历史") {
                LabeledContent("搜索历史", value: "\(history.searches.count) 条")
                LabeledContent("观看历史", value: "\(history.records.count) 条")
                Button("清空搜索与观看历史", role: .destructive) { confirmClear = true }
                    .disabled(history.searches.isEmpty && history.records.isEmpty)
                if let error = history.persistenceError {
                    Text(error).foregroundStyle(.red)
                }
                Text("清空后无法恢复。订阅和播放器设置将保留。订阅可在订阅页单独删除。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("隐私说明") {
                Text(policy).font(.body).textSelection(.enabled)
            }
        }
        .navigationTitle("隐私与数据")
        .confirmationDialog("清空搜索与观看历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) {
                history.clearSearches()
                history.clearRecords()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除本机搜索记录、观看记录和播放进度，无法恢复。")
        }
    }
}
