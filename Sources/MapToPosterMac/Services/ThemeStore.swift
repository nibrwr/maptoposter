import Foundation

final class ThemeStore: ObservableObject {
    @Published private(set) var themes: [PosterTheme] = []

    private let repositoryRoot: URL

    init(repositoryRoot: URL = RepositoryLocator.repositoryRoot) {
        self.repositoryRoot = repositoryRoot
        reload()
    }

    func reload() {
        let themesURL = repositoryRoot.appending(path: "themes")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: themesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            themes = []
            return
        }

        themes = files
            .filter { $0.pathExtension == "json" }
            .compactMap(loadTheme)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func loadTheme(from url: URL) -> PosterTheme? {
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let slug = url.deletingPathExtension().lastPathComponent
        return PosterTheme(
            slug: slug,
            name: object["name"] as? String ?? "",
            description: object["description"] as? String ?? "",
            backgroundHex: object["bg"] as? String ?? "",
            roadHex: object["road_primary"] as? String ?? object["road_default"] as? String ?? "",
            textHex: object["text"] as? String ?? ""
        )
    }
}
