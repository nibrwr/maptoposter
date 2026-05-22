import Foundation

struct PosterRequest: Codable, Equatable {
    var zipCode: String = ""
    var locationQuery: String = "Norman, OK"
    var city: String = "Norman"
    var country: String = "OK"
    var displayCity: String = ""
    var displayCountry: String = ""
    var countryLabel: String = ""
    var themeSlug: String = "sunset"
    var distance: Double = 8000
    var sizePreset: PosterSizePreset = .twelveBySixteen
    var customWidthText: String = "12"
    var customHeightText: String = "16"
    var width: Double = 12
    var height: Double = 16
    var format: PosterFormat = .png
    var cacheOnly: Bool = false
    var enhanceSparseMaps: Bool = true
    var detailLevel: PosterDetailLevel = .auto
    var insetMode: PosterInsetMode = .auto
    var timeoutSeconds: TimeInterval = 240

    var canGenerate: Bool {
        !locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && effectiveDimensions != nil
    }

    func commandArguments(outputURL: URL? = nil) -> [String] {
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

        if let outputURL {
            arguments.append(contentsOf: ["--output", outputURL.path])
        }

        if cacheOnly {
            arguments.append("--cache-only")
        }

        arguments.append(contentsOf: ["--detail-level", detailLevel.rawValue])
        arguments.append(contentsOf: ["--inset", insetMode.rawValue])

        if !enhanceSparseMaps {
            arguments.append("--no-enhance-sparse")
        }

        appendIfPresent("--display-city", displayCity, to: &arguments)
        appendIfPresent("--display-country", displayCountry, to: &arguments)
        appendIfPresent("--country-label", countryLabel, to: &arguments)

        return arguments
    }

    func generatedOutputURL(in repositoryRoot: URL, date: Date = Date()) -> URL {
        generatedOutputURL(inPostersDirectory: repositoryRoot.appending(path: "posters"), date: date)
    }

    func generatedOutputURL(inPostersDirectory postersDirectory: URL, date: Date = Date()) -> URL {
        let timestamp = Self.outputTimestampFormatter.string(from: date)
        let citySlug = Self.slug(from: posterCity)
        let filename = "\(citySlug)_\(themeSlug)_\(timestamp).\(format.rawValue)"
        return postersDirectory.appending(path: filename)
    }

    mutating func apply(_ preset: CityPreset) {
        zipCode = ""
        displayCity = ""
        displayCountry = ""
        countryLabel = ""
        locationQuery = preset.locationQuery
        city = preset.city
        country = preset.country
        themeSlug = preset.themeSlug
        distance = Double(preset.distance)
    }

    mutating func updateLocationQuery(_ value: String, clearAdvancedLabels: Bool = true) {
        locationQuery = value
        if clearAdvancedLabels {
            displayCity = ""
            displayCountry = ""
            countryLabel = ""
        }

        let labels = Self.labels(from: value)
        city = labels.city
        country = labels.region
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

    mutating func apply(_ preset: GenerationPreset) {
        distance = Double(preset.distanceMeters)
        apply(preset.sizePreset)
        if format == .svg || format == .pdf {
            return
        }
        format = preset.format
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
        let explicitDisplayCity = trimmed(displayCity)
        if !explicitDisplayCity.isEmpty {
            return explicitDisplayCity
        }

        let firstComponent = Self.labels(from: locationQuery).city

        return firstComponent.isEmpty ? "Location" : firstComponent
    }

    var posterRegion: String {
        let explicitDisplayCountry = trimmed(displayCountry)
        if !explicitDisplayCountry.isEmpty {
            return explicitDisplayCountry
        }

        let region = Self.labels(from: locationQuery).region

        if !region.isEmpty {
            return region
        }

        return trimmed(country)
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

    private static func labels(from locationQuery: String) -> (city: String, region: String) {
        let components = locationQuery
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let city = components.first else {
            return (locationQuery.trimmingCharacters(in: .whitespacesAndNewlines), "")
        }

        return (city, components.dropFirst().joined(separator: ", "))
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

    private static func slug(from text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let collapsed = String(scalars)
            .split(separator: "_")
            .joined(separator: "_")
        return collapsed.isEmpty ? "location" : collapsed
    }

    private static let outputTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter
    }()
}

enum PosterSizePreset: String, CaseIterable, Identifiable, Codable {
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

enum PosterFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case svg
    case pdf

    var id: String { rawValue }
}

enum PosterDetailLevel: String, CaseIterable, Identifiable, Codable {
    case auto
    case clean
    case rich

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .clean: "Clean"
        case .rich: "Rich"
        }
    }

    var helpText: String {
        switch self {
        case .auto:
            "Adapt street weight, feature layers, and texture to the selected location."
        case .clean:
            "Keep the poster minimal with fewer sparse-map enhancements."
        case .rich:
            "Add stronger street visibility, more map texture, and richer feature emphasis."
        }
    }
}

enum PosterInsetMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case on
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto inset"
        case .on: "Inset on"
        case .off: "Inset off"
        }
    }

    var helpText: String {
        switch self {
        case .auto:
            "Show a town-detail inset only when the map area is sparse."
        case .on:
            "Always include a small town-detail inset."
        case .off:
            "Do not include a town-detail inset."
        }
    }
}

enum GenerationPreset: String, CaseIterable, Identifiable {
    case quickGift
    case cityGallery
    case framedPrint
    case statement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickGift: "Gift"
        case .cityGallery: "Gallery"
        case .framedPrint: "Frame"
        case .statement: "Statement"
        }
    }

    var subtitle: String {
        switch self {
        case .quickGift: "8 x 10, close"
        case .cityGallery: "12 x 16, city"
        case .framedPrint: "16 x 20, metro"
        case .statement: "24 x 36, region"
        }
    }

    var distanceMeters: Int {
        switch self {
        case .quickGift: 4_000
        case .cityGallery: 8_000
        case .framedPrint: 12_000
        case .statement: 18_000
        }
    }

    var sizePreset: PosterSizePreset {
        switch self {
        case .quickGift: .eightByTen
        case .cityGallery: .twelveBySixteen
        case .framedPrint: .sixteenByTwenty
        case .statement: .twentyFourByThirtySix
        }
    }

    var format: PosterFormat { .png }

    var helpText: String {
        "Apply \(subtitle) settings."
    }
}
