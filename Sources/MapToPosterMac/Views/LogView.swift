import SwiftUI

struct LogView: View {
    let logText: String
    let isGenerating: Bool
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Run Log", systemImage: "terminal")
                    .font(AppDesign.panelTitleFont)
                    .foregroundStyle(AppDesign.inkBlue)

                Spacer()

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            ScrollView {
                Text(logText.isEmpty ? "Generation output will appear here." : logText)
                    .font(AppDesign.logFont)
                    .foregroundStyle(logText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .appPanel()
        .accessibilityElement(children: .contain)
    }
}
