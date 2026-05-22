import AppKit
import SwiftUI

struct ComposerView: View {
    @Binding var request: PosterRequest
    let outputDirectory: URL
    let themes: [PosterTheme]
    let canGenerate: Bool
    let isGenerating: Bool
    let chooseOutputDirectory: () -> Void
    let resetOutputDirectory: () -> Void
    let generate: () -> Void
    let reset: () -> Void

    @State private var isLookingUpZip = false
    @State private var zipLookupMessage: String?
    @State private var isAdvancedOptionsExpanded = false
    private let zipLookupService = ZipLookupService()

    private var selectedTheme: PosterTheme? {
        themes.first { $0.slug == request.themeSlug }
    }

    private var locationBinding: Binding<String> {
        Binding(
            get: { request.locationQuery },
            set: { request.updateLocationQuery($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Poster", systemImage: "map")

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        FieldLabel("Preset")
                        HStack(spacing: 8) {
                            ForEach(GenerationPreset.allCases) { preset in
                                GenerationPresetButton(
                                    preset: preset,
                                    isSelected: Int(request.distance) == preset.distanceMeters
                                        && request.sizePreset == preset.sizePreset
                                ) {
                                    request.apply(preset)
                                }
                            }
                        }
                    }
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
                                .font(AppDesign.metadataFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        Text("")
                        Label("ZIP lookup and poster generation use OpenStreetMap/Nominatim to resolve the location.", systemImage: "lock.shield")
                            .font(AppDesign.metadataFont)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(2)
                            .accessibilityLabel("Privacy note. ZIP lookup and poster generation use OpenStreetMap and Nominatim to resolve the location.")
                    }
                    GridRow {
                        FieldLabel("Location")
                        TextField("ZIP, city/state, address, or landmark", text: locationBinding)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Location")
                            .accessibilityHint("Enter a ZIP code, city and state, address, landmark, or city and country.")
                    }
                    GridRow {
                        FieldLabel("Theme")
                        HStack(alignment: .center, spacing: 12) {
                            Picker("Theme", selection: $request.themeSlug) {
                                ForEach(themes) { theme in
                                    Text(theme.displayName).tag(theme.slug)
                                }
                            }
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 240, alignment: .leading)
                            .accessibilityHint("Selects the visual style used by the Python poster generator.")

                            if let selectedTheme {
                                ThemeInlineSummary(theme: selectedTheme)
                            } else {
                                Text("Choose a poster color style.")
                                    .font(AppDesign.metadataFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                                columns: Array(repeating: GridItem(.fixed(70), spacing: 8), count: 4),
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
                                        .frame(minWidth: 92, idealWidth: 110, maxWidth: 130)
                                        .onChange(of: request.customWidthText) {
                                            request.applyCustomDimensions()
                                        }
                                        .accessibilityLabel("Custom poster width in inches")

                                    Text("x")
                                        .foregroundStyle(.secondary)

                                    TextField("Height", text: $request.customHeightText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(minWidth: 92, idealWidth: 110, maxWidth: 130)
                                        .onChange(of: request.customHeightText) {
                                            request.applyCustomDimensions()
                                        }
                                        .accessibilityLabel("Custom poster height in inches")

                                    Text("inches")
                                        .font(AppDesign.metadataFont)
                                        .foregroundStyle(.secondary)
                                }

                                if request.effectiveDimensions == nil {
                                    Text("Enter numeric width and height from 3.6 to 48 inches.")
                                        .font(AppDesign.metadataFont)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    GridRow {
                        FieldLabel("Format")
                        HStack(spacing: 12) {
                            Picker("Format", selection: $request.format) {
                                ForEach(PosterFormat.allCases) { format in
                                    Text(format.rawValue.uppercased()).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                            .accessibilityHint("Choose whether to save the poster as a PNG, SVG, or PDF.")

                            Toggle(isOn: $request.cacheOnly) {
                                Label("Cache only", systemImage: "externaldrive.badge.checkmark")
                            }
                            .toggleStyle(.checkbox)
                            .help("Generate only from already cached map data. No new OpenStreetMap requests are made.")
                            .accessibilityHint("When enabled, generation will fail if the selected location has not already been cached.")
                        }
                    }
                    GridRow {
                        FieldLabel("Save to")
                        HStack(spacing: 8) {
                            Label(outputDirectory.path(percentEncoded: false), systemImage: "folder")
                                .font(AppDesign.metadataFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .accessibilityLabel("Output folder \(outputDirectory.path(percentEncoded: false))")

                            Button {
                                chooseOutputDirectory()
                            } label: {
                                Label("Choose", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                            .buttonLift()
                            .help("Choose the folder where generated posters are saved.")

                            Button {
                                resetOutputDirectory()
                            } label: {
                                Label("Default", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                            .buttonLift()
                            .help("Save generated posters to the app's managed poster library folder.")
                        }
                    }
                }
            }
            .appPanel()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        isAdvancedOptionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(AppDesign.metadataFont.weight(.semibold))
                            .rotationEffect(.degrees(isAdvancedOptionsExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)

                        Label("Advanced options", systemImage: "slider.horizontal.3")
                            .font(AppDesign.formLabelFont.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isAdvancedOptionsExpanded ? "Hide advanced poster options." : "Show advanced poster options.")
                .accessibilityLabel("Advanced options")
                .accessibilityValue(isAdvancedOptionsExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows or hides detail, inset, and label controls.")

                if isAdvancedOptionsExpanded {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            FieldLabel("Detail")
                            HStack(spacing: 12) {
                                Picker("Detail", selection: $request.detailLevel) {
                                    ForEach(PosterDetailLevel.allCases) { level in
                                        Text(level.title).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 190)
                                .help(request.detailLevel.helpText)
                                .accessibilityHint(request.detailLevel.helpText)

                                Toggle("Enhance sparse maps", isOn: $request.enhanceSparseMaps)
                                    .toggleStyle(.checkbox)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .help("Automatically make suburban and rural posters more expressive with stronger streets, feature layers, and map texture.")
                                    .accessibilityHint("Automatically improves sparse suburban and rural maps.")
                            }
                        }
                        GridRow {
                            FieldLabel("Inset")
                            Picker("Inset", selection: $request.insetMode) {
                                ForEach(PosterInsetMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 250)
                            .help(request.insetMode.helpText)
                            .accessibilityHint(request.insetMode.helpText)
                        }
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
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                .tint(AppDesign.actionBlue)
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
                    request.updateLocationQuery(result.locationName)
                    zipLookupMessage = "Location set to \(result.locationName)."
                    isLookingUpZip = false
                }
            } catch {
                await MainActor.run {
                    request.updateLocationQuery(zip)
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
            .font(AppDesign.panelTitleFont)
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
            .font(AppDesign.formLabelFont.weight(.medium))
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
        Button {
            action()
            clearTransientButtonFocus()
        } label: {
            VStack(spacing: 2) {
                Text(option.title)
                    .font(AppDesign.controlTitleFont)
                Text("\(option.meters / 1000) km")
                    .font(AppDesign.controlDetailFont)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .frame(width: 70)
            .frame(minHeight: 48)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isSelected ? .white : AppDesign.inkBlue)
        .background(isSelected ? AppDesign.clearBlue : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .stroke(isSelected ? AppDesign.clearBlue.opacity(0.55) : AppDesign.panelStroke, lineWidth: 1)
        }
        .buttonLift()
        .help(option.helpText)
        .accessibilityLabel("\(option.title), \(option.meters / 1000) kilometers")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(option.helpText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct GenerationPresetButton: View {
    let preset: GenerationPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            clearTransientButtonFocus()
        } label: {
            VStack(spacing: 2) {
                Text(preset.title)
                    .font(AppDesign.controlTitleFont)
                Text(preset.subtitle)
                    .font(AppDesign.controlDetailFont)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .frame(width: 88)
            .frame(minHeight: 48)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isSelected ? .white : AppDesign.inkBlue)
        .background(isSelected ? AppDesign.clearBlue : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .stroke(isSelected ? AppDesign.clearBlue.opacity(0.55) : AppDesign.panelStroke, lineWidth: 1)
        }
        .buttonLift()
        .help(preset.helpText)
        .accessibilityLabel("\(preset.title) generation preset")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(preset.helpText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PosterSizeButton: View {
    let preset: PosterSizePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            clearTransientButtonFocus()
        } label: {
            VStack(spacing: 2) {
                Text(preset.title)
                    .font(AppDesign.controlTitleFont)
                Text(preset.subtitle)
                    .font(AppDesign.controlDetailFont)
                    .foregroundStyle(isSelected ? .white.opacity(0.88) : .secondary)
            }
            .frame(width: 70)
            .frame(minHeight: 48)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .foregroundStyle(isSelected ? .white : AppDesign.inkBlue)
        .background(isSelected ? AppDesign.clearBlue : .white.opacity(0.62), in: RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .stroke(isSelected ? AppDesign.clearBlue.opacity(0.55) : AppDesign.panelStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
        .buttonLift()
        .help(preset.helpText)
        .accessibilityLabel("\(preset.title) poster size")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(preset.helpText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThemeInlineSummary: View {
    let theme: PosterTheme

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                theme.backgroundColor
                theme.roadColor
                theme.textColor
            }
            .frame(width: 42, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(AppDesign.metadataFont.weight(.semibold))
                    .foregroundStyle(AppDesign.inkBlue)
                Text(theme.description)
                    .font(AppDesign.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme \(theme.displayName). \(theme.description)")
    }
}

private func clearTransientButtonFocus() {
    DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
