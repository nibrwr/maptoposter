import XCTest
@testable import MapToPosterMac

final class PosterLogSanitizerTests: XCTestCase {
    func testSanitizerRemovesProgressEventsAndParsesLatestEvent() {
        let raw = """
        Generating Norman, OK...
        MAPTOPOSTER_EVENT {"progress":0.42,"status":"Downloading street network"}
        ✓ Coordinates: 35.2225717, -97.4394816
        Fetching map data:\rDownloading water features
        MAPTOPOSTER_EVENT {"progress":0.56,"status":"Downloading water features"}
        """

        let parsed = PosterLogSanitizer.parse(raw)

        XCTAssertFalse(parsed.log.contains("MAPTOPOSTER_EVENT"))
        XCTAssertFalse(parsed.log.contains("35.2225717"))
        XCTAssertTrue(parsed.log.contains("[coordinates redacted]"))
        XCTAssertTrue(parsed.log.contains("Generating Norman, OK"))
        XCTAssertTrue(parsed.log.contains("Downloading water features"))
        XCTAssertEqual(parsed.event?.progress, 0.56)
        XCTAssertEqual(parsed.event?.status, "Downloading water features")
    }

    func testOutputParserBuffersPartialProgressEvents() {
        let parser = PosterOutputParser()

        let first = parser.append("MAPTOPOSTER_EVENT {\"progress\":")
        let second = parser.append("0.78,\"status\":\"Rendering\"}\nRendering map...\n")

        XCTAssertNil(first.event)
        XCTAssertEqual(first.log, "")
        XCTAssertEqual(second.event?.progress, 0.78)
        XCTAssertEqual(second.event?.status, "Rendering")
        XCTAssertTrue(second.log.contains("Rendering map"))
    }
}
