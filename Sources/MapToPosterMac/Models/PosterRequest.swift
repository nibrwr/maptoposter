import Foundation

struct PosterRequest {
    var zipCode: String = ""
    var locationQuery: String = "San Francisco, CA"
    var city: String = ""
    var country: String = ""
    var displayCity: String = ""
    var displayCountry: String = ""
    var countryLabel: String = ""
    var themeSlug: String = "sunset"
    var distance: Double = 10000
    var sizePreset: PosterSizePreset = .twelveBySixteen
    var customWidthText: String = "12"
    var customHeightText: String = "16"
    var width: Double = 12
    var height: Double = 16
    var format: PosterFormat = .png

    var canGenerate: Bool {
        !locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveDimensions != nil
    }

    func commandArguments() -> [String] {
        let dimensions = effectiveDimensions ?? (width, height)
        var arguments = [
            "--location", trimmed(locationQuery),
            "--city", posterCity,
            "--country", posterRegion,
            "--theme", themeSlug,
            "--distance", String(Int(distance)),
            "--width", formattedDimension(dimensions.width),
            "--height", formattedDimension(dimensions.height),
            "--format", format.rawValue
        ]

        appendIfPresent("--display-city", displayCity, to: &arguments)
        appendIfPresent("--display-country", displayCountry, to: &arguments)
        appendIfPresent("--country-label", countryLabel, to: &arguments)

        return arguments
    }

    mutating func apply(_ preset: CityPreset) {
        zipCode = ""
        locationQuery = preset.locationQuery
        city = preset.city
        country = preset.country
        themeSlug = preset.themeSlug
        distance = Double(preset.distance)
    }

    mutating func apply(_ sizePreset: PosterSizePreset) {
        self.sizePreset = sizePreset

        guard let presetWidth = sizePreset.width, let presetHeight = sizePreset.height else {
            customWidthText = formattedDimension(width)
            customHeightText = formattedDimension(height)
            return
        }

        width = presetWidth
        height = presetHeight
        customWidthText = formattedDimension(presetWidth)
        customHeightText = formattedDimension(presetHeight)
    }

    mutating func applyCustomDimensions() {
        guard
            let customWidth = PosterRequest.dimension(from: customWidthText),
            let customHeight = PosterRequest.dimension(from: customHeightText)
        else {
            return
        }

        width = customWidth
        height = customHeight
    }

    var effectiveDimensions: (width: Double, height: Double)? {
        if sizePreset == .custom {
            guard
                let customWidth = PosterRequest.dimension(from: customWidthText),
                let customHeight = PosterRequest.dimension(from: customHeightText)
            else {
                return nil
            }

            return (customWidth, customHeight)
        }

        return (width, height)
    }

    var posterCity: String {
        let explicit = trimmed(displayCity.isEmpty ? city : displayCity)
        if !explicit.isEmpty {
            return explicit
        }

        let firstComponent = trimmed(locationQuery)
            .split(separator: ",")
            .first
            .map(String.init) ?? trimmed(locationQuery)

        return firstComponent.isEmpty ? "Location" : firstComponent
    }

    var posterRegion: String {
        let explicit = trimmed(displayCountry.isEmpty ? country : displayCountry)
        if !explicit.isEmpty {
            return explicit
        }

        let components = trimmed(locationQuery)
            .split(separator: ",")
            .dropFirst()
            .map { trimmed(String($0)) }
            .filter { !$0.isEmpty }

        return components.joined(separator: ", ")
    }

    private func appendIfPresent(_ flag: String, _ value: String, to arguments: inout [String]) {
        let trimmedValue = trimmed(value)
        guard !trimmedValue.isEmpty else { return }
        arguments.append(contentsOf: [flag, trimmedValue])
    }

    private func formattedDimension(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func dimension(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "inches", with: "")
            .replacingOccurrences(of: "inch", with: "")
            .replacingOccurrences(of: "in", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value = Double(normalized), (3.6...48).contains(value) else {
            return nil
        }

        return value
    }
}

enum PosterSizePreset: String, CaseIterable, Identifiable {
    case eightByTen
    case elevenByFourteen
    case twelveBySixteen
    case sixteenByTwenty
    case eighteenByTwentyFour
    case twentyFourByThirtySix
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eightByTen: "8 x 10"
        case .elevenByFourteen: "11 x 14"
        case .twelveBySixteen: "12 x 16"
        case .sixteenByTwenty: "16 x 20"
        case .eighteenByTwentyFour: "18 x 24"
        case .twentyFourByThirtySix: "24 x 36"
        case .custom: "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .eightByTen: "Small"
        case .elevenByFourteen: "Classic"
        case .twelveBySixteen: "Gallery"
        case .sixteenByTwenty: "Frame"
        case .eighteenByTwentyFour: "Large"
        case .twentyFourByThirtySix: "Statement"
        case .custom: "Free size"
        }
    }

    var width: Double? {
        switch self {
        case .eightByTen: 8
        case .elevenByFourteen: 11
        case .twelveBySixteen: 12
        case .sixteenByTwenty: 16
        case .eighteenByTwentyFour: 18
        case .twentyFourByThirtySix: 24
        case .custom: nil
        }
    }

    var height: Double? {
        switch self {
        case .eightByTen: 10
        case .elevenByFourteen: 14
        case .twelveBySixteen: 16
        case .sixteenByTwenty: 20
        case .eighteenByTwentyFour: 24
        case .twentyFourByThirtySix: 36
        case .custom: nil
        }
    }

    var helpText: String {
        switch self {
        case .custom:
            "Enter a custom poster width and height in inches."
        default:
            "Use the popular \(title) inch poster size."
        }
    }
}

enum PosterFormat: String, CaseIterable, Identifiable {
    case png
    case svg
    case pdf

    var id: String { rawValue }
}
