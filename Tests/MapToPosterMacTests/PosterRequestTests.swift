import Foundation
import XCTest
@testable import MapToPosterMac

final class PosterRequestTests: XCTestCase {
    func testDefaultRequestUsesNorman() {
        let request = PosterRequest()

        XCTAssertEqual(request.locationQuery, "Norman, OK")
        XCTAssertEqual(request.posterCity, "Norman")
        XCTAssertEqual(request.posterRegion, "OK")
        XCTAssertEqual(request.distance, 8000)
        XCTAssertTrue(request.canGenerate)
    }

    func testCustomDimensionsAcceptPopularLargePosterSize() {
        var request = PosterRequest()

        request.sizePreset = .custom
        request.customWidthText = "24 in"
        request.customHeightText = "36 inches"

        XCTAssertEqual(request.effectiveDimensions?.width, 24)
        XCTAssertEqual(request.effectiveDimensions?.height, 36)
    }

    func testOutputURLIsExplicitAndSafe() {
        var request = PosterRequest()
        request.locationQuery = "Norman, OK"
        request.city = "Norman"
        request.themeSlug = "sunset"

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let outputURL = request.generatedOutputURL(in: URL(filePath: "/tmp/maptoposter"), date: date)

        XCTAssertEqual(outputURL.deletingLastPathComponent().lastPathComponent, "posters")
        XCTAssertEqual(outputURL.pathExtension, "png")
        XCTAssertTrue(outputURL.lastPathComponent.hasPrefix("norman_sunset_"))
    }

    func testCommandArgumentsIncludeExplicitOutputPath() {
        let request = PosterRequest()
        let outputURL = URL(filePath: "/tmp/maptoposter/posters/out.png")
        let arguments = request.commandArguments(outputURL: outputURL)

        XCTAssertTrue(arguments.contains("--output"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--output")! + 1], outputURL.path)
    }

    func testCommandArgumentsIncludeCacheOnlyWhenEnabled() {
        var request = PosterRequest()
        request.cacheOnly = true

        XCTAssertTrue(request.commandArguments().contains("--cache-only"))
    }

    func testCommandArgumentsIncludePosterEnhancementOptions() {
        var request = PosterRequest()
        request.detailLevel = .rich
        request.insetMode = .on
        request.enhanceSparseMaps = false

        let arguments = request.commandArguments()

        XCTAssertEqual(arguments[arguments.firstIndex(of: "--detail-level")! + 1], "rich")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--inset")! + 1], "on")
        XCTAssertTrue(arguments.contains("--no-enhance-sparse"))
    }

    func testManualLocationChangeDrivesPosterLabels() {
        var request = PosterRequest()
        request.updateLocationQuery("Lexington, KY")

        XCTAssertEqual(request.posterCity, "Lexington")
        XCTAssertEqual(request.posterRegion, "KY")

        let arguments = request.commandArguments()
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--city")! + 1], "Lexington")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--country")! + 1], "KY")
    }

    func testAdvancedLabelsOverrideLocationDerivedLabels() {
        var request = PosterRequest()
        request.updateLocationQuery("Lexington, KY")
        request.displayCity = "Horse Capital"
        request.displayCountry = "Kentucky"

        XCTAssertEqual(request.posterCity, "Horse Capital")
        XCTAssertEqual(request.posterRegion, "Kentucky")
    }

    func testManualLocationChangeClearsStaleAdvancedLabels() {
        var request = PosterRequest()
        request.displayCity = "Norman"
        request.displayCountry = "OK"
        request.countryLabel = "Campus"

        request.updateLocationQuery("Fort Riley, KS")

        XCTAssertEqual(request.displayCity, "")
        XCTAssertEqual(request.displayCountry, "")
        XCTAssertEqual(request.countryLabel, "")
        XCTAssertEqual(request.posterCity, "Fort Riley")
        XCTAssertEqual(request.posterRegion, "KS")
    }
}
