//
//  RegisterReaderTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class RegisterReaderTests: XCTestCase {
    func testInitialStateIsEmpty() async {
        let reader = RegisterReader()
        let telemetryCount = await reader.getTelemetryCount()
        XCTAssertEqual(telemetryCount, 0)
        let snapshotCount = await reader.getSnapshotCount()
        XCTAssertEqual(snapshotCount, 0)
    }

    func testProcessResponseWithReadAck() async {
        let reader = RegisterReader()
        // Simulate a speed register response: 723 raw = 72.3 km/h
        // In responses: btID = responding board, source = 0x3E (app)
        let parsed = NinebotFrameBuilder.ParsedFrame(
            length: 6,
            btID: BLEConstants.Board.vcu.rawValue,
            source: 0x3E,
            cmd: BLEConstants.Command.readAck.rawValue,
            index: 0x57,
            payload: Data([0xD3, 0x02])
        )
        let result = await reader.processResponse(parsed)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "rSpeed")
        XCTAssertEqual(result?.doubleValue ?? 0, 72.3, accuracy: 0.01)
    }

    func testProcessResponseStoresTelemetryValue() async {
        let reader = RegisterReader()
        let parsed = NinebotFrameBuilder.ParsedFrame(
            length: 6,
            btID: BLEConstants.Board.vcu.rawValue,
            source: 0x3E,
            cmd: BLEConstants.Command.readAck.rawValue,
            index: 0x57,
            payload: Data([0xD3, 0x02])
        )
        _ = await reader.processResponse(parsed)
        let speed = await reader.getTelemetryDouble("rSpeed")
        XCTAssertEqual(speed ?? 0, 72.3, accuracy: 0.01)
    }

    func testProcessResponseIgnoresNonReadAck() async {
        let reader = RegisterReader()
        let parsed = NinebotFrameBuilder.ParsedFrame(
            length: 6,
            btID: BLEConstants.Board.vcu.rawValue,
            source: 0x3E,
            cmd: BLEConstants.Command.write.rawValue,
            index: 0x57,
            payload: Data([0xD3, 0x02])
        )
        let result = await reader.processResponse(parsed)
        XCTAssertNil(result)
    }

    func testProcessResponseStoresSnapshotForCumulativeRegister() async {
        let reader = RegisterReader()
        // Odometer: 4 bytes LE, 123450 raw = 1234.50 km
        let val: UInt32 = 123450
        let payload = Data([
            UInt8(val & 0xFF), UInt8((val >> 8) & 0xFF),
            UInt8((val >> 16) & 0xFF), UInt8((val >> 24) & 0xFF)
        ])
        let parsed = NinebotFrameBuilder.ParsedFrame(
            length: 8,
            btID: BLEConstants.Board.vcu.rawValue,
            source: 0x3E,
            cmd: BLEConstants.Command.readAck.rawValue,
            index: 0x62,
            payload: payload
        )
        let result = await reader.processResponse(parsed)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "rMileage")
        // Odometer is in liveTelemetry, so stored in telemetry values
        let odometer = await reader.getTelemetryDouble("rMileage")
        XCTAssertEqual(odometer ?? 0, 1234.50, accuracy: 0.01)
    }

    func testClearTelemetry() async {
        let reader = RegisterReader()
        let parsed = NinebotFrameBuilder.ParsedFrame(
            length: 6,
            btID: BLEConstants.Board.vcu.rawValue,
            source: 0x3E,
            cmd: BLEConstants.Command.readAck.rawValue,
            index: 0x57,
            payload: Data([0xD3, 0x02])
        )
        _ = await reader.processResponse(parsed)
        let before = await reader.getTelemetryCount()
        XCTAssertGreaterThan(before, 0)

        await reader.clearTelemetry()
        let after = await reader.getTelemetryCount()
        XCTAssertEqual(after, 0)
    }
}
