import SwiftUI

struct EditSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WarehouseStore.self) private var store
    let warehouse: Warehouse
    @State private var name: String
    @State private var address: String
    @State private var saving = false
    @State private var copied = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?

    init(warehouse: Warehouse) {
        self.warehouse = warehouse
        _name = State(initialValue: warehouse.name)
        _address = State(initialValue: warehouse.configURL.absoluteString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅信息") {
                    LabeledContent("类型", value: warehouse.kind.label)
                    TextField("订阅名称", text: $name)
                }.disabled(saving)
                Section {
                    TextField("HTTP(S) 地址", text: $address, axis: .vertical)
                        .lineLimit(3...8).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("订阅链接")
                    Button(copied ? "已复制链接" : "复制链接", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = address
                        copied = true
                    }
                    .disabled(address.isEmpty)
                } header: {
                    Text("订阅链接")
                } footer: {
                    Text("修改地址后会先验证格式，成功才替换原配置。仅修改名称无需联网。订阅身份与排序保留，历史记录不会删除。")
                }
                .disabled(saving)
                if address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http://") {
                    Section {
                        Label("HTTP 传输未加密，优先使用 HTTPS 地址。", systemImage: "exclamationmark.shield")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if saving { Section { ProgressView("验证并保存订阅…") } }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("查看与编辑订阅")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saving ? "取消操作" : "取消") {
                        if saving { operation?.cancel() } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(saving || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasChanges)
                }
            }
            .onChange(of: address) { copied = false; errorMessage = nil }
            .onChange(of: name) { errorMessage = nil }
            .interactiveDismissDisabled(saving)
            .onDisappear { operation?.cancel() }
        }
    }

    private var hasChanges: Bool {
        name != warehouse.name || address.trimmingCharacters(in: .whitespacesAndNewlines) != warehouse.configURL.absoluteString
    }
    private func save() {
        saving = true; errorMessage = nil
        operation = Task { @MainActor in
            defer { saving = false }
            do {
                try await store.update(id: warehouse.id, name: name, address: address)
                dismiss()
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
    }
}
