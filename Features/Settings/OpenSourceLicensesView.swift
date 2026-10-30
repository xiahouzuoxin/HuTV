import SwiftUI

struct OpenSourceLicensesView: View {
    private var license: String {
        guard let url = Bundle.main.url(forResource: "MobileVLCKit-LGPL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "许可证文件无法读取。" }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MobileVLCKit 3.7.3").font(.title2.bold())
                Text("HuTV 使用未修改的 VideoLAN MobileVLCKit / libVLC。版权归各自贡献者所有。")
                Link("VLCKit 对应版本源码", destination: URL(string: "https://code.videolan.org/videolan/VLCKit/-/tree/3.7.3")!)
                Link("libVLC 对应源码", destination: URL(string: "https://code.videolan.org/videolan/vlc/-/tree/79128878")!)
                Text(license).font(.footnote).textSelection(.enabled)
            }.padding()
        }.navigationTitle("开源许可")
    }
}
