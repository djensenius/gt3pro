//
//  ScooterKeychain.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import Security

enum ScooterKeychain {
    private static let service = "org.davidjensenius.GT3Companion"
    private static let account = "scooter_password"

    /// Saves a 32-character hex string as raw bytes in the Keychain.
    @discardableResult
    static func savePassword(hex: String) -> Bool {
        guard let data = Data(hexString: hex) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Returns the stored password as raw bytes, or nil if not set.
    static func loadPassword() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func hasPassword() -> Bool { loadPassword() != nil }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 32 else { return nil }
        var data = Data(capacity: 16)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }
}
