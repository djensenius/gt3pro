//
//  ScooterPeripheralDelegate.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreBluetooth

// MARK: - CBPeripheralDelegate

extension ScooterConnectionManager: CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let error {
            bleLog("Service discovery error: \(error.localizedDescription)", level: .error)
            return
        }
        guard let services = peripheral.services else {
            bleLog("No services found on peripheral", level: .warning)
            return
        }
        bleLog("Discovered \(services.count) service(s) — looking for Ninebot service")
        for service in services where service.uuid == BLEConstants.serviceUUID {
            bleLog("Found Ninebot service — discovering characteristics…")
            peripheral.discoverCharacteristics(
                [BLEConstants.writeCharUUID, BLEConstants.notifyCharUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case BLEConstants.writeCharUUID:
                writeCharacteristic = characteristic
                bleLog("Found write characteristic (0002)")
                checkReadyForAuth()
            case BLEConstants.notifyCharUUID:
                notifyCharacteristic = characteristic
                bleLog("Found notify characteristic (0004)")
                checkReadyForAuth()
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BLEConstants.notifyCharUUID,
              let data = characteristic.value else { return }

        guard let transport = self.transport else { return }

        print("[GT3] [BLE] didUpdateValueFor (notify): \(data.hexString)")
        Task {
            do {
                if let parsed = try await transport.processInbound(chunk: data) {
                    if connectionState == .authenticating {
                        bleLog(
                            "Auth frame received — cmd: 0x\(String(parsed.cmd, radix: 16)) idx: \(parsed.index)",
                            level: .debug
                        )
                        handleAuthResponse(parsed)
                    } else if connectionState == .connected {
                        Task { @MainActor [weak self] in
                            self?.delegate?.didReceiveTelemetry(parsed)
                        }
                    }
                }
            } catch {
                bleLog("Frame processing error: \(error)", level: .error)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            bleLog("CCCD update failed for \(characteristic.uuid): \(error.localizedDescription)", level: .error)
            print("[GT3] [BLE] CCCD ERROR: \(characteristic.uuid) — \(error.localizedDescription)")
            return
        }
        let state = characteristic.isNotifying ? "ON" : "OFF"
        bleLog("CCCD \(state) for \(characteristic.uuid)")
        print("[GT3] [BLE] CCCD \(state) for \(characteristic.uuid)")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            bleLog("Write failed for \(characteristic.uuid): \(error.localizedDescription)", level: .error)
            print("[GT3] [BLE] Write ERROR: \(characteristic.uuid) — \(error.localizedDescription)")
        } else {
            print("[GT3] [BLE] Write ACK: \(characteristic.uuid)")
        }
    }
}
#endif
