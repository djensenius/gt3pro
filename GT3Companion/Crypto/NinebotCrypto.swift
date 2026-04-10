//
//  NinebotCrypto.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

/// Ninebot Encryption2 engine supporting both non-SN and SN modes.
///
/// Non-SN mode (counter == 0): Used only for PRE_COMM. Static keystream with checksum.
/// SN mode (counter > 0): CTR encryption with CBC-MAC authentication.
final class NinebotCrypto: @unchecked Sendable {
    private var aesKey: Data
    private var authParam: Data
    private var counter: UInt16

    init(key: Data, authParam: Data = Data(count: 16), counter: UInt16 = 0) {
        self.aesKey = key
        self.authParam = authParam
        self.counter = counter
    }

    func updateKey(_ key: Data) {
        self.aesKey = key
    }

    func updateAuthParam(_ param: Data) {
        self.authParam = param
    }

    func enableSNMode() {
        if counter == 0 {
            counter = 1
        }
    }

    func setCounter(_ newCounter: UInt16) {
        counter = newCounter
    }

    func getCounter() -> UInt16 {
        counter
    }

    // MARK: - Encrypt

    /// Encrypt a plaintext frame. Returns the encrypted payload + MAC + counter.
    /// The caller prepends the 3-byte header separately:
    /// [5A, A5, LEN] for plaintext or [5A, B5, LEN] for encrypted frames.
    func encrypt(plaintext: Data) throws -> Data {
        if counter == 0 {
            return try encryptNonSN(plaintext: plaintext)
        } else {
            return try encryptSN(plaintext: plaintext)
        }
    }

    /// Decrypt an encrypted frame. Input is the encrypted payload + MAC + counter
    /// (everything after the 3-byte header).
    func decrypt(encrypted: Data) throws -> Data {
        if counter == 0 {
            return try decryptNonSN(encrypted: encrypted)
        } else {
            return try decryptSN(encrypted: encrypted)
        }
    }

    // MARK: - Non-SN Mode (PRE_COMM)

    private func encryptNonSN(plaintext: Data) throws -> Data {
        let keystream = try AESHelper.encryptBlock(key: aesKey, plaintext: Data(count: 16))

        var encrypted = Data()
        for offset in stride(from: 0, to: plaintext.count, by: 16) {
            let end = min(offset + 16, plaintext.count)
            let block = plaintext[offset..<end]
            for idx in 0..<block.count {
                encrypted.append(block[block.startIndex + idx] ^ keystream[idx])
            }
        }

        // Checksum covers the full payload (the 3-byte frame header was already stripped by the transport).
        let sum = plaintext.reduce(UInt32(0)) { $0 + UInt32($1) }
        let checksum = UInt16(truncatingIfNeeded: ~sum)

        encrypted.append(0x00)
        encrypted.append(0x00)
        encrypted.append(UInt8(checksum & 0xFF))
        encrypted.append(UInt8(checksum >> 8))
        encrypted.append(0x00)
        encrypted.append(0x00)

        return encrypted
    }

    private func decryptNonSN(encrypted: Data) throws -> Data {
        guard encrypted.count >= 6 else {
            throw NinebotCryptoError.frameTooShort
        }

        let payloadEnd = encrypted.count - 6
        let payload = encrypted[0..<payloadEnd]
        let tail = encrypted[payloadEnd...]
        let keystream = try AESHelper.encryptBlock(key: aesKey, plaintext: Data(count: 16))

        var decrypted = Data()
        for offset in stride(from: 0, to: payload.count, by: 16) {
            let end = min(offset + 16, payload.count)
            let block = payload[offset..<end]
            for idx in 0..<block.count {
                decrypted.append(block[block.startIndex + idx] ^ keystream[idx])
            }
        }

        // Validate checksum from tail bytes [0x00, 0x00, checksum_lo, checksum_hi, 0x00, 0x00]
        let checksumLo = tail[tail.startIndex + 2]
        let checksumHi = tail[tail.startIndex + 3]
        let receivedChecksum = UInt16(checksumHi) << 8 | UInt16(checksumLo)

        // Checksum covers the full decrypted payload (header was already stripped).
        let sum = decrypted.reduce(UInt32(0)) { $0 + UInt32($1) }
        let expectedChecksum = UInt16(truncatingIfNeeded: ~sum)

        guard receivedChecksum == expectedChecksum else {
            throw NinebotCryptoError.checksumMismatch
        }

        return decrypted
    }

    // MARK: - SN Mode (CTR + CBC-MAC)

    private func encryptSN(plaintext: Data) throws -> Data {
        let currentCounter = counter
        counter &+= 1

        let nonce = buildNonce(counter: currentCounter)
        let tag = try computeCBCMAC(plaintext: plaintext, nonce: nonce)
        let encryptedPayload = try ctrEncrypt(data: plaintext, nonce: nonce, startBlock: 1)
        let encryptedTag = try encryptTag(tag: tag, nonce: nonce)

        var result = encryptedPayload
        result.append(encryptedTag)
        result.append(UInt8(currentCounter >> 8))
        result.append(UInt8(currentCounter & 0xFF))

        return result
    }

    private func decryptSN(encrypted: Data) throws -> Data {
        guard encrypted.count >= 6 else {
            throw NinebotCryptoError.frameTooShort
        }

        let counterHigh = UInt16(encrypted[encrypted.count - 2])
        let counterLow = UInt16(encrypted[encrypted.count - 1])
        let frameCounter = (counterHigh << 8) | counterLow

        let encryptedTag = Data(encrypted[(encrypted.count - 6)..<(encrypted.count - 2)])
        let encryptedPayload = Data(encrypted[0..<(encrypted.count - 6)])

        let nonce = buildNonce(counter: frameCounter)
        let decryptedPayload = try ctrEncrypt(data: encryptedPayload, nonce: nonce, startBlock: 1)

        let decryptedTag = try decryptTag(encryptedTag: encryptedTag, nonce: nonce)
        let expectedTag = try computeCBCMAC(plaintext: decryptedPayload, nonce: nonce)

        guard decryptedTag == expectedTag else {
            throw NinebotCryptoError.macVerificationFailed
        }

        return decryptedPayload
    }

    // MARK: - Nonce (13 bytes)

    /// Nonce = counter_bigEndian(4 bytes) + auth_param[0..<8] + 0x00
    private func buildNonce(counter: UInt16) -> Data {
        var nonce = Data(count: 13)
        nonce[0] = 0x00
        nonce[1] = 0x00
        nonce[2] = UInt8(counter >> 8)
        nonce[3] = UInt8(counter & 0xFF)
        let paramSlice = authParam.prefix(8)
        for idx in 0..<min(paramSlice.count, 8) {
            nonce[4 + idx] = paramSlice[paramSlice.startIndex + idx]
        }
        nonce[12] = 0x00
        return nonce
    }

    // MARK: - CTR Encryption

    /// CTR encrypt/decrypt (symmetric operation).
    /// For each block i (starting at startBlock):
    ///   A_i = [0x01] + nonce(13B) + [0x00, i]
    ///   keystream = AES_ECB(key, A_i)
    ///   output = input XOR keystream
    private func ctrEncrypt(data: Data, nonce: Data, startBlock: Int) throws -> Data {
        var output = Data()
        var blockIndex = startBlock

        for offset in stride(from: 0, to: data.count, by: 16) {
            var counterBlock = Data(count: 16)
            counterBlock[0] = 0x01
            counterBlock.replaceSubrange(1..<14, with: nonce)
            counterBlock[14] = 0x00
            counterBlock[15] = UInt8(blockIndex & 0xFF)

            let keystream = try AESHelper.encryptBlock(key: aesKey, plaintext: counterBlock)

            let end = min(offset + 16, data.count)
            for idx in 0..<(end - offset) {
                output.append(data[data.startIndex + offset + idx] ^ keystream[idx])
            }

            blockIndex += 1
        }

        return output
    }

    // MARK: - CBC-MAC

    /// Compute 4-byte CBC-MAC tag.
    /// B_0 = [0x59] + nonce(13B) + [0x00, payload_length]
    /// X = AES(key, B_0)
    /// AAD = plaintext[0..<3] padded to 16 bytes
    /// X = AES(key, X XOR AAD)
    /// For each 16-byte payload block: X = AES(key, X XOR block)
    /// Return X[0..<4]
    private func computeCBCMAC(plaintext: Data, nonce: Data) throws -> Data {
        var macBlock = Data(count: 16)
        macBlock[0] = 0x59
        macBlock.replaceSubrange(1..<14, with: nonce)
        macBlock[14] = 0x00
        macBlock[15] = UInt8(plaintext.count & 0xFF)

        var macState = try AESHelper.encryptBlock(key: aesKey, plaintext: macBlock)

        // Associated data: first 3 bytes of plaintext, zero-padded to 16
        var aad = Data(count: 16)
        let aadLen = min(3, plaintext.count)
        for idx in 0..<aadLen {
            aad[idx] = plaintext[plaintext.startIndex + idx]
        }
        macState = try AESHelper.encryptBlock(key: aesKey, plaintext: xor(macState, aad))

        // Process payload blocks (from byte 3 onward)
        if plaintext.count > 3 {
            let payloadData = Data(plaintext[3...])
            for offset in stride(from: 0, to: payloadData.count, by: 16) {
                var block = Data(count: 16)
                let end = min(offset + 16, payloadData.count)
                for idx in 0..<(end - offset) {
                    block[idx] = payloadData[payloadData.startIndex + offset + idx]
                }
                macState = try AESHelper.encryptBlock(key: aesKey, plaintext: xor(macState, block))
            }
        }

        return macState.prefix(4)
    }

    // MARK: - Tag Encryption

    /// Encrypt the 4-byte MAC tag with A_0 keystream.
    /// A_0 = [0x01] + nonce(13B) + [0x00, 0x00]
    private func encryptTag(tag: Data, nonce: Data) throws -> Data {
        var counterBlock = Data(count: 16)
        counterBlock[0] = 0x01
        counterBlock.replaceSubrange(1..<14, with: nonce)
        counterBlock[14] = 0x00
        counterBlock[15] = 0x00

        let keystream = try AESHelper.encryptBlock(key: aesKey, plaintext: counterBlock)

        var encrypted = Data(count: 4)
        for idx in 0..<4 {
            encrypted[idx] = tag[idx] ^ keystream[idx]
        }
        return encrypted
    }

    private func decryptTag(encryptedTag: Data, nonce: Data) throws -> Data {
        // Tag decryption is the same operation as encryption (XOR is symmetric)
        return try encryptTag(tag: encryptedTag, nonce: nonce)
    }

    // MARK: - Helpers

    private func xor(_ dataA: Data, _ dataB: Data) -> Data {
        var result = Data(count: max(dataA.count, dataB.count))
        for idx in 0..<result.count {
            let byteA = idx < dataA.count ? dataA[dataA.startIndex + idx] : 0
            let byteB = idx < dataB.count ? dataB[dataB.startIndex + idx] : 0
            result[idx] = byteA ^ byteB
        }
        return result
    }
}

enum NinebotCryptoError: Error {
    case frameTooShort
    case macVerificationFailed
    case checksumMismatch
}
