import SwiftUI

struct MemoryAnalysisSourceView: View {
    let sourceText: String

    var body: some View {
        DisclosureGroup("用于学习的文字") {
            VStack(alignment: .leading, spacing: 8) {
                Text("已保存的最终文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(sourceText)
                    .textSelection(.enabled)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.top, 8)
        }
    }
}
