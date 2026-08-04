import XCTest
@testable import ScooterCompanionVision

final class ThemeVisionTests: XCTestCase {
    func testThemeColorsExist() {
        XCTAssertNotNil(Theme.Colors.primary)
        XCTAssertNotNil(Theme.Colors.secondary)
        XCTAssertNotNil(Theme.Colors.background)
        XCTAssertNotNil(Theme.Colors.elevatedBackground)
        XCTAssertNotNil(Theme.Colors.textPrimary)
        XCTAssertNotNil(Theme.Colors.textSecondary)
    }

    func testThemeSpacing() {
        XCTAssertGreaterThan(Theme.Spacing.small, 0)
        XCTAssertGreaterThan(Theme.Spacing.medium, Theme.Spacing.small)
        XCTAssertGreaterThan(Theme.Spacing.large, Theme.Spacing.medium)
    }

    func testThemeFontsExist() {
        XCTAssertNotNil(Theme.Fonts.headerLarge())
        XCTAssertNotNil(Theme.Fonts.bodyMedium)
        XCTAssertNotNil(Theme.Fonts.caption)
    }

    func testRouteSpeedSegmentsShareBoundaries() {
        let coordinates = [
            RouteCoordinate(latitude: 43.0, longitude: -79.0, speed: 5),
            RouteCoordinate(latitude: 43.1, longitude: -79.1, speed: 5),
            RouteCoordinate(latitude: 43.2, longitude: -79.2, speed: 40),
            RouteCoordinate(latitude: 43.3, longitude: -79.3, speed: 40)
        ]

        let segments = routeSpeedSegments(for: coordinates)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].coordinates.count, 2)
        XCTAssertEqual(segments[1].coordinates.first, coordinates[1])
    }
}
