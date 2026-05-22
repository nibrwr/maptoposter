import XCTest
@testable import MapToPosterMac

final class GeneratedPosterTests: XCTestCase {
    func testRelativeLogPathResolvesInsideApplicationSupportLogs() {
        let metadata = PosterMetadata(
            generatedAt: Date(timeIntervalSince1970: 0),
            request: PosterRequest(),
            outputPath: "norman_sunset.png",
            logPath: "norman_sunset.log"
        )
        let poster = GeneratedPoster(
            id: URL(filePath: "/tmp/norman_sunset.png"),
            url: URL(filePath: "/tmp/norman_sunset.png"),
            metadata: metadata,
            modifiedAt: Date(timeIntervalSince1970: 0),
            fileSize: 10
        )

        XCTAssertEqual(poster.logURL, AppStorageLocations.logsDirectory.appending(path: "norman_sunset.log"))
    }
}
