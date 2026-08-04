//
//  GT3RegistersTests.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import XCTest
@testable import ScooterCompanion

final class GT3RegistersTests: XCTestCase {
    func testLiveTelemetryCount() {
        XCTAssertEqual(GT3Registers.liveTelemetry.count, 19)
    }

    func testCumulativeCount() {
        XCTAssertGreaterThanOrEqual(GT3Registers.cumulative.count, 28)
    }

    func testAllRegistersNoDuplicateNames() {
        let names = GT3Registers.all.map { $0.name }
        XCTAssertEqual(names.count, Set(names).count, "Duplicate register names found")
    }

    func testSpeedRegister() {
        let reg = GT3Registers.speed
        XCTAssertEqual(reg.board, .vcu)
        XCTAssertEqual(reg.index, 0x57)
        XCTAssertEqual(reg.size, 2)
    }

    func testBMSVoltageRegister() {
        let reg = GT3Registers.bmsVoltage
        XCTAssertEqual(reg.board, .bms2)
        XCTAssertEqual(reg.index, 0x8C)
        XCTAssertEqual(reg.size, 2)
    }

    func testCellVoltagesRegister() {
        let reg = GT3Registers.bms1CellVoltages
        XCTAssertEqual(reg.size, 26)
    }
}
