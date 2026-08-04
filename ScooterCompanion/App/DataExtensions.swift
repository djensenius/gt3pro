//
//  DataExtensions.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation

extension Data {
    /// Hex string representation for debug logging.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
