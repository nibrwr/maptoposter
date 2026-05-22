import SwiftUI

struct SidebarView: View {
    let themes: [PosterTheme]
    @Binding var selectedThemeSlug: String
    @Binding var selectedPresetID: CityPreset.ID?
    let onPresetSelected: (CityPreset) -> Void

    var body: some View {
        List(selection: $selectedPresetID) {
            Section("Presets") {
                ForEach(CityPreset.samples) { preset in
                    Button {
                        selectedPresetID = preset.id
                        onPresetSelected(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.city)
                                    .lineLimit(1)
                                Text("\(preset.country) · \(preset.themeSlug)")
                                    .font(AppDesign.metadataFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .tag(preset.id)
                }
            }

            Section("Themes") {
                ForEach(themes) { theme in
                    Button {
                        selectedThemeSlug = theme.slug
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(theme.roadColor)
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.displayName)
                                    .lineLimit(1)
                                Text(theme.slug)
                                    .font(AppDesign.metadataFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .accessibilityLabel("Poster presets and themes")
    }
}
