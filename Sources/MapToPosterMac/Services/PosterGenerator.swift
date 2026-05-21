import Foundation

struct PosterGenerationResult {
    let outputURL: URL?
    let exitCode: Int32
}

enum PosterGeneratorError: LocalizedError {
    case missingScript(URL)
    case missingDependencies(String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingScript(let url):
            "Could not find create_map_poster.py at \(url.path)."
        case .missingDependencies(let message):
            message
        case .launchFailed(let message):
            message
        }
    }
}

final class PosterGenerator {
    private let repositoryRoot: URL

    init(repositoryRoot: URL = RepositoryLocator.repositoryRoot) {
        self.repositoryRoot = repositoryRoot
    }

    func generate(request: PosterRequest, onOutput: @escaping @MainActor (String) -> Void) async throws -> PosterGenerationResult {
        let scriptURL = repositoryRoot.appending(path: "create_map_poster.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw PosterGeneratorError.missingScript(scriptURL)
        }

        let startDate = Date()
        let launch = try pythonLaunch(arguments: request.commandArguments())
        if let message = try dependencyMessage(for: launch) {
            throw PosterGeneratorError.missingDependencies(message)
        }

        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = repositoryRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                onOutput(text)
            }
        }

        do {
            try process.run()
        } catch {
            throw PosterGeneratorError.launchFailed(error.localizedDescription)
        }

        await wait(for: process)
        pipe.fileHandleForReading.readabilityHandler = nil

        let latestOutput = latestPoster(since: startDate, format: request.format)
        return PosterGenerationResult(outputURL: latestOutput, exitCode: process.terminationStatus)
    }

    func dependencyWarning() async -> String? {
        do {
            let launch = try pythonLaunch(arguments: [])
            return try dependencyMessage(for: launch)
        } catch {
            return error.localizedDescription
        }
    }

    private func pythonLaunch(arguments: [String]) throws -> (executableURL: URL, arguments: [String]) {
        if let uvURL = executable(named: "uv") {
            return (uvURL, ["run", "./create_map_poster.py"] + arguments)
        }

        let venvPython = repositoryRoot.appending(path: ".venv/bin/python3")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (venvPython, ["create_map_poster.py"] + arguments)
        }

        if let pythonURL = executable(named: "python3") {
            return (pythonURL, ["create_map_poster.py"] + arguments)
        }

        throw PosterGeneratorError.launchFailed("Neither uv nor python3 was found on PATH.")
    }

    private func executable(named name: String) -> URL? {
        let defaultPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? defaultPaths)
            .split(separator: ":")
            .map(String.init)

        for path in paths {
            let candidate = URL(filePath: path).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func dependencyMessage(for launch: (executableURL: URL, arguments: [String])) throws -> String? {
        if launch.executableURL.lastPathComponent == "uv" {
            return nil
        }

        let check = Process()
        check.executableURL = launch.executableURL
        check.arguments = ["-c", "import matplotlib, osmnx, geopandas, geopy, PIL"]
        check.currentDirectoryURL = repositoryRoot

        let pipe = Pipe()
        check.standardOutput = pipe
        check.standardError = pipe

        try check.run()
        check.waitUntilExit()

        guard check.terminationStatus != 0 else {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let details = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .last
            .map(String.init) ?? "Required Python packages are missing."

        return """
        Python dependencies are not installed for this interpreter.
        \(details)

        Run ./script/setup_python.sh, then generate again.
        """
    }

    private func wait(for process: Process) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private func latestPoster(since startDate: Date, format: PosterFormat) -> URL? {
        let postersURL = repositoryRoot.appending(path: "posters")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: postersURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents
            .filter { $0.pathExtension.lowercased() == format.rawValue }
            .compactMap { url -> (URL, Date)? in
                guard
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                    values.isRegularFile == true,
                    let date = values.contentModificationDate,
                    date >= startDate
                else {
                    return nil
                }
                return (url, date)
            }
            .max { $0.1 < $1.1 }?
            .0
    }
}
