//
//  JavaLCG.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import CryptoKit
import Foundation

/// Exact port of Java's java.util.Random for Ninebot SET_PWD password generation.
/// The 48-bit LCG must produce identical output to Java for auth to succeed.
final class JavaLCG: @unchecked Sendable {
    private var seed: Int64

    init(seed: Int64) {
        self.seed = (seed ^ 0x5DEECE66D) & 0xFFFF_FFFF_FFFF
    }

    /// Advance state and return n bits.
    private func next(_ bits: Int) -> Int32 {
        seed = (seed &* 0x5DEECE66D &+ 0xB) & 0xFFFF_FFFF_FFFF
        return Int32(truncatingIfNeeded: seed >> (48 - bits))
    }

    func nextInt() -> Int32 {
        return next(32)
    }

    func nextInt(bound: Int32) -> Int32 {
        precondition(bound > 0)
        // Power of 2 fast path
        if bound & (bound &- 1) == 0 {
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(next(31))) >> 31)
        }
        // Rejection sampling
        var bits: Int32
        var val: Int32
        repeat {
            bits = next(31)
            val = bits % bound
        } while bits &- val &+ (bound &- 1) < 0
        return val
    }

    func nextBytes(count: Int) -> Data {
        var bytes = Data(count: count)
        var byteIndex = 0
        while byteIndex < count {
            var rnd = nextInt()
            var remaining = min(count - byteIndex, 4)
            while remaining > 0 {
                bytes[byteIndex] = UInt8(truncatingIfNeeded: rnd)
                rnd >>= 8
                remaining -= 1
                byteIndex += 1
            }
        }
        return bytes
    }

    /// Generate the 16-byte session password for SET_PWD.
    /// Seed = currentTimeMillis() + deriveSeedOffset(authParam)
    static func generatePassword(authParam: Data, timestampMs: Int64? = nil) -> Data {
        let timestamp = timestampMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        let offset = deriveSeedOffset(authParam: authParam)
        let lcg = JavaLCG(seed: timestamp &+ offset)
        let randomBytes = lcg.nextBytes(count: 16)
        let hash = SHA256.hash(data: randomBytes)
        return Data(hash.prefix(16))
    }

    /// Derive seed offset from auth_param using Java 32-bit int shift semantics.
    /// Combines bytes from auth_param with shifts masked by & 31.
    static func deriveSeedOffset(authParam: Data) -> Int64 {
        guard authParam.count >= 4 else { return 0 }
        let byte0 = Int32(authParam[0]) & 0xFF
        let byte1 = Int32(authParam[1]) & 0xFF
        let byte2 = Int32(authParam[2]) & 0xFF
        let byte3 = Int32(authParam[3]) & 0xFF
        let value = byte0 | (byte1 << (8 & 31)) | (byte2 << (16 & 31)) | (byte3 << (24 & 31))
        return Int64(value)
    }
}
