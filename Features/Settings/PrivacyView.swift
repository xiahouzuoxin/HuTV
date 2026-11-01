import SwiftUI

struct PrivacyView: View {

    private var policy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私说明无法读取，请通过 App Store 产品页的 App 支持联系发布者。"
        }
        return text
    }

    var body: some View {
        List {
            Section("隐私说明") {
                Text(policy).font(.body).textSelection(.enabled)
            }
        }
        .navigationTitle("隐私说明")
    }
}
