//
//  NinebotFrameBuilderTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class NinebotFrameBuilderTests: XCTestCase {
    func testBuildReadFrame() {
        let frame = NinebotFrameBuilder.buildReadFrame(board: .vcu, register: 0x57, length: 2)
        // GT3 Pro format: LEN = data.count only (1 data byte = the length byte)
        // [5A, A5, LEN, 3E, 02, 01, 57, 02]
        XCTAssertEqual(frame[0], 0x5A) // sync
        XCTAssertEqual(frame[1], 0xA5) // sync
        XCTAssertEqual(frame[2], 1)    // length: 1 data byte
        XCTAssertEqual(frame[3], 0x3E) // BT_ID
        XCTAssertEqual(frame[4], 0x02) // VCU board
        XCTAssertEqual(frame[5], 0x01) // read command
        XCTAssertEqual(frame[6], 0x57) // speed register
        XCTAssertEqual(frame[7], 0x02) // read 2 bytes
        XCTAssertEqual(frame.count, 8)
    }

    func testBuildWriteFrame() {
        let data = Data([0xAA, 0xBB])
        let frame = NinebotFrameBuilder.buildWriteFrame(board: .bms1, register: 0x10, data: data)
        XCTAssertEqual(frame[0], 0x5A)
        XCTAssertEqual(frame[1], 0xA5)
        XCTAssertEqual(frame[2], 2)    // 2 data bytes
        XCTAssertEqual(frame[3], 0x3E)
        XCTAssertEqual(frame[4], 0x06) // BMS1
        XCTAssertEqual(frame[5], 0x03) // write command
        XCTAssertEqual(frame[6], 0x10)
        XCTAssertEqual(frame[7], 0xAA)
        XCTAssertEqual(frame[8], 0xBB)
    }

    func testBuildAuthFrame() {
        let frame = NinebotFrameBuilder.buildAuthFrame(cmd: .preComm, data: Data())
        XCTAssertEqual(frame[4], 0x21) // BLE board (0x21 on GT3 Pro)
        XCTAssertEqual(frame[5], 0x5B) // PRE_COMM
        XCTAssertEqual(frame[6], 0x00) // index 0
    }

    func testParseFrame() {
        let frame = Data([0x5A, 0xA5, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])
        let parsed = NinebotFrameBuilder.parseFrame(frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.source, 0x02) // VCU
        XCTAssertEqual(parsed?.cmd, 0x04)    // readAck
        XCTAssertEqual(parsed?.index, 0x57)  // speed register
        XCTAssertEqual(parsed?.payload, Data([0x23]))
    }

    func testParseFrameTooShort() {
        let frame = Data([0x5A, 0xA5])
        XCTAssertNil(NinebotFrameBuilder.parseFrame(frame))
    }

    func testParseFrameInvalidSync() {
        let frame = Data([0xFF, 0xFF, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])
        XCTAssertNil(NinebotFrameBuilder.parseFrame(frame))
    }
}
