import Foundation

enum NetworkPreflightError: LocalizedError {
    case unreachable
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            "OpenStreetMap services are not reachable right now. Try again, or enable Cache only if this location has already been generated."
        case .invalidResponse(let statusCode):
            "OpenStreetMap preflight returned HTTP \(statusCode). Try again in a few minutes, or use Cache only for already cached places."
        }
    }
}

final class NetworkPreflightService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkReachability() async throws {
        var request = URLRequest(url: URL(string: "https://nominatim.openstreetmap.org/status.php")!)
        request.timeoutInterval = 8
        request.setValue("map-to-poster-macos/1.0", forHTTPHeaderField: "User-Agent")

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkPreflightError.unreachable
                }
                guard (200..<500).contains(httpResponse.statusCode) else {
                    throw NetworkPreflightError.invalidResponse(httpResponse.statusCode)
                }
                return
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1) * 750_000_000))
                }
            }
        }

        throw lastError ?? NetworkPreflightError.unreachable
    }
}
