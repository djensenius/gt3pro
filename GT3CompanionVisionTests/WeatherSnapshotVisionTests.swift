import XCTest
@testable import GT3CompanionVision

final class WeatherSnapshotVisionTests: XCTestCase {
    func testWeatherSnapshotCodable() throws {
        let snapshot = WeatherSnapshot(
            temp: 22.5,
            feelsLike: 21.0,
            humidity: 0.65,
            windSpeed: 12.3,
            windDirection: 180.0,
            condition: "Clear",
            conditionSymbol: "sun.max.fill",
            uvIndex: 5,
            pressure: 1013.25
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: data)

        XCTAssertEqual(decoded.temp, 22.5)
        XCTAssertEqual(decoded.feelsLike, 21.0)
        XCTAssertEqual(decoded.humidity, 0.65)
        XCTAssertEqual(decoded.windSpeed, 12.3)
        XCTAssertEqual(decoded.condition, "Clear")
        XCTAssertEqual(decoded.conditionSymbol, "sun.max.fill")
        XCTAssertEqual(decoded.uvIndex, 5)
        XCTAssertEqual(decoded.pressure, 1013.25)
    }

    func testWeatherSymbolFallback() {
        XCTAssertEqual(weatherSymbol(for: "Clear"), "sun.max.fill")
        XCTAssertEqual(weatherSymbol(for: "Rain"), "cloud.rain.fill")
        XCTAssertEqual(weatherSymbol(for: "Snow"), "cloud.snow.fill")
        XCTAssertEqual(weatherSymbol(for: "Cloudy"), "cloud.fill")
        XCTAssertEqual(weatherSymbol(for: "SomethingUnknown"), "cloud.fill")
    }
}
