//
//  NinebotTransportTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class NinebotTransportTests: XCTestCase {
    func testFragmentSmallFrame() {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        // A frame smaller than MTU should produce a single chunk
        let smallData = Data(repeating: 0x42, count: 10)
        let chunks = transport.fragment(smallData)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], smallData)
    }

    func testFragmentLargeFrame() {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        // 50 bytes should split into 3 chunks at MTU-3=20 bytes each
        let largeData = Data(repeating: 0xAB, count: 50)
        let chunks = transport.fragment(largeData)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[1].count, 20)
        XCTAssertEqual(chunks[2].count, 10)

        // Reassembled should equal original
        let reassembled = chunks.reduce(Data()) { $0 + $1 }
        XCTAssertEqual(reassembled, largeData)
    }

    func testInboundReassemblyPlaintext() throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        // Feed a complete plaintext frame byte by byte
        // [5A, A5, 05, 3E, 02, 04, 57, 23] — LEN=5, total=8
        let frame = Data([0x5A, 0xA5, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])

        // Feed all at once
        let parsed = try transport.processInbound(chunk: frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.cmd, 0x04)
        XCTAssertEqual(parsed?.index, 0x57)
    }

    func testInboundReassemblyPartialChunks() throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        let frame = Data([0x5A, 0xA5, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])

        // Feed first 4 bytes — shouldn't complete yet
        let partial = try transport.processInbound(chunk: Data(frame[0..<4]))
        XCTAssertNil(partial)

        // Feed remaining bytes — should complete
        let complete = try transport.processInbound(chunk: Data(frame[4...]))
        XCTAssertNotNil(complete)
        XCTAssertEqual(complete?.index, 0x57)
    }

    func testReassemblyResetOnInvalidSecondByte() throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        // Feed 0x5A followed by garbage — should reset
        let garbage = Data([0x5A, 0xFF, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])
        let result = try transport.processInbound(chunk: garbage)
        XCTAssertNil(result)
    }

    func testPrepareOutboundProducesFragments() throws {
        let key = KeyDerivation.deriveKey(key1: Data("test".utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        let plainFrame = NinebotFrameBuilder.buildReadFrame(
            board: .vcu,
            register: 0x57,
            length: 2
        )

        let chunks = try transport.prepareOutbound(plaintextFrame: plainFrame)
        XCTAssertGreaterThan(chunks.count, 0)

        // First chunk should start with the encrypted sync bytes
        XCTAssertEqual(chunks[0][0], BLEConstants.syncByte1)
        XCTAssertEqual(chunks[0][1], BLEConstants.syncByte2Encrypted)
    }

    func testMTUUpdate() {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        // With default MTU=23, chunk size = 20
        let data = Data(repeating: 0x42, count: 50)
        let defaultChunks = transport.fragment(data)
        XCTAssertEqual(defaultChunks.count, 3)

        // After MTU update to 103, chunk size = 100
        transport.updateMTU(103)
        let bigChunks = transport.fragment(data)
        XCTAssertEqual(bigChunks.count, 1)
    }
}
