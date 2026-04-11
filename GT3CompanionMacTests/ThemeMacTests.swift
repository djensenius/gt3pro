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
}
