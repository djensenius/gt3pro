//
//  TelemetryParserTests.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import XCTest
@testable import ScooterCompanion

final class TelemetryParserTests: XCTestCase {
    func testParseUInt16() {
        let data = Data([0x34, 0x12]) // 0x1234 = 4660
        XCTAssertEqual(TelemetryParser.parseUInt16(data), 4660)
    }

    func testParseUInt16LittleEndian() {
        let data = Data([0xFF, 0x00]) // 255
        XCTAssertEqual(TelemetryParser.parseUInt16(data), 255)
    }

    func testParseInt16Negative() {
        let data = Data([0xCE, 0xFF]) // -50 in two's complement LE
        XCTAssertEqual(TelemetryParser.parseInt16(data), -50)
    }

    func testParseUInt32() {
        let data = Data([0x78, 0x56, 0x34, 0x12]) // 0x12345678
        XCTAssertEqual(TelemetryParser.parseUInt32(data), 0x12345678)
    }

    func testParseSpeed() {
        // 723 raw → 72.3 km/h
        let data = Data([0xD3, 0x02]) // 723 LE
        XCTAssertEqual(TelemetryParser.parseSpeed(data), 72.3, accuracy: 0.01)
    }

    func testParseVoltage() {
        // 5842 raw → 58.42 V
        let data = Data([0xD2, 0x16]) // 5842 LE
        XCTAssertEqual(TelemetryParser.parseVoltage(data), 58.42, accuracy: 0.01)
    }

    func testParseCurrent() {
        // -1230 raw → -12.30 A (discharging)
        let raw = Int16(-1230)
        let unsigned = UInt16(bitPattern: raw)
        let data = Data([UInt8(unsigned & 0xFF), UInt8(unsigned >> 8)])
        XCTAssertEqual(TelemetryParser.parseCurrent(data), -12.30, accuracy: 0.01)
    }

    func testParseTemperature() {
        // 382 raw → 38.2 °C
        let data = Data([0x7E, 0x01]) // 382 LE
        XCTAssertEqual(TelemetryParser.parseTemperature(data), 38.2, accuracy: 0.01)
    }

    func testParseDistance() {
        // 1240 raw → 12.40 km
        let data = Data([0xD8, 0x04]) // 1240 LE
        XCTAssertEqual(TelemetryParser.parseDistance(data), 12.40, accuracy: 0.01)
    }

    func testParseOdometer() {
        // 123450 raw → 1234.50 km
        let val: UInt32 = 123_450
        let data = Data([UInt8(val & 0xFF), UInt8((val >> 8) & 0xFF),
                         UInt8((val >> 16) & 0xFF), UInt8((val >> 24) & 0xFF)])
        XCTAssertEqual(TelemetryParser.parseOdometer(data), 1234.50, accuracy: 0.01)
    }

    func testParseASCII() {
        let data = Data("N2GWD1234567890".utf8).prefix(14)
        XCTAssertEqual(TelemetryParser.parseASCII(data), "N2GWD123456789")
    }

    func testParseFirmwareVersion() {
        let data = Data([0x6E, 0x01]) // 366 → "3.66"
        XCTAssertEqual(TelemetryParser.parseFirmwareVersion(data), "3.66")
    }

    func testParseCellVoltages() {
        // 13 cells × 2 bytes = 26 bytes
        var data = Data()
        for idx in 0..<13 {
            let voltage = UInt16(3800 + idx * 10) // 3.800V to 3.920V
            data.append(UInt8(voltage & 0xFF))
            data.append(UInt8(voltage >> 8))
        }
        let voltages = TelemetryParser.parseCellVoltages(data)
        XCTAssertEqual(voltages.count, 13)
        XCTAssertEqual(voltages[0], 3.800, accuracy: 0.001)
        XCTAssertEqual(voltages[12], 3.920, accuracy: 0.001)
    }

    func testParseTempSensors() {
        // 8 sensors × 2 bytes = 16 bytes
        var data = Data()
        for idx in 0..<8 {
            let temp = Int16(250 + idx * 10) // 25.0°C to 32.0°C
            let unsigned = UInt16(bitPattern: temp)
            data.append(UInt8(unsigned & 0xFF))
            data.append(UInt8(unsigned >> 8))
        }
        let temps = TelemetryParser.parseTempSensors(data)
        XCTAssertEqual(temps.count, 8)
        XCTAssertEqual(temps[0], 25.0, accuracy: 0.1)
    }

    func testParseShortData() {
        // Short data should return 0 / empty gracefully
        XCTAssertEqual(TelemetryParser.parseUInt16(Data()), 0)
        XCTAssertEqual(TelemetryParser.parseUInt32(Data([0x01])), 0)
        XCTAssertEqual(TelemetryParser.parseSpeed(Data()), 0.0)
    }

    func testParseRegisterDispatch() throws {
        let speedData = Data([0xD3, 0x02]) // 723
        let result = TelemetryParser.parseRegister(GT3Registers.speed, data: speedData)
        let value = try XCTUnwrap(result as? Double)
        XCTAssertEqual(value, 72.3, accuracy: 0.01)
    }
}
