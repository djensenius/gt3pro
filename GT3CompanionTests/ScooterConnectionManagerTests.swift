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

    // MARK: - Peripheral UUID Persistence

    func testSaveAndLoadPeripheralUUID() {
        let defaults = UserDefaults(suiteName: "TestPeripheralUUID")!
        defaults.removePersistentDomain(forName: "TestPeripheralUUID")

        let uuid = UUID()
        ScooterConnectionManager.savePeripheralUUID(uuid, defaults: defaults)
        let loaded = ScooterConnectionManager.loadPeripheralUUID(defaults: defaults)
        XCTAssertEqual(loaded, uuid)

        defaults.removePersistentDomain(forName: "TestPeripheralUUID")
    }

    func testLoadPeripheralUUIDWhenMissing() {
        let defaults = UserDefaults(suiteName: "TestPeripheralUUIDEmpty")!
        defaults.removePersistentDomain(forName: "TestPeripheralUUIDEmpty")

        let loaded = ScooterConnectionManager.loadPeripheralUUID(defaults: defaults)
        XCTAssertNil(loaded)

        defaults.removePersistentDomain(forName: "TestPeripheralUUIDEmpty")
    }

    // MARK: - Ninebot Serial Detection

    func testLooksLikeNinebotSerialWithRealSerial() {
        XCTAssertTrue(ScooterConnectionManager.looksLikeNinebotSerial("03GGG2539C0023"))
    }

    func testLooksLikeNinebotSerialRejectsSegwayName() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("Segway Scooter0023"))
    }

    func testLooksLikeNinebotSerialRejectsNBPrefix() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("NB-12345678901"))
    }

    func testLooksLikeNinebotSerialRejectsLowercase() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("03ggg2539c0023"))
    }

    func testLooksLikeNinebotSerialRejectsTooShort() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("03GGG2539"))
    }

    func testLooksLikeNinebotSerialRejectsTooLong() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("03GGG2539C0023EXTRA"))
    }

    func testLooksLikeNinebotSerialRejectsStartingWithLetter() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("A3GGG2539C0023"))
    }

    func testLooksLikeNinebotSerialRejectsKnownNonScooter() {
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("MAINFRAME"))
        XCTAssertFalse(ScooterConnectionManager.looksLikeNinebotSerial("L300Y5E"))
    }
}
