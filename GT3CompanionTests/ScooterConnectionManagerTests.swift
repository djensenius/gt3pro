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
}
