//
//  NinebotTransportTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class NinebotTransportTests: XCTestCase {
    func testFragmentSmallFrame() async {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        let smallData = Data(repeating: 0x42, count: 10)
        let chunks = await transport.fragment(smallData)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], smallData)
    }

    func testFragmentLargeFrame() async {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        let largeData = Data(repeating: 0xAB, count: 50)
        let chunks = await transport.fragment(largeData)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 20)
        XCTAssertEqual(chunks[1].count, 20)
        XCTAssertEqual(chunks[2].count, 10)

        let reassembled = chunks.reduce(Data()) { $0 + $1 }
        XCTAssertEqual(reassembled, largeData)
    }

    func testInboundReassemblyPlaintext() async throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        // New GT3 Pro plain frame format: LEN=data count only.
        // Frame: 5A A5 01 3E 02 04 57 23 CHK_LO CHK_HI (10 bytes, LEN=1 for 1 data byte)
        // Checksum covers frame[2..]: 01+3E+02+04+57+23 = 0xBF → ~0xBF = 0xFF40 → [40, FF]
        let frame = Data([0x5A, 0xA5, 0x01, 0x3E, 0x02, 0x04, 0x57, 0x23, 0x40, 0xFF])
        let parsed = try await transport.processInbound(chunk: frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.cmd, 0x04)
        XCTAssertEqual(parsed?.index, 0x57)
    }

    func testInboundReassemblyPartialChunks() async throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        // New GT3 Pro plain frame (10 bytes, LEN=1)
        let frame = Data([0x5A, 0xA5, 0x01, 0x3E, 0x02, 0x04, 0x57, 0x23, 0x40, 0xFF])

        let partial = try await transport.processInbound(chunk: Data(frame[0..<4]))
        XCTAssertNil(partial)

        let complete = try await transport.processInbound(chunk: Data(frame[4...]))
        XCTAssertNotNil(complete)
        XCTAssertEqual(complete?.index, 0x57)
    }

    func testReassemblyResetOnInvalidSecondByte() async throws {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto)

        let garbage = Data([0x5A, 0xFF, 0x05, 0x3E, 0x02, 0x04, 0x57, 0x23])
        let result = try await transport.processInbound(chunk: garbage)
        XCTAssertNil(result)
    }

    func testPrepareOutboundProducesFragments() async throws {
        let key = KeyDerivation.deriveKey(key1: Data("test".utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        let plainFrame = NinebotFrameBuilder.buildReadFrame(
            board: .vcu,
            register: 0x57,
            length: 2
        )

        let chunks = try await transport.prepareOutbound(plaintextFrame: plainFrame)
        XCTAssertGreaterThan(chunks.count, 0)

        XCTAssertEqual(chunks[0][0], BLEConstants.syncByte1)
        XCTAssertEqual(chunks[0][1], BLEConstants.syncByte2Encrypted)
    }

    func testMTUUpdate() async {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)
        let transport = NinebotTransport(crypto: crypto, mtu: 23)

        let data = Data(repeating: 0x42, count: 50)
        let defaultChunks = await transport.fragment(data)
        XCTAssertEqual(defaultChunks.count, 3)

        await transport.updateMTU(103)
        let bigChunks = await transport.fragment(data)
        XCTAssertEqual(bigChunks.count, 1)
    }
}
