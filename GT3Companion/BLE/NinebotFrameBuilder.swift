//
//  NinebotFrameBuilder.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

enum NinebotFrameBuilder {
    /// Build a read register command frame.
    /// - Parameters:
    ///   - board: Target board (e.g., .vcu, .bms1)
    ///   - register: Register address (index byte)
    ///   - length: Number of bytes to read
    static func buildReadFrame(board: BLEConstants.Board, register: UInt8, length: UInt8) -> Data {
        let data = Data([length])
        return buildFrame(
            target: board.rawValue,
            cmd: BLEConstants.Command.read.rawValue,
            index: register,
            data: data
        )
    }

    /// Build a write register command frame.
    static func buildWriteFrame(board: BLEConstants.Board, register: UInt8, data: Data) -> Data {
        return buildFrame(
            target: board.rawValue,
            cmd: BLEConstants.Command.write.rawValue,
            index: register,
            data: data
        )
    }

    /// Build an auth command frame (PRE_COMM, SET_PWD, AUTH).
    static func buildAuthFrame(cmd: BLEConstants.Command, data: Data) -> Data {
        return buildFrame(
            target: BLEConstants.Board.ble.rawValue,
            cmd: cmd.rawValue,
            index: 0x00,
            data: data
        )
    }

    /// Build a raw Ninebot frame.
    /// Layout: [0x5A, 0xA5, LEN, BT_ID, TARGET, CMD, INDEX, DATA...]
    /// LEN = data.count + 4 (covers BT_ID, TARGET, CMD, INDEX, and DATA)
    private static func buildFrame(target: UInt8, cmd: UInt8, index: UInt8, data: Data) -> Data {
        let len = UInt8(data.count + 4)

        var frame = Data()
        frame.append(BLEConstants.syncByte1)
        frame.append(BLEConstants.syncByte2Plain)
        frame.append(len)
        frame.append(BLEConstants.btID)
        frame.append(target)
        frame.append(cmd)
        frame.append(index)
        frame.append(data)
        return frame
    }

    /// Parse a received frame's fields (after decryption).
    /// Returns nil if the frame is too short, has invalid sync bytes,
    /// or the length field doesn't match the actual frame size.
    static func parseFrame(_ frame: Data) -> ParsedFrame? {
        guard frame.count >= 7 else { return nil }
        guard frame[0] == BLEConstants.syncByte1 else { return nil }
        guard frame[1] == BLEConstants.syncByte2Plain
            || frame[1] == BLEConstants.syncByte2Encrypted else { return nil }

        let length = frame[2]
        // Validate: frame should be exactly 3 (header) + length bytes
        guard length >= 4, frame.count == Int(length) + 3 else { return nil }

        let btID = frame[3]
        let source = frame[4]
        let cmd = frame[5]
        let index = frame[6]
        let payload = frame.count > 7 ? Data(frame[7...]) : Data()

        return ParsedFrame(
            length: length,
            btID: btID,
            source: source,
            cmd: cmd,
            index: index,
            payload: payload
        )
    }

    struct ParsedFrame: Sendable {
        let length: UInt8
        let btID: UInt8
        let source: UInt8
        let cmd: UInt8
        let index: UInt8
        let payload: Data
    }
}
