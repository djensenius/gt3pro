//
//  BLEConstants.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import CoreBluetooth
import Foundation

/// Ninebot BLE protocol constants for the GT3 Pro.
enum BLEConstants {
    // MARK: - Service & Characteristic UUIDs
    // UUID suffix 006e-696e65626f74 decodes to \x00ninebot in ASCII

    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "6E400001-0000-0000-006E-696E65626F74")

    /// Write characteristic (app → device)
    nonisolated(unsafe) static let writeCharUUID = CBUUID(
        string: "6E400002-0000-0000-006E-696E65626F74"
    )

    /// RCTP secondary write channel — NOT the notify characteristic
    nonisolated(unsafe) static let rctpWriteCharUUID = CBUUID(
        string: "6E400003-0000-0000-006E-696E65626F74"
    )

    /// Notify characteristic (device → app). CRITICAL: This is 0004, NOT 0003.
    nonisolated(unsafe) static let notifyCharUUID = CBUUID(
        string: "6E400004-0000-0000-006E-696E65626F74"
    )

    /// Secondary write characteristic (app → device). May be the auth channel.
    nonisolated(unsafe) static let authWriteCharUUID = CBUUID(
        string: "6E400005-0000-0000-006E-696E65626F74"
    )

    /// Secondary notify characteristic (device → app). May be the auth response channel.
    nonisolated(unsafe) static let authNotifyCharUUID = CBUUID(
        string: "6E400006-0000-0000-006E-696E65626F74"
    )

    // MARK: - Board Target IDs

    enum Board: UInt8 {
        case ble = 0x04
        case vcu = 0x02  // ESC / Vehicle Control Unit
        case mcu = 0x05
        case bms1 = 0x06
        case bms2 = 0x07
        case tft = 0x09
    }

    // MARK: - Frame Constants

    /// Bluetooth frame ID (always 0x3E in outbound frames)
    static let btID: UInt8 = 0x3E

    /// Sync bytes for plaintext frames
    static let syncByte1: UInt8 = 0x5A
    static let syncByte2Plain: UInt8 = 0xA5
    static let syncByte2Encrypted: UInt8 = 0xB5

    // MARK: - Command Bytes

    enum Command: UInt8 {
        case read = 0x01
        case readAck = 0x04
        case write = 0x03
        case writeAck = 0x05
        case preComm = 0x5B
        case setPwd = 0x5C
        case auth = 0x5D
    }

    // MARK: - Timing

    /// Default BLE MTU (negotiated higher where possible)
    static let defaultMTU = 23

    /// Payload size per fragment = MTU - 3 (ATT overhead)
    static let defaultFragmentSize = defaultMTU - 3

    /// Inter-fragment write delay
    static let fragmentDelayMs: UInt64 = 10

    /// CCCD toggle delay before auth (workaround for iOS stale notifications)
    static let cccdToggleOffDelayMs: UInt64 = 300
    static let cccdDrainDelayMs: UInt64 = 200

    /// Auth phase timeouts
    static let preCommTimeoutMs: UInt64 = 2000
    static let setPwdTimeoutMs: UInt64 = 2000
    static let authTimeoutMs: UInt64 = 2000
    static let setPwdMaxRetries = 30
    static let preCommMaxRetries = 10
    static let authMaxRetries = 3
    static let authMaxRestarts = 5

    /// Echo detection retry delays (escalating)
    static let echoRetryDelays: [UInt64] = [1000, 2000]

    // MARK: - State Restoration

    static let centralManagerRestoreID = "GT3CompanionCentral"

    // MARK: - Device Identification

    /// GT3 hardware ID
    static let hardwareID: UInt16 = 0x0101

    /// GT3 server ID
    static let serverID: UInt16 = 10257

    /// BLE advertising name patterns (varies by firmware version)
    static let advertisingNamePrefixes = ["NB-", "Segway Scooter"]
}
