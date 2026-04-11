//
//  NinebotTransport.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

/// Reassembly state machine for inbound BLE notifications.
enum ReassemblyState {
    case idle
    case haveHead
    case haveBegin
}

/// BLE transport layer: fragmentation for outbound frames, reassembly for inbound.
actor NinebotTransport {
    private let crypto: NinebotCrypto
    private var mtu: Int

    // Reassembly state
    private var reassemblyState: ReassemblyState = .idle
    private var reassemblyBuffer = Data()
    private var expectedLength: Int = 0
    private var inboundIsEncrypted = false
    /// When true, 5AA5-prefixed frames are treated as encrypted (GT3 Pro uses 5AA5 for everything).
    private var encryptionActive = false

    init(crypto: NinebotCrypto, mtu: Int = BLEConstants.defaultMTU) {
        self.crypto = crypto
        self.mtu = mtu
    }

    func updateMTU(_ newMTU: Int) {
        self.mtu = newMTU
    }

    /// Tell the transport that encryption is now active.
    /// After this, incoming 5AA5 frames will be treated as encrypted (LEN + 3 total).
    func setEncryptionActive() {
        encryptionActive = true
        print("[GT3] [TRANSPORT] Encryption active — 5AA5 frames will be decrypted")
    }

    // MARK: - Outbound (app → device)

    /// Encrypt a plaintext frame and fragment into MTU-sized chunks.
    /// Returns an array of Data chunks to write sequentially with inter-fragment delay.
    func prepareOutbound(plaintextFrame: Data) throws -> [Data] {
        guard plaintextFrame.count >= 3 else { return [] }
        print("[GT3] [TRANSPORT] prepareOutbound: \(plaintextFrame.hexString)")

        // Extract payload (everything after 3-byte header [5A, A5, LEN])
        let payload = Data(plaintextFrame[3...])

        // Encrypt
        let encrypted = try crypto.encrypt(plaintext: payload)
        print("[GT3] [TRANSPORT] encrypted payload: \(encrypted.hexString)")

        // Build encrypted frame — preserve original LEN byte from plaintext frame
        var frame = Data()
        frame.append(BLEConstants.syncByte1)
        frame.append(BLEConstants.syncByte2Plain)
        frame.append(plaintextFrame[2])
        frame.append(encrypted)

        // Fragment
        return fragment(frame)
    }

    /// Fragment data into MTU-sized chunks.
    func fragment(_ data: Data) -> [Data] {
        let chunkSize = mtu - 3 // ATT overhead
        guard chunkSize > 0 else { return [data] }

        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            chunks.append(Data(data[offset..<end]))
            offset = end
        }
        return chunks
    }

    // MARK: - Inbound (device → app)

    /// Feed a notification chunk. Returns a decrypted parsed frame when
    /// reassembly is complete, or nil if more data is needed.
    func processInbound(chunk: Data) throws -> NinebotFrameBuilder.ParsedFrame? {
        for byte in chunk {
            if let frame = try processInboundByte(byte) {
                return frame
            }
        }
        return nil
    }

    private func processInboundByte(
        _ byte: UInt8
    ) throws -> NinebotFrameBuilder.ParsedFrame? {
        switch reassemblyState {
        case .idle:
            if byte == BLEConstants.syncByte1 {
                reassemblyBuffer = Data([byte])
                reassemblyState = .haveHead
            }
            return nil

        case .haveHead:
            if byte == BLEConstants.syncByte2Plain || byte == BLEConstants.syncByte2Encrypted {
                // GT3 Pro uses 5AA5 for both plain AND encrypted frames.
                // If encryption is active, 5AA5 = encrypted. 5AB5 always = encrypted.
                inboundIsEncrypted = (byte == BLEConstants.syncByte2Encrypted) || encryptionActive
                reassemblyBuffer.append(byte)
                reassemblyState = .haveBegin
            } else {
                resetReassembly()
            }
            return nil

        case .haveBegin:
            reassemblyBuffer.append(byte)

            // Third byte after sync is the length.
            // GT3 Pro plain frames: LEN = data bytes only, total frame = LEN + 9
            // (5A + A5 + LEN + SRC + DEST + CMD + INDEX + DATA(LEN) + CHK_LO + CHK_HI)
            // Encrypted frames: total = LEN + 13
            // (5A + A5 + LEN + encrypted_payload(LEN+4) + tail(6))
            if reassemblyBuffer.count == 3 {
                if inboundIsEncrypted {
                    expectedLength = Int(byte) + 13
                } else {
                    expectedLength = Int(byte) + 9
                }
            }

            if reassemblyBuffer.count >= expectedLength && expectedLength > 3 {
                let completeFrame = reassemblyBuffer
                resetReassembly()
                return try decryptAndParse(completeFrame)
            }
            return nil
        }
    }

    private func decryptAndParse(
        _ frame: Data
    ) throws -> NinebotFrameBuilder.ParsedFrame? {
        // GT3 Pro uses 5AA5 for ALL frames. Use the encryptionActive flag set after
        // PRE_COMM response, or check for 5AB5 (other Ninebot scooters).
        let isEncrypted = encryptionActive || frame[1] == BLEConstants.syncByte2Encrypted
        print("[GT3] [TRANSPORT] decryptAndParse: \(frame.hexString) isEncrypted=\(isEncrypted)")

        if isEncrypted {
            let encryptedPayload = Data(frame[3...])
            let decrypted = try crypto.decrypt(encrypted: encryptedPayload)
            print("[GT3] [TRANSPORT] decrypted: \(decrypted.hexString)")

            // Rebuild as plaintext frame for parsing.
            // LEN = data bytes count (GT3 Pro format: payload = BT_ID+TARGET+CMD+INDEX+DATA).
            let dataLen = max(0, decrypted.count - 4)
            var plainFrame = Data()
            plainFrame.append(BLEConstants.syncByte1)
            plainFrame.append(BLEConstants.syncByte2Plain)
            plainFrame.append(UInt8(dataLen))
            plainFrame.append(decrypted)

            return NinebotFrameBuilder.parseFrame(plainFrame)
        } else {
            // Strip the trailing 2-byte checksum before parsing.
            guard frame.count >= 5 else { return nil }
            let stripped = Data(frame[..<(frame.count - 2)])
            return NinebotFrameBuilder.parseFrame(stripped)
        }
    }

    func resetReassembly() {
        reassemblyState = .idle
        reassemblyBuffer = Data()
        expectedLength = 0
        inboundIsEncrypted = false
    }
}
