import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PosterLibrary: ObservableObject {
    @Published private(set) var posters: [GeneratedPoster] = []

    private let postersDirectory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(postersDirectory: URL = AppStorageLocations.postersDirectory) {
        self.postersDirectory = postersDirectory
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func reload() {
        do {
            try AppStorageLocations.prepare()
            let urls = try FileManager.default.contentsOfDirectory(
                at: postersDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            posters = urls
                .filter { ["png", "svg", "pdf"].contains($0.pathExtension.lowercased()) }
                .compactMap { url in
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
                    guard values?.isRegularFile == true else { return nil }
                    return GeneratedPoster(
                        id: url,
                        url: url,
                        metadata: metadata(for: url),
                        modifiedAt: values?.contentModificationDate ?? .distantPast,
                        fileSize: Int64(values?.fileSize ?? 0)
                    )
                }
                .sorted { $0.modifiedAt > $1.modifiedAt }
        } catch {
            posters = []
        }
    }

    func writeMetadata(request: PosterRequest, outputURL: URL, logURL: URL?) throws {
        let metadata = PosterMetadata(
            generatedAt: Date(),
            request: request,
            outputPath: outputURL.lastPathComponent,
            logPath: logURL?.lastPathComponent
        )
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL(for: outputURL), options: [.atomic])
    }

    func duplicateRequest(from poster: GeneratedPoster) -> PosterRequest? {
        poster.metadata?.request
    }

    func open(_ poster: GeneratedPoster) {
        NSWorkspace.shared.open(poster.url)
    }

    func reveal(_ poster: GeneratedPoster) {
        NSWorkspace.shared.activateFileViewerSelecting([poster.url])
    }

    func revealAppSupport() {
        NSWorkspace.shared.activateFileViewerSelecting([AppStorageLocations.appSupportDirectory])
    }

    func delete(_ poster: GeneratedPoster) throws {
        try FileManager.default.removeItem(at: poster.url)
        try? FileManager.default.removeItem(at: metadataURL(for: poster.url))
        reload()
    }

    func export(_ poster: GeneratedPoster) throws {
        try export(url: poster.url)
    }

    func export(url: URL) throws {
        let panel = NSSavePanel()
        if let contentType = UTType(filenameExtension: url.pathExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        panel.title = "Export Poster"
        panel.message = "Choose where to save a copy of the generated poster."

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
    }

    private func metadata(for posterURL: URL) -> PosterMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: posterURL)) else {
            return nil
        }
        return try? decoder.decode(PosterMetadata.self, from: data)
    }

    private func metadataURL(for posterURL: URL) -> URL {
        posterURL.deletingPathExtension().appendingPathExtension("json")
    }
}
