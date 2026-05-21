import Foundation

enum RepositoryLocator {
    static var repositoryRoot: URL {
        if let configuredPath = ProcessInfo.processInfo.environment["MAPTOPOSTER_ROOT"], !configuredPath.isEmpty {
            return URL(filePath: configuredPath)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app", bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        return URL(filePath: FileManager.default.currentDirectoryPath)
    }
}
