import XCTest
@testable import MapToPosterMac

final class ZipLookupServiceTests: XCTestCase {
    func testLocationNamePrefersCityStateCountry() throws {
        let address = NominatimAddress(city: "Norman", state: "Oklahoma", country: "United States")

        let name = try ZipLookupService.locationName(from: address)

        XCTAssertEqual(name, "Norman, Oklahoma, United States")
    }

    func testLocationNameFallsBackToTownAndCounty() throws {
        let address = NominatimAddress(town: "Telluride", county: "San Miguel County", country: "United States")

        let name = try ZipLookupService.locationName(from: address)

        XCTAssertEqual(name, "Telluride, San Miguel County, United States")
    }

    func testLocationNameRejectsEmptyAddress() {
        XCTAssertThrowsError(try ZipLookupService.locationName(from: NominatimAddress())) { error in
            XCTAssertEqual(error as? ZipLookupError, .noResult)
        }
    }
}
