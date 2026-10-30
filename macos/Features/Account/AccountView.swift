import SwiftUI

struct AccountView: View {
    @Environment(ApplicationStore.self) private var store
    @State private var create = false
    @State private var email = ""
    @State private var password = ""
    @State private var rememberLogin = false
    @FocusState private var field: Field?
    private enum Field { case email, password }

    var body: some View {
        HStack(spacing: 64) {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 58, weight: .ultraLight)).foregroundStyle(AtlasTheme.growth)
                Text("Skill Atlas").font(.system(size: 38, weight: .medium))
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 24) {
                Text(create ? "创建账号" : "登录").font(.system(size: 24, weight: .semibold))
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("邮箱").font(.system(size: 12, weight: .medium))
                        TextField("name@example.com", text: $email).textContentType(.username)
                            .textFieldStyle(.roundedBorder).controlSize(.large).focused($field, equals: .email)
                            .accessibilityLabel("邮箱").accessibilityIdentifier("account-email")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("密码").font(.system(size: 12, weight: .medium))
                        SecureField(create ? "12–128 个字符" : "输入密码", text: $password)
                            .textContentType(create ? .newPassword : .password).textFieldStyle(.roundedBorder).controlSize(.large)
                            .focused($field, equals: .password).accessibilityLabel("密码").accessibilityIdentifier("account-password")
                    }
                    Toggle("记住登录", isOn: $rememberLogin).toggleStyle(.checkbox).disabled(store.account.isBusy)
                        .help("将登录令牌保存在本机钥匙串").accessibilityIdentifier("account-remember-login")
                    if let error = store.account.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: submit) {
                        HStack { Spacer(); if store.account.isBusy { ProgressView().controlSize(.small) }; Text(create ? "创建账号" : "登录"); Spacer() }.padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).tint(.white)
                        .disabled(email.isEmpty || password.isEmpty || store.account.isBusy).keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("account-submit")
                }
                HStack {
                    Button(create ? "去登录" : "创建账号") { create.toggle(); password = ""; store.account.errorMessage = nil }
                        .buttonStyle(.link).tint(.white).accessibilityIdentifier("account-mode")
                    Spacer()
                    Button("后端地址…") { store.isBackendEditorPresented = true }
                        .buttonStyle(.link).tint(.white).disabled(store.account.isBusy)
                        .accessibilityIdentifier("account-backend-address")
                }.font(.system(size: 12))
            }.padding(32).frame(width: 380).background(AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }.padding(64).frame(maxWidth: 1100, maxHeight: .infinity)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(AtlasTheme.ground)
            .onSubmit(submit).onAppear { field = .email }
    }
    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await store.account.authenticate(email: email, password: password, create: create, rememberLogin: rememberLogin); if store.account.user != nil { password = "" } }
    }
}
