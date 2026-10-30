import SwiftUI

struct BackendAddressEditor: View {
    @Environment(ApplicationStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var check: BackendConnectionCheck
    @State private var error: String?
    @State private var pauseConfirmation = false
    private let defaultAddress: String

    init(address: String, defaultAddress: String, makeClient: @escaping @MainActor (BackendAddress) throws -> APIClient) {
        _check = State(initialValue: BackendConnectionCheck(address: address, makeClient: makeClient))
        self.defaultAddress = defaultAddress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("后端地址").font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                TextField("https://example.com:8447", text: $check.address)
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .accessibilityLabel("后端地址").accessibilityIdentifier("backend-address-input")
                if let message = error ?? check.validationError ?? check.error {
                    Label(message, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("backend-address-error")
                } else if check.isChecking {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在检查连接").font(.callout) }
                } else if check.health != nil {
                    Label("连接正常", systemImage: "checkmark.circle").font(.callout).foregroundStyle(AtlasTheme.growth)
                        .accessibilityIdentifier("backend-address-success")
                }
                if (try? BackendAddress(check.address))?.text != defaultAddress {
                    Button("使用默认地址") { check.address = defaultAddress }
                        .buttonStyle(.link).accessibilityIdentifier("backend-address-default")
                }
            }
            HStack(spacing: 12) {
                Button("取消", role: .cancel) { check.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("检查连接") { Task { await check.check() } }
                    .disabled(check.isChecking || check.validationError != nil)
                    .accessibilityIdentifier("backend-address-check")
                Button(store.account.user == nil ? "保存" : "保存并切换", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(check.validationError != nil || store.account.isBusy)
                    .accessibilityIdentifier("backend-address-save")
            }.controlSize(.large)
        }.padding(28).frame(width: 520).background(AtlasTheme.ground)
            .onChange(of: check.address) { _, _ in error = nil }
            .onDisappear { check.cancel() }
            .confirmationDialog("暂停专注并切换后端？", isPresented: $pauseConfirmation, titleVisibility: .visible) {
                Button("暂停并切换", action: apply)
            }
    }
    private func save() {
        if store.focus?.snapshot?.status == .running, (try? BackendAddress(check.address)) != store.backendAddress { pauseConfirmation = true }
        else { apply() }
    }
    private func apply() {
        do { try store.changeBackend(to: check.address); check.cancel(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
