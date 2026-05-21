import Foundation
import SwiftUI

struct PosterTheme: Identifiable, Hashable {
    let slug: String
    let name: String
    let description: String
    let backgroundHex: String
    let roadHex: String
    let textHex: String

    var id: String { slug }

    var displayName: String {
        name.isEmpty ? slug.replacingOccurrences(of: "_", with: " ").capitalized : name
    }

    var backgroundColor: Color {
        Color(hex: backgroundHex) ?? .secondary.opacity(0.15)
    }

    var roadColor: Color {
        Color(hex: roadHex) ?? .accentColor
    }

    var textColor: Color {
        Color(hex: textHex) ?? .primary
    }
}
