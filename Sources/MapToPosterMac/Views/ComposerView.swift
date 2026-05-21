import SwiftUI

struct ComposerView: View {
    @Binding var request: PosterRequest
    let themes: [PosterTheme]
    let canGenerate: Bool
    let isGenerating: Bool
    let generate: () -> Void
    let reset: () -> Void

    @State private var isLookingUpZip = false
    @State private var zipLookupMessage: String?
    private let zipLookupService = ZipLookupService()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Poster", systemImage: "map")

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        FieldLabel("ZIP Code")
                        HStack(spacing: 8) {
                            TextField("Optional ZIP lookup", text: $request.zipCode)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("ZIP code lookup")
                                .onSubmit(lookupZipCode)

                            Button {
                                lookupZipCode()
                            } label: {
                                if isLookingUpZip {
                                    Label("Looking Up", systemImage: "hourglass")
                                } else {
                                    Label("Use ZIP", systemImage: "magnifyingglass")
                                }
                            }
                            .labelStyle(.titleAndIcon)
                            .controlSize(.regular)
                            .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                            .buttonLift()
                            .help("Look up the ZIP code and fill Location with the matching city when one is found.")
                            .disabled(isLookingUpZip || request.zipCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    if let zipLookupMessage {
                        GridRow {
                            Text("")
                            Text(zipLookupMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        FieldLabel("Location")
                        TextField("ZIP, city/state, address, or landmark", text: $request.locationQuery)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Location")
                            .accessibilityHint("Enter a ZIP code, city and state, address, landmark, or city and country.")
                    }
                    GridRow {
                        FieldLabel("Theme")
                        Picker("Theme", selection: $request.themeSlug) {
                            ForEach(themes) { theme in
                                Text(theme.displayName).tag(theme.slug)
                            }
                        }
                        .accessibilityHint("Selects the visual style used by the Python poster generator.")
                    }
                    GridRow {
                        FieldLabel("Distance")
                        HStack(spacing: 8) {
                            ForEach(DistanceOption.allCases) { option in
                                DistanceButton(
                                    option: option,
                                    isSelected: Int(request.distance) == option.meters
                                ) {
                                    request.distance = Double(option.meters)
                                }
                            }
                        }
                    }
                    GridRow {
                        FieldLabel("Size")
                        VStack(alignment: .leading, spacing: 10) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(PosterSizePreset.allCases) { preset in
                                    PosterSizeButton(
                                        preset: preset,
                                        isSelected: request.sizePreset == preset
                                    ) {
                                        request.apply(preset)
                                    }
                                }
                            }

                            if request.sizePreset == .custom {
                                HStack(spacing: 8) {
                                    TextField("Width", text: $request.customWidthText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 92)
                                        .onChange(of: request.customWidthText) {
                                            request.applyCustomDimensions()
                                        }
                                        .accessibilityLabel("Custom poster width in inches")

                                    Text("x")
                                        .foregroundStyle(.secondary)

                                    TextField("Height", text: $request.customHeightText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 92)
                                        .onChange(of: request.customHeightText) {
                                            request.applyCustomDimensions()
                                        }
                                        .accessibilityLabel("Custom poster height in inches")

                                    Text("inches")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if request.effectiveDimensions == nil {
                                    Text("Enter numeric width and height from 3.6 to 48 inches.")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    GridRow {
                        FieldLabel("Format")
                        Picker("Format", selection: $request.format) {
                            ForEach(PosterFormat.allCases) { format in
                                Text(format.rawValue.uppercased()).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .appPanel()

            if let theme = themes.first(where: { $0.slug == request.themeSlug }) {
                ThemeSummary(theme: theme)
            }

            DisclosureGroup {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        FieldLabel("Title")
                        TextField(request.posterCity, text: $request.displayCity)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Poster title")
                    }
                    GridRow {
                        FieldLabel("Subtitle")
                        TextField(request.posterRegion.isEmpty ? "Optional subtitle" : request.posterRegion, text: $request.displayCountry)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Poster subtitle")
                    }
                    GridRow {
                        FieldLabel("Footer")
                        TextField("Optional country label", text: $request.countryLabel)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Country label")
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced labels", systemImage: "textformat")
                    .font(.subheadline.weight(.medium))
            }
            .appPanel()

            HStack(spacing: 10) {
                Button {
                    generate()
                } label: {
                    Label(isGenerating ? "Generating Poster" : "Generate Poster", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .controlSize(.large)
                .buttonLift()
                .help("Create a new poster from the selected location, distance, theme, size, and format.")
                .disabled(!canGenerate || request.effectiveDimensions == nil)

                Button {
                    reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .controlSize(.large)
                .buttonLift()
                .help("Reset the poster form, preview, and run log to their default state.")
            }
        }
        .controlSize(.regular)
    }

    private func lookupZipCode() {
        let zip = request.zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zip.isEmpty else { return }

        isLookingUpZip = true
        zipLookupMessage = nil

        Task {
            do {
                let result = try await zipLookupService.lookup(zipCode: zip)
                await MainActor.run {
                    request.locationQuery = result.locationName
                    request.city = result.locationName
                        .split(separator: ",")
                        .first
                        .map(String.init) ?? result.locationName
                    request.country = ""
                    zipLookupMessage = "Location set to \(result.locationName)."
                    isLookingUpZip = false
                }
            } catch {
                await MainActor.run {
                    request.locationQuery = zip
                    request.city = zip
                    request.country = ""
                    zipLookupMessage = "\(error.localizedDescription) Using ZIP code directly."
                    isLookingUpZip = false
                }
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(AppDesign.inkBlue)
    }
}

private struct FieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 104, alignment: .leading)
    }
}

private enum DistanceOption: CaseIterable, Identifiable {
    case close
    case city
    case metro
    case region

    var id: Int { meters }

    var title: String {
        switch self {
        case .close: "Close"
        case .city: "City"
        case .metro: "Metro"
        case .region: "Region"
        }
    }

    var meters: Int {
        switch self {
        case .close: 4000
        case .city: 8000
        case .metro: 12000
        case .region: 18000
        }
    }

    var helpText: String {
        switch self {
        case .close:
            "Use a tight 4 km radius for downtowns or compact neighborhoods."
        case .city:
            "Use an 8 km radius for a balanced city poster."
        case .metro:
            "Use a 12 km radius for larger urban areas."
        case .region:
            "Use an 18 km radius for wide metro-region posters."
        }
    }
}

private struct DistanceButton: View {
    let option: DistanceOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(option.title)
                    .font(.caption.weight(.semibold))
                Text("\(option.meters / 1000) km")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .frame(width: 70)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : AppDesign.inkBlue)
        .background(isSelected ? AppDesign.clearBlue : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .stroke(isSelected ? AppDesign.clearBlue.opacity(0.55) : AppDesign.panelStroke, lineWidth: 1)
        }
        .buttonLift()
        .help(option.helpText)
        .accessibilityLabel("\(option.title), \(option.meters / 1000) kilometers")
        .accessibilityHint(option.helpText)
    }
}

private struct PosterSizeButton: View {
    let preset: PosterSizePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(preset.title)
                    .font(.caption.weight(.semibold))
                Text(preset.subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .white : AppDesign.inkBlue)
        .background(isSelected ? AppDesign.clearBlue : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .stroke(isSelected ? AppDesign.clearBlue.opacity(0.55) : AppDesign.panelStroke, lineWidth: 1)
        }
        .buttonLift()
        .help(preset.helpText)
        .accessibilityLabel("\(preset.title) poster size")
        .accessibilityHint(preset.helpText)
    }
}

private struct ThemeSummary: View {
    let theme: PosterTheme

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                theme.backgroundColor
                theme.roadColor
                theme.textColor
            }
            .frame(width: 54, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppDesign.inkBlue)
                Text(theme.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .appPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme \(theme.displayName). \(theme.description)")
    }
}
