//
//  NinebotCryptoTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class NinebotCryptoTests: XCTestCase {
    func testNonSNEncryptDecryptRoundTrip() throws {
        let key = KeyDerivation.deriveKey(key1: Data("NB-GT3Pro".utf8), key2: BLEConstants.dataBasic)
        let crypto = NinebotCrypto(key: key, counter: 0)

        let plaintext = Data([
            0x3E, 0x04, 0x5B, 0x00
        ])

        let encrypted = try crypto.encrypt(plaintext: plaintext)
        // Non-SN mode adds 6-byte tail
        XCTAssertEqual(encrypted.count, plaintext.count + 6)

        let decryptCrypto = NinebotCrypto(key: key, counter: 0)
        let decrypted = try decryptCrypto.decrypt(encrypted: encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testSNEncryptDecryptRoundTrip() throws {
        let key = KeyDerivation.deriveKey(
            key1: Data("NB-GT3Pro".utf8),
            key2: Data(repeating: 0xAA, count: 16)
        )
        let authParam = Data(repeating: 0xAA, count: 16)

        let encryptCrypto = NinebotCrypto(key: key, authParam: authParam, counter: 1)
        let plaintext = Data([
            0x3E, 0x02, 0x01, 0x57, 0x02
        ])

        let encrypted = try encryptCrypto.encrypt(plaintext: plaintext)
        // SN mode: encrypted payload + 4-byte MAC + 2-byte counter
        XCTAssertEqual(encrypted.count, plaintext.count + 6)

        let decryptCrypto = NinebotCrypto(key: key, authParam: authParam, counter: 1)
        let decrypted = try decryptCrypto.decrypt(encrypted: encrypted)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testSNCounterIncrements() throws {
        let key = Data(repeating: 0x01, count: 16)
        let authParam = Data(repeating: 0x02, count: 16)
        let crypto = NinebotCrypto(key: key, authParam: authParam, counter: 1)

        XCTAssertEqual(crypto.getCounter(), 1)
        _ = try crypto.encrypt(plaintext: Data([0x3E, 0x02, 0x01, 0x57, 0x02]))
        XCTAssertEqual(crypto.getCounter(), 2)
        _ = try crypto.encrypt(plaintext: Data([0x3E, 0x02, 0x01, 0x55, 0x02]))
        XCTAssertEqual(crypto.getCounter(), 3)
    }

    func testSNMACVerificationFailsOnTamper() throws {
        let key = Data(repeating: 0x01, count: 16)
        let authParam = Data(repeating: 0x02, count: 16)

        let encryptCrypto = NinebotCrypto(key: key, authParam: authParam, counter: 1)
        let plaintext = Data([0x3E, 0x02, 0x01, 0x57, 0x02])
        var encrypted = try encryptCrypto.encrypt(plaintext: plaintext)

        // Tamper with the encrypted payload
        encrypted[0] ^= 0xFF

        let decryptCrypto = NinebotCrypto(key: key, authParam: authParam, counter: 1)
        XCTAssertThrowsError(try decryptCrypto.decrypt(encrypted: encrypted)) { error in
            guard case NinebotCryptoError.macVerificationFailed = error else {
                XCTFail("Expected macVerificationFailed, got \(error)")
                return
            }
        }
    }

    func testNonSNStaticKeystream() throws {
        // In non-SN mode, the same keystream is used for every block
        let key = Data(repeating: 0x42, count: 16)
        let crypto1 = NinebotCrypto(key: key, counter: 0)
        let crypto2 = NinebotCrypto(key: key, counter: 0)

        let pt1 = Data([0x3E, 0x04, 0x5B, 0x00])
        let pt2 = Data([0x3E, 0x04, 0x5B, 0x00])

        let enc1 = try crypto1.encrypt(plaintext: pt1)
        let enc2 = try crypto2.encrypt(plaintext: pt2)

        // Same plaintext + same key = same encrypted output in non-SN mode
        XCTAssertEqual(enc1, enc2)
    }

    func testSNDifferentCountersProduceDifferentCiphertext() throws {
        let key = Data(repeating: 0x01, count: 16)
        let authParam = Data(repeating: 0x02, count: 16)
        let plaintext = Data([0x3E, 0x02, 0x01, 0x57, 0x02])

        let crypto1 = NinebotCrypto(key: key, authParam: authParam, counter: 1)
        let enc1 = try crypto1.encrypt(plaintext: plaintext)

        let crypto2 = NinebotCrypto(key: key, authParam: authParam, counter: 2)
        let enc2 = try crypto2.encrypt(plaintext: plaintext)

        // Different counters → different ciphertext
        XCTAssertNotEqual(enc1, enc2)
    }

    func testDecryptFrameTooShort() {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 1)

        XCTAssertThrowsError(try crypto.decrypt(encrypted: Data([0x01, 0x02]))) { error in
            guard case NinebotCryptoError.frameTooShort = error else {
                XCTFail("Expected frameTooShort, got \(error)")
                return
            }
        }
    }

    func testEnableSNMode() {
        let key = Data(count: 16)
        let crypto = NinebotCrypto(key: key, counter: 0)

        XCTAssertEqual(crypto.getCounter(), 0)
        crypto.enableSNMode()
        XCTAssertEqual(crypto.getCounter(), 1)

        // Calling again shouldn't reset
        crypto.enableSNMode()
        XCTAssertEqual(crypto.getCounter(), 1)
    }

    func testKeyUpdate() throws {
        let key1 = Data(repeating: 0x01, count: 16)
        let key2 = Data(repeating: 0x02, count: 16)
        let plaintext = Data([0x3E, 0x04, 0x5B, 0x00])

        let crypto = NinebotCrypto(key: key1, counter: 0)
        let enc1 = try crypto.encrypt(plaintext: plaintext)

        let crypto2 = NinebotCrypto(key: key1, counter: 0)
        crypto2.updateKey(key2)
        let enc2 = try crypto2.encrypt(plaintext: plaintext)

        XCTAssertNotEqual(enc1, enc2)
    }

    /// Verify the PRE_COMM checksum is computed over the full payload (not payload[3:]).
    /// For payload 3E 04 5B 00: sum = 0x9D, checksum = ~0x9D & 0xFFFF = 0xFF62.
    func testNonSNChecksumCoversFullPayload() throws {
        let key = KeyDerivation.deriveKey(key1: Data("03GGG2539C0023".utf8), key2: BLEConstants.dataBasic)
        let crypto = NinebotCrypto(key: key, counter: 0)

        // PRE_COMM payload (after 3-byte frame header is stripped)
        let payload = Data([0x3E, 0x04, 0x5B, 0x00])
        let encrypted = try crypto.encrypt(plaintext: payload)

        // Tail is the last 6 bytes: [0x00, 0x00, checksum_lo, checksum_hi, 0x00, 0x00]
        // sum(3E 04 5B 00) = 0x9D → checksum = ~0x9D & 0xFFFF = 0xFF62
        let tail = Data(encrypted[(encrypted.count - 6)...])
        let checksumLo = tail[tail.startIndex + 2]
        let checksumHi = tail[tail.startIndex + 3]
        let checksum = UInt16(checksumHi) << 8 | UInt16(checksumLo)

        XCTAssertEqual(checksum, 0xFF62,
            "Checksum must cover full payload (sum=0x9D, ~sum=0xFF62), not just payload[3:]")
    }

    /// End-to-end test verified against a real Bluetooth packet capture from the Segway app.
    /// Reproduces the encrypted PRE_COMM (Frame 1 in capture) sent to B5A3-0002.
    func testCaptureVerifiedPreCommEncryption() throws {
        // From capture: name = "03GGG2539C0023"
        let name = "03GGG2539C0023"
        let key = KeyDerivation.deriveKey(key1: Data(name.utf8), key2: BLEConstants.dataBasic)

        // Verified from packet capture analysis:
        // key = SHA1(pad("03GGG2539C0023",16) + dataBasic)[0:16] = 41332579467d814852f122b62bc88411
        XCTAssertEqual(key.map { String(format: "%02x", $0) }.joined(),
                       "41332579467d814852f122b62bc88411")

        let crypto = NinebotCrypto(key: key, counter: 0)

        // PRE_COMM payload: BT_ID=0x3E, TARGET=0x04, CMD=0x5B, INDEX=0x00
        let payload = Data([0x3E, 0x04, 0x5B, 0x00])
        let encrypted = try crypto.encrypt(plaintext: payload)

        // Non-SN keystream = AES_ECB(key, dataBasic) = 99e0fd99d32f247cd8d6e1429ea9fac6
        // XOR: [3E^99, 04^e0, 5B^fd, 00^99] = [a7, e4, a6, 99]
        // Checksum: ~(3E+04+5B+00) = ~0x9D = 0xFF62 → [62, FF]
        // Expected: a7 e4 a6 99 00 00 62 ff 00 00
        let expected = Data([0xA7, 0xE4, 0xA6, 0x99, 0x00, 0x00, 0x62, 0xFF, 0x00, 0x00])
        XCTAssertEqual(encrypted, expected,
            "Encrypted PRE_COMM must match packet capture Frame 1")
    }

    /// Verify non-SN round-trip decryption with the real GT3 Pro key.
    func testCaptureVerifiedPreCommRoundTrip() throws {
        let name = "03GGG2539C0023"
        let key = KeyDerivation.deriveKey(key1: Data(name.utf8), key2: BLEConstants.dataBasic)
        let payload = Data([0x3E, 0x04, 0x5B, 0x00])

        let encryptCrypto = NinebotCrypto(key: key, counter: 0)
        let encrypted = try encryptCrypto.encrypt(plaintext: payload)

        let decryptCrypto = NinebotCrypto(key: key, counter: 0)
        let decrypted = try decryptCrypto.decrypt(encrypted: encrypted)
        XCTAssertEqual(decrypted, payload)
    }
}
