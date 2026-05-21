import Foundation

struct ZipLookupResult {
    let locationName: String
}

enum ZipLookupError: LocalizedError {
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
        request.setValue("map-to-poster-macos/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let results = try JSONDecoder().decode([NominatimResult].self, from: data)
        guard let first = results.first else {
            throw ZipLookupError.noResult
        }

        let city = first.address.city ?? first.address.town ?? first.address.village ?? first.address.hamlet
        let region = first.address.state ?? first.address.county
        let country = first.address.country

        let locationName = [city, region, country]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: ", ")

        guard !locationName.isEmpty else {
            throw ZipLookupError.noResult
        }

        return ZipLookupResult(locationName: locationName)
    }
}

private struct NominatimResult: Decodable {
    let address: NominatimAddress
}

private struct NominatimAddress: Decodable {
    let city: String?
    let town: String?
    let village: String?
    let hamlet: String?
    let county: String?
    let state: String?
    let country: String?
}
