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
        bleLog("Discovered \(services.count) service(s)")
        for service in services {
            print("[GT3] [BLE] Service: \(service.uuid)")
            if service.uuid == BLEConstants.serviceUUID {
                bleLog("Found Ninebot service — discovering ALL characteristics…")
                peripheral.discoverCharacteristics(nil, for: service)
            } else {
                // Discover chars on other services too so we can log them
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        let isNinebot = service.uuid == BLEConstants.serviceUUID
        print("[GT3] [BLE] Chars for service \(service.uuid) (\(isNinebot ? "NINEBOT" : "other")):")
        for characteristic in characteristics {
            let props = characteristic.properties
            var propStr: [String] = []
            if props.contains(.read) { propStr.append("read") }
            if props.contains(.write) { propStr.append("write") }
            if props.contains(.writeWithoutResponse) { propStr.append("writeNoAck") }
            if props.contains(.notify) { propStr.append("notify") }
            if props.contains(.indicate) { propStr.append("indicate") }
            print("[GT3] [BLE] Char \(characteristic.uuid) props=[\(propStr.joined(separator: ","))]")

            switch characteristic.uuid {
            case BLEConstants.writeCharUUID where isNinebot:
                writeCharacteristic = characteristic
                bleLog("Found write characteristic (0002)")
                checkReadyForAuth()
            case BLEConstants.notifyCharUUID where isNinebot:
                notifyCharacteristic = characteristic
                bleLog("Found notify characteristic (0004)")
                checkReadyForAuth()
            default:
                break
            }

            // Subscribe to ANY notify/indicate char (except 0004, handled by toggleNotifications)
            if props.contains(.notify) || props.contains(.indicate),
               characteristic.uuid != BLEConstants.notifyCharUUID {
                print("[GT3] [BLE] Subscribing to extra notify char \(characteristic.uuid)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Log raw bytes immediately, before ANY guard — catch silent drops
        if let data = characteristic.value {
            print("[GT3] [BLE] <<< RAW notify on \(characteristic.uuid): \(data.hexString)")
        } else {
            print("[GT3] [BLE] <<< RAW notify on \(characteristic.uuid): (no data)")
        }

        guard let data = characteristic.value else { return }
        guard let transport = self.transport else {
            print("[GT3] [BLE] <<< transport=nil, dropping \(data.hexString)")
            return
        }

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

        // Fire beginAuthentication as soon as CCCD ON is ACK'd (event-driven, not timer)
        if characteristic.isNotifying,
           characteristic.uuid == BLEConstants.notifyCharUUID,
           pendingBeginAuthOnCCCDOn {
            pendingBeginAuthOnCCCDOn = false
            print("[GT3] [BLE] CCCD ON confirmed — starting auth now")
            beginAuthentication()
        }
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
