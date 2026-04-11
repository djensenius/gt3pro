//
//  RegisterReader.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "RegisterReader")

/// Result of processing a register read response.
struct RegisterReadResult: Sendable {
    let name: String
    let doubleValue: Double?
    let intValue: Int?
    let stringValue: String?
}

/// Orchestrates sequential register reads from the GT3 Pro.
/// Sends read commands one at a time, waits for responses, parses values.
actor RegisterReader {
    /// Callback type for sending a frame to the BLE transport.
    typealias FrameSender = @Sendable (Data) -> Void

    private var pendingRegister: RegisterDefinition?
    private var sendFrame: FrameSender?
    private var telemetryValues: [String: Any] = [:]
    private var snapshotValues: [String: Any] = [:]
    private var isPolling = false
    private var pollTask: Task<Void, Never>?

    func configure(sendFrame: @escaping FrameSender) {
        self.sendFrame = sendFrame
    }

    /// Read all cumulative registers once (on connect).
    func readCumulativeRegisters() async {
        for register in GT3Registers.cumulative {
            await readRegister(register)
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Start polling live telemetry registers at the given interval.
    func startPolling(intervalMs: UInt64 = 500) {
        guard !isPolling else { return }
        isPolling = true
        pollTask = Task { await self.pollLoop(intervalMs: intervalMs) }
    }

    private func pollLoop(intervalMs: UInt64) async {
        while isPolling && !Task.isCancelled {
            for register in GT3Registers.liveTelemetry {
                guard isPolling else { break }
                await readRegister(register)
                try? await Task.sleep(for: .milliseconds(25))
            }
            try? await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    func stopPolling() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
    }

    /// Send a read command for a single register.
    private func readRegister(_ register: RegisterDefinition) async {
        pendingRegister = register
        let frame = NinebotFrameBuilder.buildReadFrame(
            board: register.board,
            register: register.index,
            length: register.size
        )
        sendFrame?(frame)
    }

    /// Process a response frame from the scooter.
    /// Returns a RegisterReadResult if this was a register read response.
    func processResponse(_ parsed: NinebotFrameBuilder.ParsedFrame) -> RegisterReadResult? {
        guard parsed.cmd == BLEConstants.Command.readAck.rawValue else { return nil }

        let boardHex = String(parsed.btID, radix: 16)
        let indexHex = String(parsed.index, radix: 16)
        let payloadHex = parsed.payload.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("[GT3] [REG] board=0x\(boardHex) idx=0x\(indexHex) len=\(parsed.payload.count) data=[\(payloadHex)]")

        // Match on board + index only; payload size may differ from definition
        let matchingRegister = GT3Registers.all.first { register in
            register.board.rawValue == parsed.btID
            && register.index == parsed.index
        }

        guard let register = matchingRegister else {
            print("[GT3] [REG] ⚠️ UNMATCHED board=0x\(boardHex) idx=0x\(indexHex)")
            return nil
        }

        let value = TelemetryParser.parseRegister(register, data: parsed.payload)
        print("[GT3] [REG] ✅ \(register.name) = \(value)")

        if GT3Registers.liveTelemetry.contains(where: { $0.name == register.name }) {
            telemetryValues[register.name] = value
        } else {
            snapshotValues[register.name] = value
        }

        return RegisterReadResult(
            name: register.name,
            doubleValue: value as? Double,
            intValue: value as? Int,
            stringValue: value as? String
        )
    }

    // MARK: - Telemetry Accessors

    func getTelemetryDouble(_ key: String) -> Double? { telemetryValues[key] as? Double }
    func getTelemetryInt(_ key: String) -> Int? { telemetryValues[key] as? Int }
    func getTelemetryCount() -> Int { telemetryValues.count }
    func isTelemetryEmpty() -> Bool { telemetryValues.isEmpty }

    // MARK: - Snapshot Accessors

    func getSnapshotDouble(_ key: String) -> Double? { snapshotValues[key] as? Double }
    func getSnapshotInt(_ key: String) -> Int? { snapshotValues[key] as? Int }
    func getSnapshotCount() -> Int { snapshotValues.count }
    func isSnapshotEmpty() -> Bool { snapshotValues.isEmpty }

    func clearTelemetry() { telemetryValues.removeAll() }

    /// Return snapshot values as a string dictionary for upload.
    func getDiagnosticSnapshot() -> [String: String] {
        snapshotValues.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = "\(pair.value)"
        }
    }
}
