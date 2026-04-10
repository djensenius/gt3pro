//
//  NinebotAuthTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class NinebotAuthTests: XCTestCase {
    let testBTName = "NB-GT3Pro"
    let testAuthParam = Data(repeating: 0xAA, count: 16)
    let testSerial = Data("N2GWD1234567890".utf8).prefix(14)

    func testInitialStateIsIdle() async {
        let auth = NinebotAuth(btName: testBTName)
        let state = await auth.state
        if case .idle = state {
            // Expected
        } else {
            XCTFail("Expected idle, got \(state)")
        }
    }

    func testStartAuthGeneratesPreCommFrame() async {
        let auth = NinebotAuth(btName: testBTName)
        let frame = await auth.startAuth()

        let parsed = NinebotFrameBuilder.parseFrame(frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.cmd, BLEConstants.Command.preComm.rawValue)
        XCTAssertEqual(parsed?.source, BLEConstants.Board.mcu.rawValue) // MCU target for encrypted auth
        XCTAssertEqual(parsed?.index, 0x00)
    }

    func testPreCommStateAfterStart() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()
        let state = await auth.state
        if case .preComm = state {
            // Expected
        } else {
            XCTFail("Expected preComm, got \(state)")
        }
    }

    func testPreCommResponseExtractsAuthParamAndSerial() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()

        // Build a fake PRE_COMM response: 16 bytes authParam + 14 bytes serial
        var responsePayload = testAuthParam
        responsePayload.append(testSerial)

        let response = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 0, // no stored password
            payload: responsePayload
        )

        let nextFrame = await auth.processResponse(response)
        XCTAssertNotNil(nextFrame, "Should generate SET_PWD frame")

        let state = await auth.state
        if case .setPwd = state {
            // Expected
        } else {
            XCTFail("Expected setPwd, got \(state)")
        }
    }

    func testSetPwdAccepted() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()

        // PRE_COMM response
        var responsePayload = testAuthParam
        responsePayload.append(testSerial)
        let preCommResponse = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 0,
            payload: responsePayload
        )
        _ = await auth.processResponse(preCommResponse)

        // SET_PWD accepted (INDEX=1)
        let setPwdResponse = NinebotFrameBuilder.ParsedFrame(
            length: 4,
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.setPwd.rawValue,
            index: 1,
            payload: Data()
        )
        let authFrame = await auth.processResponse(setPwdResponse)
        XCTAssertNotNil(authFrame, "Should generate AUTH frame")

        let state = await auth.state
        if case .auth = state {
            // Expected
        } else {
            XCTFail("Expected auth, got \(state)")
        }
    }

    func testSetPwdWaitingForButtonPress() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()

        var responsePayload = testAuthParam
        responsePayload.append(testSerial)
        let preCommResponse = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 0,
            payload: responsePayload
        )
        _ = await auth.processResponse(preCommResponse)

        // SET_PWD waiting (INDEX=0)
        let setPwdResponse = NinebotFrameBuilder.ParsedFrame(
            length: 4,
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.setPwd.rawValue,
            index: 0,
            payload: Data()
        )
        let retryFrame = await auth.processResponse(setPwdResponse)
        XCTAssertNotNil(retryFrame, "Should retry SET_PWD")

        let state = await auth.state
        if case .setPwd = state {
            // Expected — still in setPwd
        } else {
            XCTFail("Expected setPwd, got \(state)")
        }
    }

    func testAuthSuccess() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()

        // PRE_COMM → SET_PWD accepted → AUTH success
        var responsePayload = testAuthParam
        responsePayload.append(testSerial)
        let preCommResponse = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 0,
            payload: responsePayload
        )
        _ = await auth.processResponse(preCommResponse)

        let setPwdResponse = NinebotFrameBuilder.ParsedFrame(
            length: 4, btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.setPwd.rawValue,
            index: 1, payload: Data()
        )
        _ = await auth.processResponse(setPwdResponse)

        let authResponse = NinebotFrameBuilder.ParsedFrame(
            length: 4, btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.auth.rawValue,
            index: 1, payload: Data()
        )
        let result = await auth.processResponse(authResponse)
        XCTAssertNil(result, "No more frames after auth success")

        let state = await auth.state
        if case .authenticated = state {
            // Expected
        } else {
            XCTFail("Expected authenticated, got \(state)")
        }
    }

    func testStoredPasswordSkipsSetPwd() async {
        let storedPwd = Data(repeating: 0xBB, count: 16)
        let auth = NinebotAuth(btName: testBTName, storedPassword: storedPwd)
        _ = await auth.startAuth()

        // PRE_COMM response with deviceHasStoredPassword (INDEX != 0)
        var responsePayload = testAuthParam
        responsePayload.append(testSerial)
        let preCommResponse = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 1, // device has stored password
            payload: responsePayload
        )
        let nextFrame = await auth.processResponse(preCommResponse)
        XCTAssertNotNil(nextFrame, "Should go straight to AUTH")

        let state = await auth.state
        if case .auth = state {
            // Expected — skipped SET_PWD
        } else {
            XCTFail("Expected auth (skipped setPwd), got \(state)")
        }
    }

    func testPasswordIsAccessible() async {
        let auth = NinebotAuth(btName: testBTName)
        _ = await auth.startAuth()

        var responsePayload = testAuthParam
        responsePayload.append(testSerial)
        let preCommResponse = NinebotFrameBuilder.ParsedFrame(
            length: UInt8(responsePayload.count + 4),
            btID: 0x3E,
            source: BLEConstants.Board.ble.rawValue,
            cmd: BLEConstants.Command.preComm.rawValue,
            index: 0, payload: responsePayload
        )
        _ = await auth.processResponse(preCommResponse)

        let pwd = await auth.getPassword()
        XCTAssertNotNil(pwd)
        XCTAssertEqual(pwd?.count, 16)
    }
}
