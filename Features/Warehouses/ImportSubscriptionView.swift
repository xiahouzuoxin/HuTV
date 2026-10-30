import SwiftUI

struct ImportSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WarehouseStore.self) private var store
    @State private var kind: SubscriptionKind = .cms
    @State private var name = ""
    @State private var urlText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅类型") {
                    ForEach(SubscriptionKind.allCases) { value in
                        Button {
                            kind = value
                        } label: {
                            HStack {
                                Text(value.label).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: kind == value ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(kind == value ? Color.accentColor : Color.secondary)
                            }
                            .contentShape(Rectangle())
                            .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(value.label)
                        .accessibilityAddTraits(kind == value ? .isSelected : [])
                    }
                    Text(kind.hint).font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(isImporting)
                Section("订阅地址") {
                    TextField("名称（可选）", text: $name)
                    TextField(kind.placeholder, text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                .disabled(isImporting)

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if urlText.lowercased().hasPrefix("http://") {
                    Section {
                        Label("HTTP 连接不会加密，配置和播放地址可能被网络中的其他设备读取或篡改。", systemImage: "exclamationmark.shield")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("添加订阅")
            .onChange(of: kind) { errorMessage = nil }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "导入中…" : "导入") {
                        Task { await importSubscription() }
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                }
            }
        }
    }

    @MainActor
    private func importSubscription() async {
        errorMessage = nil
        isImporting = true
        defer { isImporting = false }
        do {
            try await store.importURL(urlText.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, name: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
