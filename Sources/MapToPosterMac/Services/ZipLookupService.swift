import Foundation

struct ZipLookupResult {
    let locationName: String
}

enum ZipLookupError: LocalizedError, Equatable {
    case emptyZip
    case noResult
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyZip:
            "Enter a ZIP code to look up."
        case .noResult:
            "No city was found for that ZIP code."
        case .invalidResponse:
            "ZIP code lookup returned an invalid response."
        }
    }
}

final class ZipLookupService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(zipCode: String) async throws -> ZipLookupResult {
        let trimmedZip = zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedZip.isEmpty else {
            throw ZipLookupError.emptyZip
        }

        var components = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmedZip),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "addressdetails", value: "1"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw ZipLookupError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("map-to-poster-macos/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw ZipLookupError.invalidResponse
        }

        let results = try JSONDecoder().decode([NominatimResult].self, from: data)
        guard let first = results.first else {
            throw ZipLookupError.noResult
        }

        return try ZipLookupResult(locationName: Self.locationName(from: first.address))
    }

    static func locationName(from address: NominatimAddress) throws -> String {
        let city = address.city ?? address.town ?? address.village ?? address.hamlet
        let region = address.state ?? address.county
        let country = address.country

        let locationName = [city, region, country]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: ", ")

        guard !locationName.isEmpty else {
            throw ZipLookupError.noResult
        }

        return locationName
    }
}

struct NominatimResult: Decodable {
    let address: NominatimAddress
}

struct NominatimAddress: Decodable {
    let city: String?
    let town: String?
    let village: String?
    let hamlet: String?
    let county: String?
    let state: String?
    let country: String?

    init(
        city: String? = nil,
        town: String? = nil,
        village: String? = nil,
        hamlet: String? = nil,
        county: String? = nil,
        state: String? = nil,
        country: String? = nil
    ) {
        self.city = city
        self.town = town
        self.village = village
        self.hamlet = hamlet
        self.county = county
        self.state = state
        self.country = country
    }
}
