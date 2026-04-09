//
//  AESHelper.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import CommonCrypto
import Foundation

enum AESError: Error {
    case encryptionFailed(status: CCCryptorStatus)
    case decryptionFailed(status: CCCryptorStatus)
    case invalidKeySize
    case invalidBlockSize
}

/// Single-block AES-128-ECB encrypt/decrypt using CommonCrypto.
/// CryptoKit doesn't expose raw ECB mode, so we use CCCrypt directly.
enum AESHelper {
    static let blockSize = 16
    static let keySize = 16

    /// Encrypt a single 16-byte block with AES-128-ECB.
    static func encryptBlock(key: Data, plaintext: Data) throws -> Data {
        guard key.count == keySize else {
            throw AESError.invalidKeySize
        }
        guard plaintext.count == blockSize else {
            throw AESError.invalidBlockSize
        }

        var outBuffer = Data(count: blockSize + kCCBlockSizeAES128)
        var outLength = 0

        let status = key.withUnsafeBytes { keyBytes in
            plaintext.withUnsafeBytes { inputBytes in
                outBuffer.withUnsafeMutableBytes { outBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, keySize,
                        nil,
                        inputBytes.baseAddress, blockSize,
                        outBytes.baseAddress, outBytes.count,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw AESError.encryptionFailed(status: status)
        }
        guard outLength == blockSize else {
            throw AESError.encryptionFailed(status: CCCryptorStatus(kCCUnspecifiedError))
        }

        return outBuffer.prefix(outLength)
    }

    /// Decrypt a single 16-byte block with AES-128-ECB.
    static func decryptBlock(key: Data, ciphertext: Data) throws -> Data {
        guard key.count == keySize else {
            throw AESError.invalidKeySize
        }
        guard ciphertext.count == blockSize else {
            throw AESError.invalidBlockSize
        }

        var outBuffer = Data(count: blockSize + kCCBlockSizeAES128)
        var outLength = 0

        let status = key.withUnsafeBytes { keyBytes in
            ciphertext.withUnsafeBytes { inputBytes in
                outBuffer.withUnsafeMutableBytes { outBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode),
                        keyBytes.baseAddress, keySize,
                        nil,
                        inputBytes.baseAddress, blockSize,
                        outBytes.baseAddress, outBytes.count,
                        &outLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw AESError.decryptionFailed(status: status)
        }
        guard outLength == blockSize else {
            throw AESError.decryptionFailed(status: CCCryptorStatus(kCCUnspecifiedError))
        }

        return outBuffer.prefix(outLength)
    }
}
