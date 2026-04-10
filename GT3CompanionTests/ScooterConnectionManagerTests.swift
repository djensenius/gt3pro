//
//  ScooterConnectionManagerTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class ScooterConnectionManagerTests: XCTestCase {
    func testInitialStateIsDisconnected() {
        let manager = ScooterConnectionManager()
        XCTAssertEqual(manager.connectionState, .disconnected)
    }

    func testConnectionStateIsEquatable() {
        XCTAssertEqual(ConnectionState.disconnected, ConnectionState.disconnected)
        XCTAssertNotEqual(ConnectionState.disconnected, ConnectionState.connected)
    }

    func testAllConnectionStates() {
        XCTAssertEqual(ConnectionState.allCases.count, 7)
    }

    // MARK: - BLE Name Sanitization

    func testSanitizePlainName() {
        XCTAssertEqual(ScooterConnectionManager.sanitizeBLEName("NB-12345"), "NB-12345")
    }

    func testSanitizeSegwayName() {
        let name = "Segway Scooter0023"
        XCTAssertEqual(ScooterConnectionManager.sanitizeBLEName(name), name)
    }

    func testSanitizeEmojiPrefixedName() {
        XCTAssertEqual(
            ScooterConnectionManager.sanitizeBLEName("🛴 Segway Scooter0023"),
            "Segway Scooter0023"
        )
    }

    func testSanitizeMultipleEmoji() {
        XCTAssertEqual(
            ScooterConnectionManager.sanitizeBLEName("🛴🔋 Device"),
            "Device"
        )
    }

    func testSanitizeNoChangeForEmpty() {
        XCTAssertEqual(ScooterConnectionManager.sanitizeBLEName(""), "")
    }

    func testSanitizePreservesInternalEmoji() {
        XCTAssertEqual(
            ScooterConnectionManager.sanitizeBLEName("Device🛴Name"),
            "Device🛴Name"
        )
    }
}
