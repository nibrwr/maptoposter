import SwiftUI

enum AppDesign {
    static let cornerRadius: CGFloat = 12
    static let compactRadius: CGFloat = 8

    static let graphiteTop = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let graphiteBottom = Color(red: 0.77, green: 0.81, blue: 0.86)
    static let mistBlue = Color(red: 0.70, green: 0.84, blue: 0.96)
    static let clearBlue = Color(red: 0.32, green: 0.58, blue: 0.86)
    static let inkBlue = Color(red: 0.16, green: 0.26, blue: 0.38)
    static let panelStroke = Color.white.opacity(0.72)
    static let panelFill = Color(red: 0.966, green: 0.972, blue: 0.978).opacity(0.95)
    static let quietText = Color.secondary
    static let buttonShadow = Color.black.opacity(0.18)

    static var windowBackground: some View {
        return ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.966, green: 0.972, blue: 0.978),
                    Color(red: 0.938, green: 0.948, blue: 0.958),
                    Color(red: 0.910, green: 0.922, blue: 0.934)
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
                shape.stroke(AppDesign.panelStroke, lineWidth: 1)
            }
            .shadow(color: .black.opacity(isProminent ? 0.10 : 0.06), radius: isProminent ? 16 : 8, y: isProminent ? 8 : 3)
    }
}

extension View {
    func appPanel(prominent: Bool = false) -> some View {
        modifier(AppPanelModifier(isProminent: prominent))
    }

    func buttonLift() -> some View {
        shadow(color: AppDesign.buttonShadow, radius: 7, y: 3)
    }
}
