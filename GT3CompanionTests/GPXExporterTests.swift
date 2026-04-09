#if os(iOS)
import XCTest
@testable import GT3Companion

final class GPXExporterTests: XCTestCase {
    func testExportContainsGPXHeader() {
        let gpx = GPXExporter.export(
            rideName: "Test Ride",
            date: Date(),
            coordinates: []
        )
        XCTAssertTrue(gpx.contains("<?xml"))
        XCTAssertTrue(gpx.contains("<gpx"))
        XCTAssertTrue(gpx.contains("GT3Companion"))
    }

    func testExportContainsCoordinates() {
        let coords = [GPXCoordinate(latitude: 43.65, longitude: -79.38, altitude: 76.0, timestamp: Date(), speed: 15.0)]
        let gpx = GPXExporter.export(rideName: "Test", date: Date(), coordinates: coords)
        XCTAssertTrue(gpx.contains("43.65"))
        XCTAssertTrue(gpx.contains("-79.38"))
        XCTAssertTrue(gpx.contains("76.0"))
    }

    func testExportToFileURL() {
        let coords = [GPXCoordinate(latitude: 43.65, longitude: -79.38, altitude: 76.0, timestamp: Date(), speed: 15.0)]
        let url = GPXExporter.exportToFileURL(rideName: "Test", date: Date(), coordinates: coords)
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.pathExtension == "gpx")
    }

    func testExportEmptyCoordinates() {
        let gpx = GPXExporter.export(rideName: "Empty", date: Date(), coordinates: [])
        XCTAssertTrue(gpx.contains("<trkseg>"))
        XCTAssertTrue(gpx.contains("</trkseg>"))
        XCTAssertFalse(gpx.contains("<trkpt"))
    }
}
#endif
