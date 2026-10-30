import SwiftUI

struct IconPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var icons: [SkillIcon] { SkillIcon.all.filter { search.isEmpty || ($0.name + $0.category + $0.id).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("选择图标").font(.title2); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
            TextField("搜索名称或类别", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(icons) { icon in
                        Button { selection = icon.id } label: {
                            VStack(spacing: 9) { Image(systemName: icon.symbol).font(.system(size: 24, weight: .light)); Text(icon.name).font(.caption) }
                                .frame(maxWidth: .infinity).frame(height: 78)
                                .background(selection == icon.id ? AtlasTheme.raised : AtlasTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) { if selection == icon.id { Image(systemName: "checkmark").font(.caption).padding(6) } }
                        }.buttonStyle(.plain).accessibilityLabel("\(icon.name)，\(icon.category)\(selection == icon.id ? "，已选择" : "")")
                    }
                }
            }
        }.padding(24).frame(width: 440, height: 460)
    }
}
