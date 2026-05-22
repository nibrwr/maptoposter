import SwiftUI

struct PosterLibrarySheet: View {
    let posters: [GeneratedPoster]
    let useSettings: (GeneratedPoster) -> Void
    let open: (GeneratedPoster) -> Void
    let reveal: (GeneratedPoster) -> Void
    let export: (GeneratedPoster) -> Void
    let delete: (GeneratedPoster) -> Void
    let revealAppSupport: () -> Void
    let clearCache: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingCacheClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Poster Library", systemImage: "rectangle.stack")
                    .font(.title3)
                    .foregroundStyle(AppDesign.inkBlue)

                Spacer()

                Button(role: .destructive) {
                    isConfirmingCacheClear = true
                } label: {
                    Label("Clear Cache", systemImage: "externaldrive.badge.minus")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .buttonLift()
                .help("Remove locally cached map data. Generated posters and logs are kept.")

                Button {
                    revealAppSupport()
                } label: {
                    Label("Show Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .buttonLift()
                .help("Reveal the local poster library folder in Finder.")

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            if posters.isEmpty {
                ContentUnavailableView(
                    "No Posters Yet",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Generated posters will appear here after the first successful run.")
                )
                .frame(minWidth: 760, minHeight: 360)
                .accessibilityLabel("No generated posters yet")
            } else {
                List(posters) { poster in
                    PosterLibraryRow(
                        poster: poster,
                        useSettings: { useSettings(poster) },
                        open: { open(poster) },
                        reveal: { reveal(poster) },
                        export: { export(poster) },
                        delete: { delete(poster) }
                    )
                }
                .frame(minWidth: 820, minHeight: 420)
                .accessibilityLabel("Generated poster library")
            }
        }
        .padding(20)
        .background(AppWindowBackground())
        .confirmationDialog(
            "Clear cached map data?",
            isPresented: $isConfirmingCacheClear,
            titleVisibility: .visible
        ) {
            Button("Clear Cache", role: .destructive) {
                clearCache()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generated posters and logs are kept, but Cache only generation may fail until places are generated again.")
        }
    }
}

private struct PosterLibraryRow: View {
    let poster: GeneratedPoster
    let useSettings: () -> Void
    let open: () -> Void
    let reveal: () -> Void
    let export: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(poster.title)
                    .font(AppDesign.panelTitleFont)
                    .lineLimit(1)

                Text(poster.subtitle)
                    .font(AppDesign.metadataFont)
                    .foregroundStyle(.secondary)

                Text(poster.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: useSettings) {
                    Label("Use Settings", systemImage: "slider.horizontal.3")
                }
                .help("Load this poster's saved settings into the generator.")

                Button(action: open) {
                    Label("Open", systemImage: "arrow.up.right.square")
                }
                .help("Open this poster in the default app.")

                Button(action: reveal) {
                    Label("Reveal", systemImage: "folder")
                }
                .help("Reveal this poster in Finder.")

                Button(action: export) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Save a copy of this poster somewhere else.")

                Button(role: .destructive, action: delete) {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this generated poster and its local metadata.")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if poster.url.pathExtension.lowercased() == "png", let image = NSImage(contentsOf: poster.url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: AppDesign.compactRadius, style: .continuous)
                .fill(AppDesign.mistBlue.opacity(0.25))
                .frame(width: 56, height: 72)
                .overlay {
                    Image(systemName: "doc")
                        .foregroundStyle(AppDesign.clearBlue)
                }
                .accessibilityHidden(true)
        }
    }
}
