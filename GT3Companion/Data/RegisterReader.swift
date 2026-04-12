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

    /// Tracks which cumulative registers have been received.
    private var receivedCumulativeRegisters: Set<String> = []

    private static let snapshotKeyMap: [String: String] = [
        "rSN": "serialNumber",
        "rPreciseMileage": "odometer",
        "rMileage": "odometerRaw",
        "rRuntime": "totalRuntime",
        "rRideTime": "totalRideTime",
        "rCtrlV": "controllerFirmware",
        "rMCUV": "mcuFirmware",
        "rBmsV": "bms1Firmware",
        "rBms2V": "bms2Firmware",
        "rBleV": "bleFirmware",
        "rBms2CycleCountLT": "bms2CycleCount",
        "rBms2EnergyThroughputLT": "bms2EnergyThroughput",
        "rBms2CapacityThroughputLT": "bms2CapacityThroughput",
        "rBms2DeepDischargeCountLT": "bms2DeepDischargeCount",
        "rBms2RemainCapacityLT": "bms2RemainingCapacity",
        "rBms2ManufactureDateLT": "bms2ManufactureDate",
        "rBatterySN2": "batterySN",
        "rPN": "partNumber",
        "rTimeFull": "timeToFull",
        "rChargeStatus": "chargeStatus",
        "rMaxPower": "maxPower",
        "rBmsCapacity": "bmsDesignCapacity",
        "rBmsCellVolFrequence": "bmsCellVoltages",
        "rBmsTempFrequence": "bmsTempSensors",
        "rLedMode": "ledMode",
        "rProjectionLightMode": "projectionLightMode",
        "rTailLightMode": "tailLightMode",
        "rAlarmLevel": "alarmLevel",
        "rBumpyRoad": "bumpyRoad",
        "rVoiceVolume": "voiceVolume",
        "rGearED": "energyRecovery",
        "rGearSR": "speedResponse",
        "rFindMyStatus": "findMyStatus",
        "rFindMyEnable": "findMyEnable"
    ]

    func configure(sendFrame: @escaping FrameSender) {
        self.sendFrame = sendFrame
    }

    /// Read all cumulative registers once (on connect).
    func readCumulativeRegisters() async {
        receivedCumulativeRegisters.removeAll()
        for register in GT3Registers.cumulative {
            await readRegister(register)
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Wait until all cumulative registers have been received, or timeout.
    func awaitCumulativeData(timeoutSeconds: UInt64 = 10) async {
        if receivedCumulativeRegisters.count >= GT3Registers.cumulative.count {
            return
        }
        // Poll with short sleeps until all registers arrive or timeout expires
        let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
        while ContinuousClock.now < deadline {
            if receivedCumulativeRegisters.count >= GT3Registers.cumulative.count {
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
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
            if GT3Registers.cumulative.contains(where: { $0.name == register.name }) {
                receivedCumulativeRegisters.insert(register.name)
            }
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

    /// Return snapshot values mapped to server field names.
    func getDiagnosticSnapshot() -> [String: String] {
        var mapped = [String: String]()

        // Separate firmware versions and settings into nested JSON objects
        var firmwareVersions = [String: String]()
        var settings = [String: String]()
        let fwKeys: Set<String> = [
            "controllerFirmware", "mcuFirmware", "bms1Firmware",
            "bms2Firmware", "bleFirmware"
        ]
        let settingsKeys: Set<String> = [
            "ledMode", "projectionLightMode", "tailLightMode",
            "alarmLevel", "bumpyRoad", "voiceVolume",
            "energyRecovery", "speedResponse", "maxPower",
            "findMyStatus", "findMyEnable"
        ]

        for (registerName, value) in snapshotValues {
            let serverKey = Self.snapshotKeyMap[registerName] ?? registerName
            let stringValue = "\(value)"
            if fwKeys.contains(serverKey) {
                firmwareVersions[serverKey] = stringValue
            } else if settingsKeys.contains(serverKey) {
                settings[serverKey] = stringValue
            } else {
                mapped[serverKey] = stringValue
            }
        }

        // Encode firmware versions and settings as JSON strings
        if !firmwareVersions.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: firmwareVersions),
           let json = String(data: data, encoding: .utf8) {
            mapped["firmwareVersions"] = json
        }
        if !settings.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: settings),
           let json = String(data: data, encoding: .utf8) {
            mapped["settings"] = json
        }

        // Use bms2 values for bms1 columns too (GT3 Pro single-pack)
        if mapped["bms1CycleCount"] == nil, let bms2 = mapped["bms2CycleCount"] {
            mapped["bms1CycleCount"] = bms2
        }
        if mapped["bms1EnergyThroughput"] == nil, let bms2 = mapped["bms2EnergyThroughput"] {
            mapped["bms1EnergyThroughput"] = bms2
        }

        return mapped
    }

    /// Return a snapshot enriched with end-of-ride inferred values.
    func getEnrichedSnapshot(
        tripDistance: Double,
        rideDuration: TimeInterval
    ) -> [String: String] {
        var snapshot = getDiagnosticSnapshot()
        let rideDurationSeconds = Int(rideDuration.rounded())

        // Update odometer: add trip distance
        if let current = snapshot["odometer"], let currentVal = Double(current) {
            snapshot["odometer"] = "\(currentVal + tripDistance)"
        }
        // Update totalRideTime: add this ride's duration in whole seconds
        if let current = snapshot["totalRideTime"], let currentVal = Int(current) {
            snapshot["totalRideTime"] = "\(currentVal + rideDurationSeconds)"
        }
        // Update totalRuntime: add this ride's duration in whole seconds
        if let current = snapshot["totalRuntime"], let currentVal = Int(current) {
            snapshot["totalRuntime"] = "\(currentVal + rideDurationSeconds)"
        }

        return snapshot
    }
}
