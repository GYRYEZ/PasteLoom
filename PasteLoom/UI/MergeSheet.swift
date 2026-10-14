import SwiftUI

struct MergeSheet: View {
    @ObservedObject var model: AppModel
    let selectedIDs: [UUID]
    let palette: PaperPalette
    let onDismiss: () -> Void

    @State private var separatorChoice = "newline"
    @State private var customSeparator = ""
    @State private var copyAfterMerge = true
    @State private var isProcessing = false

    private var separatorString: String {
        switch separatorChoice {
        case "newline": return "\n"
        case "doubleNewline": return "\n\n"
        case "space": return " "
        case "comma": return "，"
        case "custom": return customSeparator
        default: return "\n"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("合并条目 (\(selectedIDs.count) 项)").font(.headline.weight(.bold))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("分隔方式").font(.subheadline.weight(.semibold))
                Picker("分隔符", selection: $separatorChoice) {
                    Text("单换行 (\\n)").tag("newline")
                    Text("双换行 (段落)").tag("doubleNewline")
                    Text("空格").tag("space")
                    Text("逗号").tag("comma")
                    Text("自定义").tag("custom")
                }
                .pickerStyle(.segmented)

                if separatorChoice == "custom" {
                    TextField("输入自定义分隔符", text: $customSeparator)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 4)
                }
            }

            Toggle("合并完成后自动复制到剪贴板", isOn: $copyAfterMerge)
                .font(.subheadline)

            HStack {
                Spacer()
                Button("取消") { onDismiss() }
                    .buttonStyle(.bordered)
                Button("开始合并") {
                    isProcessing = true
                    Task {
                        if let merged = await model.mergeSelected(ids: selectedIDs, separator: separatorString) {
                            if copyAfterMerge {
                                model.copy(merged)
                            }
                        }
                        isProcessing = false
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 380)
        .background(palette.background)
        .foregroundStyle(palette.primaryText)
    }
}
