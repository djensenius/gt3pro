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

    init(crypto: NinebotCrypto, mtu: Int = BLEConstants.defaultMTU) {
        self.crypto = crypto
        self.mtu = mtu
    }

    func updateMTU(_ newMTU: Int) {
        self.mtu = newMTU
    }

    // MARK: - Outbound (app → device)

    /// Encrypt a plaintext frame and fragment into MTU-sized chunks.
    /// Returns an array of Data chunks to write sequentially with inter-fragment delay.
    func prepareOutbound(plaintextFrame: Data) throws -> [Data] {
        guard plaintextFrame.count >= 3 else { return [] }

        // Extract payload (everything after 3-byte header [5A, A5, LEN])
        let payload = Data(plaintextFrame[3...])

        // Encrypt
        let encrypted = try crypto.encrypt(plaintext: payload)

        // Build encrypted frame with header
        var frame = Data()
        frame.append(BLEConstants.syncByte1)
        frame.append(BLEConstants.syncByte2Encrypted)
        frame.append(UInt8(encrypted.count))
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
                reassemblyBuffer.append(byte)
                reassemblyState = .haveBegin
            } else {
                resetReassembly()
            }
            return nil

        case .haveBegin:
            reassemblyBuffer.append(byte)

            // Third byte after sync is the length
            if reassemblyBuffer.count == 3 {
                expectedLength = Int(byte) + 3 // total = header(3) + payload(length)
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
        let isEncrypted = frame[1] == BLEConstants.syncByte2Encrypted

        if isEncrypted {
            let encryptedPayload = Data(frame[3...])
            let decrypted = try crypto.decrypt(encrypted: encryptedPayload)

            // Rebuild as plaintext frame for parsing
            var plainFrame = Data()
            plainFrame.append(BLEConstants.syncByte1)
            plainFrame.append(BLEConstants.syncByte2Plain)
            plainFrame.append(UInt8(decrypted.count))
            plainFrame.append(decrypted)

            return NinebotFrameBuilder.parseFrame(plainFrame)
        } else {
            return NinebotFrameBuilder.parseFrame(frame)
        }
    }

    func resetReassembly() {
        reassemblyState = .idle
        reassemblyBuffer = Data()
        expectedLength = 0
    }
}
