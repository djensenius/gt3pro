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
        XCTAssertEqual(
            String(describing: manager.connectionState),
            String(describing: ConnectionState.disconnected)
        )
    }

    func testConnectionStateEnum() {
        // Verify all states exist and are distinct
        let states: [ConnectionState] = [
            .disconnected, .scanning, .connecting,
            .discovering, .authenticating, .connected, .reconnecting
        ]
        let descriptions = states.map { String(describing: $0) }
        XCTAssertEqual(Set(descriptions).count, 7)
    }
}
