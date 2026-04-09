//
//  AESHelperTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class AESHelperTests: XCTestCase {
    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0x01, count: 16)
        let plaintext = Data(repeating: 0xAB, count: 16)

        let ciphertext = try AESHelper.encryptBlock(key: key, plaintext: plaintext)
        XCTAssertEqual(ciphertext.count, 16)
        XCTAssertNotEqual(ciphertext, plaintext)

        let decrypted = try AESHelper.decryptBlock(key: key, ciphertext: ciphertext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testKnownVector() throws {
        // NIST AES-128 ECB test vector
        // Key: 2b7e151628aed2a6abf7158809cf4f3c
        // Plaintext: 6bc1bee22e409f96e93d7e117393172a
        // Ciphertext: 3ad77bb40d7a3660a89ecaf32466ef97
        let key = Data([
            0x2B, 0x7E, 0x15, 0x16, 0x28, 0xAE, 0xD2, 0xA6,
            0xAB, 0xF7, 0x15, 0x88, 0x09, 0xCF, 0x4F, 0x3C
        ])
        let plaintext = Data([
            0x6B, 0xC1, 0xBE, 0xE2, 0x2E, 0x40, 0x9F, 0x96,
            0xE9, 0x3D, 0x7E, 0x11, 0x73, 0x93, 0x17, 0x2A
        ])
        let expected = Data([
            0x3A, 0xD7, 0x7B, 0xB4, 0x0D, 0x7A, 0x36, 0x60,
            0xA8, 0x9E, 0xCA, 0xF3, 0x24, 0x66, 0xEF, 0x97
        ])

        let ciphertext = try AESHelper.encryptBlock(key: key, plaintext: plaintext)
        XCTAssertEqual(ciphertext, expected)

        let decrypted = try AESHelper.decryptBlock(key: key, ciphertext: ciphertext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testZeroKeyZeroPlaintext() throws {
        let key = Data(count: 16)
        let plaintext = Data(count: 16)

        let ciphertext = try AESHelper.encryptBlock(key: key, plaintext: plaintext)
        XCTAssertEqual(ciphertext.count, 16)
        // AES(zeros, zeros) produces a known non-zero output
        XCTAssertNotEqual(ciphertext, plaintext)

        let decrypted = try AESHelper.decryptBlock(key: key, ciphertext: ciphertext)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testInvalidKeySize() {
        let shortKey = Data(count: 8)
        let plaintext = Data(count: 16)

        XCTAssertThrowsError(try AESHelper.encryptBlock(key: shortKey, plaintext: plaintext)) { error in
            guard case AESError.invalidKeySize = error else {
                XCTFail("Expected invalidKeySize, got \(error)")
                return
            }
        }
    }

    func testInvalidBlockSize() {
        let key = Data(count: 16)
        let shortBlock = Data(count: 8)

        XCTAssertThrowsError(try AESHelper.encryptBlock(key: key, plaintext: shortBlock)) { error in
            guard case AESError.invalidBlockSize = error else {
                XCTFail("Expected invalidBlockSize, got \(error)")
                return
            }
        }
    }

    func testDifferentKeysProduceDifferentCiphertext() throws {
        let key1 = Data([
            0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
            0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
        ])
        let key2 = Data([
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
            0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
        ])
        let plaintext = Data(repeating: 0x42, count: 16)

        let ct1 = try AESHelper.encryptBlock(key: key1, plaintext: plaintext)
        let ct2 = try AESHelper.encryptBlock(key: key2, plaintext: plaintext)
        XCTAssertNotEqual(ct1, ct2)
    }
}
