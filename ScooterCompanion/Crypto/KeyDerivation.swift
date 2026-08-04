//
//  KeyDerivation.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import CryptoKit
import Foundation

/// Ninebot Encryption2 key derivation.
/// Derives a 16-byte AES key from two key components using SHA-1.
enum KeyDerivation {
    /// Derive a 16-byte AES key from a key pair.
    ///
    /// Algorithm:
    /// 1. Right-pad key1 to 16 bytes with 0x00
    /// 2. Right-pad key2 to 16 bytes with 0x00 (or use 16 zero bytes if nil)
    /// 3. Concatenate to 32 bytes
    /// 4. SHA-1 hash
    /// 5. Return first 16 bytes
    static func deriveKey(key1: Data, key2: Data?) -> Data {
        let paddedKey1 = pad(key1, to: 16)
        let paddedKey2 = key2.map { pad($0, to: 16) } ?? Data(count: 16)
        let combined = paddedKey1 + paddedKey2

        let hash = Insecure.SHA1.hash(data: combined)
        return Data(hash.prefix(16))
    }

    /// Right-pad data to the specified length with 0x00 bytes.
    /// If data is longer than length, truncate to length.
    private static func pad(_ data: Data, to length: Int) -> Data {
        if data.count >= length {
            return data.prefix(length)
        }
        var padded = data
        padded.append(contentsOf: [UInt8](repeating: 0x00, count: length - data.count))
        return padded
    }
}
