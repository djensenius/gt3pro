import XCTest
@testable import ScooterCompanionWatch

final class ThemeWatchTests: XCTestCase {
    func testThemeColorsExist() {
        XCTAssertNotNil(Theme.Colors.primary)
        XCTAssertNotNil(Theme.Colors.secondary)
        XCTAssertNotNil(Theme.Colors.background)
        XCTAssertNotNil(Theme.Colors.elevatedBackground)
    }

    func testThemeSpacing() {
        XCTAssertGreaterThan(Theme.Spacing.small, 0)
        XCTAssertGreaterThan(Theme.Spacing.medium, Theme.Spacing.small)
        XCTAssertGreaterThan(Theme.Spacing.large, Theme.Spacing.medium)
    }
}
