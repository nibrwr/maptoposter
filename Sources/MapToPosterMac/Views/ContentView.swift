import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var posterLibrary = PosterLibrary()
    @State private var request = PosterRequest()
    @State private var generatedPosterURL: URL?
    @State private var logText = ""
    @State private var fullLogURL: URL?
    @State private var isGenerating = false
    @State private var generationProgress = 0.0
    @State private var statusText = "Ready"
    @State private var errorMessage: String?
    @State private var dependencyWarning: String?
    @State private var isShowingRunLog = false
    @State private var isShowingLibrary = false
    @State private var outputDirectory = AppStorageLocations.postersDirectory
    @State private var generationTask: Task<Void, Never>?

    private let generator = PosterGenerator()
    private let preflightService = NetworkPreflightService()
    private let maxVisibleLogCharacters = 24_000

    var selectedTheme: PosterTheme? {
        themeStore.themes.first { $0.slug == request.themeSlug }
    }

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeaderView()

                    if let dependencyWarning {
                        DependencyBanner(message: dependencyWarning)
                    }

                    ComposerView(
                        request: $request,
                        outputDirectory: outputDirectory,
                        themes: themeStore.themes,
                        canGenerate: request.canGenerate && !isGenerating,
                        isGenerating: isGenerating,
                        chooseOutputDirectory: chooseOutputDirectory,
                        resetOutputDirectory: resetOutputDirectory,
                        generate: generate,
                        reset: reset
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    GenerationStatusView(
                        statusText: statusText,
                        progress: generationProgress,
                        isGenerating: isGenerating,
                        errorMessage: errorMessage,
                        cancel: cancelGeneration,
                        showRunLog: { isShowingRunLog = true }
                    )
                }
                .padding(22)
            }
            .defaultScrollAnchor(.top)
            .frame(minWidth: 520, idealWidth: 560, maxWidth: 620)

            PreviewPane(
                posterURL: generatedPosterURL,
                request: request,
                selectedTheme: selectedTheme,
                openPoster: openCurrentPoster,
                revealPoster: revealCurrentPoster,
                exportPoster: exportCurrentPoster,
                openLibrary: { isShowingLibrary = true }
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
        .sheet(isPresented: $isShowingRunLog) {
            RunLogSheet(logText: logText, logURL: fullLogURL, isGenerating: isGenerating, errorMessage: errorMessage)
        }
        .sheet(isPresented: $isShowingLibrary) {
            PosterLibrarySheet(
                posters: posterLibrary.posters,
                useSettings: useSettings,
                open: posterLibrary.open,
                reveal: posterLibrary.reveal,
                export: exportPoster,
                delete: deletePoster,
                revealAppSupport: posterLibrary.revealAppSupport,
                clearCache: clearCache
            )
        }
        .task {
            dependencyWarning = await generator.dependencyWarning()
            posterLibrary.reload()
        }
    }

    private func generate() {
        guard request.canGenerate, !isGenerating else { return }

        isGenerating = true
        generationProgress = 0.04
        statusText = "Starting"
        errorMessage = nil
        dependencyWarning = nil
        fullLogURL = nil
        logText = "Generating \(request.locationQuery)...\n"
        let selectedOutputDirectory = outputDirectory

        generationTask = Task {
            do {
                if !request.cacheOnly {
                    await MainActor.run {
                        generationProgress = 0.02
                        statusText = "Checking map services"
                    }
                    try await preflightService.checkReachability()
                }

                let result = try await generator.generate(
                    request: request,
                    outputDirectory: selectedOutputDirectory,
                    onOutput: { chunk in
                        appendVisibleLog(chunk)
                    },
                    onProgress: { event in
                        generationProgress = max(generationProgress, min(max(event.progress, 0), 1))
                        statusText = event.status
                    }
                )

                await MainActor.run {
                    isGenerating = false
                    generationTask = nil
                    dependencyWarning = nil
                    generatedPosterURL = result.outputURL
                    fullLogURL = result.logURL
                    if result.exitCode != 0 {
                        errorMessage = "Poster generation exited with status \(result.exitCode)."
                        statusText = "Failed"
                    } else if result.outputURL == nil {
                        errorMessage = "Generation finished, but no new \(request.format.rawValue.uppercased()) file was found in posters/."
                        statusText = "Finished with warning"
                        generationProgress = 1.0
                    } else {
                        statusText = "Complete"
                        generationProgress = 1.0
                        do {
                            try posterLibrary.writeMetadata(request: request, outputURL: result.outputURL!, logURL: result.logURL)
                        } catch {
                            errorMessage = "Poster was created, but its library metadata could not be saved."
                        }
                        posterLibrary.reload()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isGenerating = false
                    generationTask = nil
                    errorMessage = "Poster generation was cancelled."
                    statusText = "Cancelled"
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    generationTask = nil
                    if error.localizedDescription.contains("Python dependencies") {
                        dependencyWarning = error.localizedDescription
                        errorMessage = nil
                        logText = ""
                        statusText = "Setup needed"
                        generationProgress = 0.0
                    } else {
                        errorMessage = error.localizedDescription
                        statusText = "Failed"
                    }
                }
            }
        }
    }

    private func cancelGeneration() {
        generator.cancel()
        generationTask?.cancel()
    }

    private func appendVisibleLog(_ chunk: String) {
        logText += chunk
        if logText.count > maxVisibleLogCharacters {
            logText = "...\n" + logText.suffix(maxVisibleLogCharacters)
        }
    }

    private func reset() {
        if isGenerating {
            cancelGeneration()
        }
        request = PosterRequest()
        generatedPosterURL = nil
        logText = ""
        fullLogURL = nil
        errorMessage = nil
        generationProgress = 0.0
        statusText = "Ready"
    }

    private func openCurrentPoster() {
        guard let poster = posterLibrary.posters.first(where: { $0.url == generatedPosterURL }) else {
            if let generatedPosterURL {
                NSWorkspace.shared.open(generatedPosterURL)
            }
            return
        }
        posterLibrary.open(poster)
    }

    private func revealCurrentPoster() {
        guard let generatedPosterURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([generatedPosterURL])
    }

    private func exportCurrentPoster() {
        guard let generatedPosterURL else { return }
        do {
            try posterLibrary.export(url: generatedPosterURL)
        } catch {
            errorMessage = "Could not export poster: \(error.localizedDescription)"
        }
    }

    private func exportPoster(_ poster: GeneratedPoster) {
        do {
            try posterLibrary.export(poster)
        } catch {
            errorMessage = "Could not export poster: \(error.localizedDescription)"
        }
    }

    private func deletePoster(_ poster: GeneratedPoster) {
        do {
            try posterLibrary.delete(poster)
            if generatedPosterURL == poster.url {
                generatedPosterURL = nil
            }
        } catch {
            errorMessage = "Could not delete poster: \(error.localizedDescription)"
        }
    }

    private func useSettings(from poster: GeneratedPoster) {
        guard let copiedRequest = posterLibrary.duplicateRequest(from: poster) else { return }
        request = copiedRequest
        isShowingLibrary = false
        statusText = "Ready"
        generationProgress = 0.0
        errorMessage = nil
    }

    private func clearCache() {
        do {
            try AppStorageLocations.removeContents(of: AppStorageLocations.cacheDirectory)
            try AppStorageLocations.prepare()
            statusText = "Cache cleared"
            generationProgress = 0.0
            errorMessage = nil
        } catch {
            errorMessage = "Could not clear cache: \(error.localizedDescription)"
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputDirectory
        panel.title = "Choose Poster Save Location"
        panel.message = "Generated posters will be saved directly to this folder."
        panel.prompt = "Choose"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url
        statusText = "Save location selected"
        errorMessage = nil
    }

    private func resetOutputDirectory() {
        outputDirectory = AppStorageLocations.postersDirectory
        statusText = "Using app poster library"
        errorMessage = nil
    }
}

private struct GenerationStatusView: View {
    let statusText: String
    let progress: Double
    let isGenerating: Bool
    let errorMessage: String?
    let cancel: () -> Void
    let showRunLog: () -> Void

    private var displayProgress: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Status", systemImage: errorMessage == nil ? "speedometer" : "exclamationmark.triangle")
                    .font(AppDesign.panelTitleFont)
                    .foregroundStyle(errorMessage == nil ? AppDesign.inkBlue : .red)

                Spacer()

                Text("\(displayProgress)%")
                    .font(AppDesign.statusValueFont)
                    .foregroundStyle(errorMessage == nil ? AppDesign.inkBlue : .red)
                    .accessibilityLabel("Generation progress \(displayProgress) percent")
            }

            ProgressView(value: progress, total: 1)
                .controlSize(.large)
                .accessibilityLabel("Generation status")
                .accessibilityValue("\(statusText), \(displayProgress) percent")

            HStack(spacing: 10) {
                Text(errorMessage ?? statusText)
                    .font(.callout)
                    .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    .lineLimit(2)

                Spacer()

                if isGenerating {
                    Button(role: .cancel) {
                        cancel()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                    .buttonLift()
                    .help("Cancel the current poster generation.")
                }

                Button {
                    showRunLog()
                } label: {
                    Label("Run Log", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: AppDesign.compactRadius))
                .buttonLift()
                .help("Open the detailed generation run log.")
            }
        }
        .appPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Generation status")
        .accessibilityValue("\(errorMessage ?? statusText), \(displayProgress) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct RunLogSheet: View {
    let logText: String
    let logURL: URL?
    let isGenerating: Bool
    let errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Run Log", systemImage: "terminal")
                    .font(.title3)
                    .foregroundStyle(AppDesign.inkBlue)

                Spacer()

                Button {
                    copyRedactedLog()
                } label: {
                    Label("Copy Redacted Log", systemImage: "doc.on.doc")
                }
                .help("Copy the redacted run log shown in this window.")

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            LogView(logText: logText, isGenerating: isGenerating, errorMessage: errorMessage)
                .frame(minWidth: 620, minHeight: 360)

            if let logURL {
                Text("Redacted local log: \(logURL.path)")
                    .font(AppDesign.metadataFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .background(AppWindowBackground())
    }

    private func copyRedactedLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Map to Poster Generator")
                .font(AppDesign.windowTitleFont)
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
                    .font(AppDesign.panelTitleFont)
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
