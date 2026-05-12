import XCTest
@testable import GT3CompanionMac

final class ThemeMacTests: XCTestCase {
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

    func testRidePresentationSortsSamplesAndFiltersRoute() {
        let ride = PersistedRide(rideId: "test", startTime: Date(), startBattery: 90)
        let later = PersistedSample(timestamp: Date(timeIntervalSince1970: 20), speed: 20, battery: 80)
        later.latitude = 43.0
        later.longitude = -79.0
        later.horizontalAccuracy = 10
        later.roughnessScore = 0.6
        later.heartRate = 120

        let earlier = PersistedSample(timestamp: Date(timeIntervalSince1970: 10), speed: 10, battery: 85)
        earlier.latitude = 0
        earlier.longitude = 0
        earlier.horizontalAccuracy = 5

        ride.samples = [later, earlier]

        let presentation = ride.ridePresentation
        XCTAssertEqual(presentation.sortedSamples.map(\.speed), [10, 20])
        XCTAssertEqual(presentation.routeCoordinates.count, 1)
        XCTAssertEqual(presentation.averageRoughness, 0.6)
        XCTAssertEqual(presentation.averageHeartRate, 120)
    }
}
