//
//  KeyDerivationTests.swift
//  ScooterCompanionTests
//
//  Created by David Jensenius.
//

import CryptoKit
import XCTest
@testable import ScooterCompanion

final class KeyDerivationTests: XCTestCase {
    func testBasicDerivation() {
        let key1 = Data("TestDevice".utf8)
        let key2 = Data(repeating: 0xAA, count: 16)

        let derived = KeyDerivation.deriveKey(key1: key1, key2: key2)
        XCTAssertEqual(derived.count, 16)
    }

    func testNullKey2UsesZeros() {
        let key1 = Data("NB-GT3Pro".utf8)

        let derivedWithNil = KeyDerivation.deriveKey(key1: key1, key2: nil)
        let derivedWithZeros = KeyDerivation.deriveKey(key1: key1, key2: Data(count: 16))

        XCTAssertEqual(derivedWithNil, derivedWithZeros)
    }

    func testDeterministic() {
        let key1 = Data("NB-GT3Pro".utf8)
        let key2 = Data([
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10
        ])

        let derived1 = KeyDerivation.deriveKey(key1: key1, key2: key2)
        let derived2 = KeyDerivation.deriveKey(key1: key1, key2: key2)
        XCTAssertEqual(derived1, derived2)
    }

    func testDifferentInputsProduceDifferentKeys() {
        let key1a = Data("DeviceA".utf8)
        let key1b = Data("DeviceB".utf8)
        let key2 = Data(count: 16)

        let derivedA = KeyDerivation.deriveKey(key1: key1a, key2: key2)
        let derivedB = KeyDerivation.deriveKey(key1: key1b, key2: key2)
        XCTAssertNotEqual(derivedA, derivedB)
    }

    func testShortKey1IsPadded() {
        let shortKey = Data("AB".utf8)
        let derived = KeyDerivation.deriveKey(key1: shortKey, key2: nil)
        XCTAssertEqual(derived.count, 16)
    }

    func testLongKey1IsTruncated() {
        let longKey = Data(repeating: 0xFF, count: 32)
        let derived = KeyDerivation.deriveKey(key1: longKey, key2: nil)
        XCTAssertEqual(derived.count, 16)
    }

    func testManualSHA1Verification() {
        // Manually verify: SHA1(key1_padded + key2_padded)[0:16]
        let key1 = Data("NB-GT3".utf8) // 6 bytes, padded to 16
        let key2: Data? = nil           // 16 zero bytes

        var padded1 = key1
        padded1.append(contentsOf: [UInt8](repeating: 0, count: 10))
        let padded2 = Data(count: 16)
        let combined = padded1 + padded2

        let expectedHash = Data(Insecure.SHA1.hash(data: combined).prefix(16))
        let derived = KeyDerivation.deriveKey(key1: key1, key2: key2)

        XCTAssertEqual(derived, expectedHash)
    }
}
