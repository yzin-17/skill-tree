import SwiftUI

struct PageHeading: View {
    let title: String
    let subtitle: String
    init(_ title: String, subtitle: String = "") { self.title = title; self.subtitle = subtitle }
    var body: some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 26, weight: .semibold)); if !subtitle.isEmpty { Text(subtitle).font(.system(size: 13)).foregroundStyle(AtlasTheme.muted) } } }
}

struct EmptyWorkspace<Actions: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(AtlasTheme.muted)
            Text(title).font(.system(size: 20, weight: .medium))
            actions().padding(.top, 8)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InlineFailure: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack { Label(message, systemImage: "exclamationmark.circle").font(.callout); Spacer(); Button("重试", action: retry) }
            .padding(16).background(AtlasTheme.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EditorFooter: View {
    let error: String?
    let saving: Bool
    let canSave: Bool
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button(action: save) { if saving { ProgressView().controlSize(.small) } else { Text("保存") } }.keyboardShortcut(.defaultAction).disabled(!canSave || saving) }
        }.padding(20)
    }
}
