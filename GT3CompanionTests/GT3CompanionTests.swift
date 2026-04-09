//
//  GT3CompanionTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
import SwiftUI

final class GT3CompanionTests: XCTestCase {
    func testThemeColorsExist() {
        // Verify theme colors are accessible
        _ = Theme.Colors.accent
        _ = Theme.Colors.primary
        _ = Theme.Colors.secondary
        _ = Theme.Colors.background
        _ = Theme.Colors.textPrimary
        _ = Theme.Colors.error
        _ = Theme.Colors.success
    }

    func testColorHexParsing() {
        // 6-digit hex
        let color = Color(hex: "ff0000")
        XCTAssertNotNil(color)

        // 3-digit hex
        let shortColor = Color(hex: "f00")
        XCTAssertNotNil(shortColor)

        // 8-digit hex with alpha
        let alphaColor = Color(hex: "80ff0000")
        XCTAssertNotNil(alphaColor)
    }

    func testThemeSpacing() {
        XCTAssertEqual(Theme.Spacing.small, 8)
        XCTAssertEqual(Theme.Spacing.medium, 12)
        XCTAssertEqual(Theme.Spacing.large, 16)
        XCTAssertEqual(Theme.Spacing.extraLarge, 20)
    }

    func testThemeCornerRadius() {
        XCTAssertEqual(Theme.cornerRadius, 12)
    }
}
