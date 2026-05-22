import SwiftUI

enum AppDesign {
    static let cornerRadius: CGFloat = 12
    static let compactRadius: CGFloat = 8

    static let graphiteTop = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let graphiteBottom = Color(red: 0.77, green: 0.81, blue: 0.86)
    static let mistBlue = Color(red: 0.70, green: 0.84, blue: 0.96)
    static let clearBlue = Color(red: 0.32, green: 0.58, blue: 0.86)
    static let actionBlue = Color(red: 0.02, green: 0.43, blue: 0.88)
    static let inkBlue = Color(red: 0.16, green: 0.26, blue: 0.38)
    static let panelStroke = Color.white.opacity(0.90)
    static let panelEdge = Color(red: 0.68, green: 0.75, blue: 0.82).opacity(0.34)
    static let panelFill = Color(red: 0.988, green: 0.992, blue: 0.996).opacity(0.98)
    static let quietText = Color.secondary
    static let buttonShadow = Color.black.opacity(0.24)

    static let panelTitleFont = Font.headline
    static let windowTitleFont = Font.title.weight(.semibold)
    static let formLabelFont = Font.subheadline
    static let controlTitleFont = Font.subheadline.weight(.semibold)
    static let controlDetailFont = Font.caption
    static let metadataFont = Font.caption
    static let statusValueFont = Font.title3.monospacedDigit().weight(.semibold)
    static let logFont = Font.system(.caption, design: .monospaced)

    static var windowBackground: some View {
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.948, green: 0.958, blue: 0.970),
                    Color(red: 0.918, green: 0.934, blue: 0.948),
                    Color(red: 0.872, green: 0.892, blue: 0.912)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct AppWindowBackground: View {
    var body: some View {
        AppDesign.windowBackground
        .ignoresSafeArea()
    }
}

struct AppPanelModifier: ViewModifier {
    var isProminent = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)

        content
            .padding(isProminent ? 18 : 16)
            .background(AppDesign.panelFill, in: shape)
            .overlay {
                shape.stroke(AppDesign.panelEdge, lineWidth: 1)
            }
            .overlay {
                shape
                    .stroke(AppDesign.panelStroke, lineWidth: 0.7)
                    .blendMode(.screen)
            }
            .shadow(color: AppDesign.mistBlue.opacity(isProminent ? 0.18 : 0.12), radius: isProminent ? 28 : 20, y: isProminent ? 12 : 8)
            .shadow(color: .black.opacity(isProminent ? 0.13 : 0.09), radius: isProminent ? 18 : 12, y: isProminent ? 8 : 5)
    }
}

extension View {
    func appPanel(prominent: Bool = false) -> some View {
        modifier(AppPanelModifier(isProminent: prominent))
    }

    func buttonLift() -> some View {
        modifier(ButtonLiftModifier())
    }
}

private struct ButtonLiftModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: AppDesign.buttonShadow.opacity(isEnabled ? (isHovered ? 1.0 : 0.72) : 0.18),
                radius: isHovered ? 12 : 8,
                y: isHovered ? 5 : 3
            )
            .scaleEffect(isHovered && isEnabled ? 1.015 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
