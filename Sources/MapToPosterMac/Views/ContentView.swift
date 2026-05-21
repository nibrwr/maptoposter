import SwiftUI

struct ContentView: View {
    @StateObject private var themeStore = ThemeStore()
    @State private var request = PosterRequest()
    @State private var generatedPosterURL: URL?
    @State private var logText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var dependencyWarning: String?

    private let generator = PosterGenerator()

    var selectedTheme: PosterTheme? {
        themeStore.themes.first { $0.slug == request.themeSlug }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderView(request: request)

                if let dependencyWarning {
                    DependencyBanner(message: dependencyWarning)
                }

                ComposerView(
                    request: $request,
                    themes: themeStore.themes,
                    canGenerate: request.canGenerate && !isGenerating,
                    isGenerating: isGenerating,
                    generate: generate,
                    reset: reset
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                LogView(logText: logText, isGenerating: isGenerating, errorMessage: errorMessage)
                    .frame(minHeight: 150, idealHeight: 170, maxHeight: 210)
            }
            .padding(22)
            .frame(minWidth: 520, idealWidth: 560, maxWidth: 620)

            PreviewPane(
                posterURL: generatedPosterURL,
                request: request,
                selectedTheme: selectedTheme
            )
            .padding(22)
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            AppWindowBackground()
        }
        .navigationTitle("Map to Poster Generator")
        .onReceive(NotificationCenter.default.publisher(for: .generatePosterRequested)) { _ in
            generate()
        }
        .task {
            dependencyWarning = await generator.dependencyWarning()
        }
    }

    private func generate() {
        guard request.canGenerate, !isGenerating else { return }

        isGenerating = true
        errorMessage = nil
        dependencyWarning = nil
        logText = "Generating \(request.locationQuery)...\n"

        Task {
            do {
                let result = try await generator.generate(request: request) { chunk in
                    logText += chunk
                }

                await MainActor.run {
                    isGenerating = false
                    dependencyWarning = nil
                    generatedPosterURL = result.outputURL
                    if result.exitCode != 0 {
                        errorMessage = "Poster generation exited with status \(result.exitCode)."
                    } else if result.outputURL == nil {
                        errorMessage = "Generation finished, but no new \(request.format.rawValue.uppercased()) file was found in posters/."
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    if error.localizedDescription.contains("Python dependencies") {
                        dependencyWarning = error.localizedDescription
                        errorMessage = nil
                        logText = ""
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func reset() {
        request = PosterRequest()
        generatedPosterURL = nil
        logText = ""
        errorMessage = nil
    }
}

private struct HeaderView: View {
    let request: PosterRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Map to Poster Generator")
                .font(.largeTitle.weight(.semibold))
            Text("Enter a ZIP code or place, choose the poster settings, then generate.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(request.locationQuery.isEmpty ? "No location selected" : request.locationQuery)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppDesign.inkBlue)
                .lineLimit(1)
        }
        .appPanel(prominent: true)
        .accessibilityElement(children: .contain)
    }
}

private struct DependencyBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(AppDesign.clearBlue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 6) {
                Text("Python setup needed")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .appPanel()
        .accessibilityElement(children: .combine)
    }
}
