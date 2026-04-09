//
//  JavaLCGTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class JavaLCGTests: XCTestCase {
    func testDeterministicOutput() {
        let lcg1 = JavaLCG(seed: 12345)
        let lcg2 = JavaLCG(seed: 12345)
        for _ in 0..<100 {
            XCTAssertEqual(lcg1.nextInt(), lcg2.nextInt())
        }
    }

    func testKnownJavaOutput() {
        // Java: new Random(0).nextInt() = -1155484576
        let lcg = JavaLCG(seed: 0)
        XCTAssertEqual(lcg.nextInt(), -1155484576)
    }

    func testNextIntSecondValue() {
        // Java: new Random(0); r.nextInt(); r.nextInt() = -723955400
        let lcg = JavaLCG(seed: 0)
        _ = lcg.nextInt()
        XCTAssertEqual(lcg.nextInt(), -723955400)
    }

    func testNextIntBound() {
        let lcg = JavaLCG(seed: 42)
        let val = lcg.nextInt(bound: 100)
        XCTAssertTrue(val >= 0 && val < 100)
    }

    func testNextBytes() {
        let lcg = JavaLCG(seed: 0)
        let bytes = lcg.nextBytes(count: 4)
        XCTAssertEqual(bytes.count, 4)
    }

    func testNextBytesKnownOutput() {
        // Java: new Random(0).nextBytes(new byte[4])
        // nextInt() = -1155484576 = 0xBB20B460
        // Bytes extracted LSB first: [0x60, 0xB4, 0x20, 0xBB]
        let lcg = JavaLCG(seed: 0)
        let bytes = lcg.nextBytes(count: 4)
        XCTAssertEqual(bytes, Data([0x60, 0xB4, 0x20, 0xBB]))
    }

    func testPasswordGeneration() {
        let authParam = Data(repeating: 0x42, count: 16)
        let pwd1 = JavaLCG.generatePassword(authParam: authParam, timestampMs: 1000000)
        let pwd2 = JavaLCG.generatePassword(authParam: authParam, timestampMs: 1000000)
        XCTAssertEqual(pwd1.count, 16)
        XCTAssertEqual(pwd1, pwd2) // Same inputs = same password
    }

    func testDifferentTimestampsProduceDifferentPasswords() {
        let authParam = Data(repeating: 0x42, count: 16)
        let pwd1 = JavaLCG.generatePassword(authParam: authParam, timestampMs: 1000000)
        let pwd2 = JavaLCG.generatePassword(authParam: authParam, timestampMs: 1000001)
        XCTAssertNotEqual(pwd1, pwd2)
    }

    func testSeedOffset() {
        let authParam = Data([0x01, 0x02, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let offset = JavaLCG.deriveSeedOffset(authParam: authParam)
        // Expected: 0x01 | (0x02 << 8) | (0x03 << 16) | (0x04 << 24) = 0x04030201 = 67305985
        XCTAssertEqual(offset, 67305985)
    }
}
