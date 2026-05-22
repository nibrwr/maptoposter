import Foundation

struct PosterMetadata: Codable, Equatable {
    var schemaVersion = 1
    var generatedAt: Date
    var request: PosterRequest
    var outputPath: String
    var logPath: String?
}

struct GeneratedPoster: Identifiable, Equatable {
    let id: URL
    let url: URL
    let metadata: PosterMetadata?
    let modifiedAt: Date
    let fileSize: Int64

    var title: String {
        metadata?.request.posterCity ?? url.deletingPathExtension().lastPathComponent
    }

    var subtitle: String {
        let format = url.pathExtension.uppercased()
        if let metadata {
            let width = metadata.request.effectiveDimensions?.width ?? metadata.request.width
            let height = metadata.request.effectiveDimensions?.height ?? metadata.request.height
            return "\(format) · \(width.formatted(.number.precision(.fractionLength(0...1)))) x \(height.formatted(.number.precision(.fractionLength(0...1))))"
        }
        return format
    }

    var logURL: URL? {
        guard let logPath = metadata?.logPath else { return nil }
        let trimmedPath = logPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        if trimmedPath.hasPrefix("/") {
            return URL(filePath: trimmedPath)
        }
        return AppStorageLocations.logsDirectory.appending(path: trimmedPath)
    }
}
