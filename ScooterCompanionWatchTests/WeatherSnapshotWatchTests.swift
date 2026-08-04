import XCTest
@testable import ScooterCompanionWatch

final class WeatherSnapshotWatchTests: XCTestCase {
    func testWeatherSnapshotCodable() throws {
        let snapshot = WeatherSnapshot(
            temp: 18.0,
            feelsLike: 16.5,
            humidity: 0.72,
            windSpeed: 8.0,
            windDirection: 270.0,
            condition: "Partly Cloudy",
            conditionSymbol: "cloud.sun.fill",
            uvIndex: 3,
            pressure: 1015.0
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: data)

        XCTAssertEqual(decoded.temp, 18.0)
        XCTAssertEqual(decoded.condition, "Partly Cloudy")
        XCTAssertEqual(decoded.conditionSymbol, "cloud.sun.fill")
        XCTAssertEqual(decoded.uvIndex, 3)
    }

    func testWeatherSymbolFallback() {
        XCTAssertEqual(weatherSymbol(for: "Clear"), "sun.max.fill")
        XCTAssertEqual(weatherSymbol(for: "Rain"), "cloud.rain.fill")
        XCTAssertEqual(weatherSymbol(for: "Cloudy"), "cloud.fill")
    }
}
