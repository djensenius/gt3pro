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
        // 6-digit hex — verify red channel
        let red = UIColor(Color(hex: "ff0000"))
        var red1: CGFloat = 0, green1: CGFloat = 0, blue1: CGFloat = 0, alpha1: CGFloat = 0
        red.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1)
        XCTAssertEqual(red1, 1.0, accuracy: 0.01)
        XCTAssertEqual(green1, 0.0, accuracy: 0.01)
        XCTAssertEqual(blue1, 0.0, accuracy: 0.01)
        XCTAssertEqual(alpha1, 1.0, accuracy: 0.01)

        // 3-digit hex — verify green channel
        let green = UIColor(Color(hex: "0f0"))
        var red2: CGFloat = 0, green2: CGFloat = 0, blue2: CGFloat = 0, alpha2: CGFloat = 0
        green.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)
        XCTAssertEqual(red2, 0.0, accuracy: 0.01)
        XCTAssertEqual(green2, 1.0, accuracy: 0.01)
        XCTAssertEqual(blue2, 0.0, accuracy: 0.01)

        // 8-digit hex with alpha — verify alpha channel
        let halfAlpha = UIColor(Color(hex: "80ff0000"))
        var red3: CGFloat = 0, green3: CGFloat = 0, blue3: CGFloat = 0, alpha3: CGFloat = 0
        halfAlpha.getRed(&red3, green: &green3, blue: &blue3, alpha: &alpha3)
        XCTAssertEqual(alpha3, 128.0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(red3, 1.0, accuracy: 0.01)
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
