import Foundation

struct PosterGenerationResult {
    let outputURL: URL?
    let logURL: URL?
    let exitCode: Int32
}

struct PosterProgressEvent: Decodable {
    let progress: Double
    let status: String
}

enum PosterLogSanitizer {
    private static let eventPrefix = "MAPTOPOSTER_EVENT "

    static func parse(_ text: String, redactSensitiveValues: Bool = true) -> (log: String, event: PosterProgressEvent?) {
        var visibleLines: [String] = []
        var lastEvent: PosterProgressEvent?

        for rawLine in text.replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(eventPrefix) {
                let payload = String(line.dropFirst(eventPrefix.count))
                if let data = payload.data(using: .utf8),
                   let event = try? JSONDecoder().decode(PosterProgressEvent.self, from: data) {
                    lastEvent = event
                }
                continue
            }

            var sanitized = line.filter { !$0.isASCIIControl || $0 == "\n" || $0 == "\t" }
            if redactSensitiveValues {
                sanitized = redactCoordinates(from: sanitized)
            }
            guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            visibleLines.append(sanitized)
        }

        let log = visibleLines.isEmpty ? "" : visibleLines.joined(separator: "\n") + "\n"
        return (log, lastEvent)
    }

    private static func redactCoordinates(from line: String) -> String {
        guard line.localizedCaseInsensitiveContains("coordinates") else {
            return line
        }

        let pattern = #"[-+]?\d{1,3}(?:\.\d+)?,\s*[-+]?\d{1,3}(?:\.\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return line
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.stringByReplacingMatches(
            in: line,
            range: range,
            withTemplate: "[coordinates redacted]"
        )
    }
}

final class PosterOutputParser {
    private var pending = ""

    func append(_ text: String, flush: Bool = false, redactSensitiveValues: Bool = true) -> (log: String, event: PosterProgressEvent?) {
        pending += text

        var parseable = ""
        if flush {
            parseable = pending
            pending = ""
        } else if let lastNewline = pending.lastIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let end = pending.index(after: lastNewline)
            parseable = String(pending[..<end])
            pending = String(pending[end...])
        }

        guard !parseable.isEmpty else {
            return ("", nil)
        }

        return PosterLogSanitizer.parse(parseable, redactSensitiveValues: redactSensitiveValues)
    }
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
    private var cachedDependencyCheck: (key: String, warning: String?)?
    private let processLock = NSLock()
    private var runningProcess: Process?

    init(repositoryRoot: URL = RepositoryLocator.repositoryRoot) {
        self.repositoryRoot = repositoryRoot
    }

    func generate(
        request: PosterRequest,
        outputDirectory: URL = AppStorageLocations.postersDirectory,
        onOutput: @escaping @MainActor (String) -> Void,
        onProgress: @escaping @MainActor (PosterProgressEvent) -> Void
    ) async throws -> PosterGenerationResult {
        let scriptURL = repositoryRoot.appending(path: "create_map_poster.py")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw PosterGeneratorError.missingScript(scriptURL)
        }

        try AppStorageLocations.prepare()

        let outputURL = request.generatedOutputURL(inPostersDirectory: outputDirectory)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let launch = try pythonLaunch(arguments: request.commandArguments(outputURL: outputURL))
        if let message = try cachedDependencyMessage(for: launch) {
            throw PosterGeneratorError.missingDependencies(message)
        }

        let logURL = try makeLogURL(for: request)
        try "Generating \(request.locationQuery)\nOutput: \(outputURL.path)\n\n".write(
            to: logURL,
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        process.currentDirectoryURL = repositoryRoot
        process.environment = processEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let redactedParser = PosterOutputParser()
        let logFileParser = PosterOutputParser()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let parsed = redactedParser.append(text)
            let fileLog = logFileParser.append(text).log
            if !fileLog.isEmpty {
                Self.append(fileLog, to: logURL)
            }
            Task { @MainActor in
                if !parsed.log.isEmpty {
                    onOutput(parsed.log)
                }
                if let event = parsed.event {
                    onProgress(event)
                }
            }
        }

        do {
            try process.run()
            setRunningProcess(process)
        } catch {
            throw PosterGeneratorError.launchFailed(error.localizedDescription)
        }

        defer {
            clearRunningProcess(process)
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try await wait(for: process)
            if Task.isCancelled {
                throw CancellationError()
            }
        } catch {
            if process.isRunning {
                process.terminate()
            }
            throw error
        }

        let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
        let remainingText = String(data: remainingData, encoding: .utf8) ?? ""
        let redactedRemainder = redactedParser.append(remainingText, flush: true)
        let fileRemainder = logFileParser.append(remainingText, flush: true).log
        if !fileRemainder.isEmpty {
            Self.append(fileRemainder, to: logURL)
        }
        await MainActor.run {
            if !redactedRemainder.log.isEmpty {
                onOutput(redactedRemainder.log)
            }
            if let event = redactedRemainder.event {
                onProgress(event)
            }
        }

        let generatedURL = FileManager.default.fileExists(atPath: outputURL.path) ? outputURL : nil
        return PosterGenerationResult(outputURL: generatedURL, logURL: logURL, exitCode: process.terminationStatus)
    }

    func dependencyWarning() async -> String? {
        do {
            let launch = try pythonLaunch(arguments: [])
            return try cachedDependencyMessage(for: launch)
        } catch {
            return error.localizedDescription
        }
    }

    func cancel() {
        processLock.lock()
        let process = runningProcess
        processLock.unlock()

        guard let process, process.isRunning else { return }
        process.terminate()
    }

    private func pythonLaunch(arguments: [String]) throws -> (executableURL: URL, arguments: [String]) {
        let venvPython = repositoryRoot.appending(path: ".venv/bin/python3")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (venvPython, ["create_map_poster.py"] + arguments)
        }

        if let uvURL = trustedExecutable(named: "uv") {
            return (uvURL, ["run", "./create_map_poster.py"] + arguments)
        }

        if let pythonURL = trustedExecutable(named: "python3") {
            return (pythonURL, ["create_map_poster.py"] + arguments)
        }

        throw PosterGeneratorError.launchFailed("Neither .venv/bin/python3, trusted uv, nor trusted python3 was found.")
    }

    private func trustedExecutable(named name: String) -> URL? {
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
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
        check.arguments = [
            "-c",
            "import importlib.util, sys; missing=[m for m in ['matplotlib','osmnx','geopandas','geopy','PIL'] if importlib.util.find_spec(m) is None]; print(', '.join(missing)); sys.exit(1 if missing else 0)"
        ]
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
        let missing = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let details = missing.isEmpty ? "Required Python packages are missing." : "Missing modules: \(missing)."

        return """
        Python dependencies are not installed for this interpreter.
        \(details)

        Run ./script/setup_python.sh, then generate again.
        """
    }

    private func cachedDependencyMessage(for launch: (executableURL: URL, arguments: [String])) throws -> String? {
        let key = launch.executableURL.path
        if let cachedDependencyCheck, cachedDependencyCheck.key == key {
            return cachedDependencyCheck.warning
        }

        let warning = try dependencyMessage(for: launch)
        cachedDependencyCheck = (key, warning)
        return warning
    }

    private func wait(for process: Process) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CACHE_DIR"] = AppStorageLocations.cacheDirectory.path
        environment["MPLCONFIGDIR"] = AppStorageLocations.matplotlibDirectory.path
        if let cacheSecret = try? AppStorageLocations.cacheSecret() {
            environment["CACHE_SECRET"] = cacheSecret
        }
        return environment
    }

    private func makeLogURL(for request: PosterRequest) throws -> URL {
        let outputURL = request.generatedOutputURL(inPostersDirectory: AppStorageLocations.logsDirectory)
        return outputURL.deletingPathExtension().appendingPathExtension("log")
    }

    private func setRunningProcess(_ process: Process) {
        processLock.lock()
        runningProcess = process
        processLock.unlock()
    }

    private func clearRunningProcess(_ process: Process) {
        processLock.lock()
        if runningProcess === process {
            runningProcess = nil
        }
        processLock.unlock()
    }

    private static func append(_ text: String, to url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }
}

private extension Character {
    var isASCIIControl: Bool {
        unicodeScalars.allSatisfy { $0.value < 32 || $0.value == 127 }
    }
}
