import Foundation
import Security

enum AppStorageLocations {
    private static let bundleName = "Map to Poster Generator"

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        return base.appending(path: bundleName, directoryHint: .isDirectory)
    }

    static var postersDirectory: URL {
        appSupportDirectory.appending(path: "Generated Posters", directoryHint: .isDirectory)
    }

    static var cacheDirectory: URL {
        appSupportDirectory.appending(path: "Cache", directoryHint: .isDirectory)
    }

    static var logsDirectory: URL {
        appSupportDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }

    static var matplotlibDirectory: URL {
        cacheDirectory.appending(path: "Matplotlib", directoryHint: .isDirectory)
    }

    static var cacheSecretURL: URL {
        appSupportDirectory.appending(path: ".cache_secret")
    }

    static func prepare() throws {
        try createPrivateDirectory(appSupportDirectory)
        try createPrivateDirectory(postersDirectory)
        try createPrivateDirectory(cacheDirectory)
        try createPrivateDirectory(logsDirectory)
        try createPrivateDirectory(matplotlibDirectory)
        _ = try cacheSecret()
    }

    static func cacheSecret() throws -> String {
        if FileManager.default.fileExists(atPath: cacheSecretURL.path) {
            return try String(contentsOf: cacheSecretURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }

        let secret = Data(bytes).base64EncodedString()
        try secret.write(to: cacheSecretURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheSecretURL.path)
        return secret
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.compactMap { item -> Int64? in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            return Int64(values.fileSize ?? 0)
        }
        .reduce(0, +)
    }

    static func removeContents(of directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in urls {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func createPrivateDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
}
