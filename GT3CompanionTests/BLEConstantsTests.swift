//
//  BLEConstantsTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import CoreBluetooth
import XCTest
@testable import GT3Companion

final class BLEConstantsTests: XCTestCase {
    func testServiceUUIDFormat() {
        let uuid = BLEConstants.serviceUUID
        XCTAssertEqual(uuid.uuidString, "6E400001-0000-0000-006E-696E65626F74")
    }

    func testNotifyCharIsNot0003() {
        // Critical: notify is 0004, NOT 0003. 0003 is the RCTP write channel.
        XCTAssertNotEqual(BLEConstants.notifyCharUUID, BLEConstants.rctpWriteCharUUID)
        XCTAssertTrue(BLEConstants.notifyCharUUID.uuidString.contains("6E400004"))
        XCTAssertTrue(BLEConstants.rctpWriteCharUUID.uuidString.contains("6E400003"))
    }

    func testBoardIDs() {
        XCTAssertEqual(BLEConstants.Board.ble.rawValue, 0x21)
        XCTAssertEqual(BLEConstants.Board.vcu.rawValue, 0x02)
        XCTAssertEqual(BLEConstants.Board.bms1.rawValue, 0x06)
        XCTAssertEqual(BLEConstants.Board.bms2.rawValue, 0x07)
        XCTAssertEqual(BLEConstants.Board.mcu.rawValue, 0x04)
        XCTAssertEqual(BLEConstants.Board.tft.rawValue, 0x09)
    }

    func testFrameConstants() {
        XCTAssertEqual(BLEConstants.btID, 0x3E)
        XCTAssertEqual(BLEConstants.syncByte1, 0x5A)
        XCTAssertEqual(BLEConstants.syncByte2Plain, 0xA5)
        XCTAssertEqual(BLEConstants.syncByte2Encrypted, 0xB5)
    }

    func testCommandBytes() {
        XCTAssertEqual(BLEConstants.Command.read.rawValue, 0x01)
        XCTAssertEqual(BLEConstants.Command.readAck.rawValue, 0x04)
        XCTAssertEqual(BLEConstants.Command.write.rawValue, 0x03)
        XCTAssertEqual(BLEConstants.Command.preComm.rawValue, 0x5B)
        XCTAssertEqual(BLEConstants.Command.setPwd.rawValue, 0x5C)
        XCTAssertEqual(BLEConstants.Command.auth.rawValue, 0x5D)
    }

    func testDefaultMTU() {
        XCTAssertEqual(BLEConstants.defaultMTU, 23)
        XCTAssertEqual(BLEConstants.defaultFragmentSize, 20)
        XCTAssertEqual(BLEConstants.defaultMTU - 3, BLEConstants.defaultFragmentSize)
    }

    func testHardwareIDs() {
        XCTAssertEqual(BLEConstants.hardwareID, 0x0101)
        XCTAssertEqual(BLEConstants.serverID, 10257)
    }
}
