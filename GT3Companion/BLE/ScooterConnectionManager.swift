//
//  ScooterConnectionManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "BLE")

/// Connection states for the BLE lifecycle.
enum ConnectionState: Sendable {
    case disconnected
    case scanning
    case connecting
    case discovering
    case authenticating
    case connected
    case reconnecting
}

/// Delegate protocol for ScooterConnectionManager events.
protocol ScooterConnectionDelegate: AnyObject, Sendable {
    func connectionStateChanged(_ state: ConnectionState)
    func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame)
    func didAuthenticate(serialNumber: String)
    func didDisconnect(error: Error?)
}

/// Actor wrapping CBCentralManager for the full GT3 Pro BLE lifecycle.
///
/// Responsibilities:
/// - Scanning for GT3 Pro by service UUID
/// - Connecting with state restoration
/// - Service/characteristic discovery
/// - MTU negotiation
/// - Frame I/O via NinebotTransport
/// - Authentication via NinebotAuth
/// - Bonded device workarounds (CCCD toggle, echo detection)
final class ScooterConnectionManager: NSObject, @unchecked Sendable {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var transport: NinebotTransport?
    private var auth: NinebotAuth?
    private var mtu: Int = BLEConstants.defaultMTU

    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            logger.info("Connection state: \(String(describing: self.connectionState))")
            delegate?.connectionStateChanged(connectionState)
        }
    }

    weak var delegate: ScooterConnectionDelegate?

    private var btName: String?
    private var storedPassword: Data?
    private var echoRetryCount = 0
    private let bleQueue = DispatchQueue(label: "io.fluxhaus.GT3Companion.ble", qos: .userInitiated)

    override init() {
        super.init()
    }

    /// Initialize the central manager with state restoration.
    func start(storedPassword: Data? = nil) {
        self.storedPassword = storedPassword
        centralManager = CBCentralManager(
            delegate: self,
            queue: bleQueue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralManagerRestoreID
            ]
        )
    }

    /// Start scanning for GT3 Pro devices.
    func scan() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not powered on")
            return
        }

        // Check for already-connected (bonded) peripherals first
        let connected = centralManager.retrieveConnectedPeripherals(
            withServices: [BLEConstants.serviceUUID]
        )
        if let existing = connected.first {
            logger.info("Found bonded peripheral: \(existing.name ?? "unknown")")
            connectToPeripheral(existing)
            return
        }

        connectionState = .scanning
        centralManager.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Scanning for GT3 Pro...")
    }

    /// Disconnect from the peripheral.
    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
    }

    // MARK: - Private Helpers

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        logger.info("Connecting to \(peripheral.name ?? "unknown")...")
    }

    private func discoverServices() {
        connectionState = .discovering
        peripheral?.discoverServices([BLEConstants.serviceUUID])
    }

    /// CCCD toggle workaround for iOS stale notifications on reconnect.
    private func toggleNotifications() {
        guard let peripheral = peripheral, let characteristic = notifyCharacteristic else { return }

        peripheral.setNotifyValue(false, for: characteristic)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(BLEConstants.cccdToggleOffDelayMs))) {
            peripheral.setNotifyValue(true, for: characteristic)
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(Int(BLEConstants.cccdDrainDelayMs))
            ) { [weak self] in
                self?.beginAuthentication()
            }
        }
    }

    private func beginAuthentication() {
        guard let name = btName else {
            logger.error("No BT name available for auth")
            return
        }

        connectionState = .authenticating
        let authActor = NinebotAuth(btName: name, storedPassword: storedPassword)
        self.auth = authActor

        let key = KeyDerivation.deriveKey(key1: Data(name.utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)
        self.transport = NinebotTransport(crypto: crypto, mtu: mtu)

        Task {
            let frame = await authActor.startAuth()
            sendFrame(frame)
        }
    }

    private func sendFrame(_ frame: Data) {
        guard let characteristic = writeCharacteristic, let peripheral = peripheral else {
            logger.error("Cannot send: no write characteristic")
            return
        }

        Task {
            guard let transport = self.transport else { return }
            do {
                let chunks = try await transport.prepareOutbound(plaintextFrame: frame)
                for (index, chunk) in chunks.enumerated() {
                    peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                    if index < chunks.count - 1 {
                        try await Task.sleep(for: .milliseconds(BLEConstants.fragmentDelayMs))
                    }
                }
            } catch {
                logger.error("Failed to send frame: \(error)")
            }
        }
    }

    private func handleAuthResponse(_ parsed: NinebotFrameBuilder.ParsedFrame) {
        guard let auth = self.auth else { return }

        Task {
            let nextFrame = await auth.processResponse(parsed)
            let state = await auth.state

            switch state {
            case .authenticated:
                let serial = await auth.getSerialNumber() ?? "unknown"
                logger.info("Authenticated with GT3 Pro (SN: \(serial))")
                connectionState = .connected
                delegate?.didAuthenticate(serialNumber: serial)

            case .failed(let reason):
                logger.error("Auth failed: \(reason)")
                connectionState = .disconnected
                disconnect()

            default:
                if let frame = nextFrame {
                    if case .setPwd = state {
                        // Wait 2s between SET_PWD retries
                        try? await Task.sleep(for: .seconds(2))
                    }
                    sendFrame(frame)
                }
            }
        }
    }

    /// Detect echo bug: device echoes back writes instead of processing them.
    private func isEcho(sent: Data, received: Data) -> Bool {
        sent == received
    }

    private func handleEchoRetry() {
        guard echoRetryCount < BLEConstants.echoRetryDelays.count else {
            logger.error("Echo detection: max retries exceeded")
            connectionState = .disconnected
            return
        }

        let delay = BLEConstants.echoRetryDelays[echoRetryCount]
        echoRetryCount += 1
        logger.warning("Echo detected, retrying in \(delay)ms (attempt \(self.echoRetryCount))")

        disconnect()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(delay))) { [weak self] in
            self?.scan()
        }
    }

    /// Issue a persistent connection request for background reconnection.
    func watchForReconnection() {
        guard let peripheral = peripheral else { return }
        connectionState = .reconnecting
        centralManager.connect(peripheral, options: nil)
        logger.info("Watching for GT3 Pro reconnection...")
    }
}

// MARK: - CBCentralManagerDelegate

extension ScooterConnectionManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Central manager state: \(central.state.rawValue)")
        if central.state == .poweredOn {
            scan()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        logger.info("Restoring BLE state")
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let restored = peripherals.first {
            self.peripheral = restored
            restored.delegate = self
            if restored.state == .connected {
                discoverServices()
            } else {
                connectToPeripheral(restored)
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        logger.info("Discovered: \(name) RSSI: \(RSSI)")

        if name.hasPrefix(BLEConstants.advertisingNamePrefix) || !name.isEmpty {
            btName = name
            connectToPeripheral(peripheral)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        logger.info("Connected to \(peripheral.name ?? "unknown")")
        echoRetryCount = 0

        // Negotiate MTU
        let negotiatedMTU = peripheral.maximumWriteValueLength(for: .withResponse) + 3
        if negotiatedMTU > BLEConstants.defaultMTU {
            mtu = negotiatedMTU
            logger.info("Negotiated MTU: \(self.mtu)")
        }

        discoverServices()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        connectionState = .disconnected
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.info("Disconnected: \(error?.localizedDescription ?? "clean")")
        delegate?.didDisconnect(error: error)
        watchForReconnection()
    }
}

// MARK: - CBPeripheralDelegate

extension ScooterConnectionManager: CBPeripheralDelegate {
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLEConstants.serviceUUID {
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
                logger.info("Found write characteristic")
            case BLEConstants.notifyCharUUID:
                notifyCharacteristic = characteristic
                logger.info("Found notify characteristic (0004)")
                toggleNotifications()
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

        Task {
            do {
                if let parsed = try await transport.processInbound(chunk: data) {
                    if connectionState == .authenticating {
                        handleAuthResponse(parsed)
                    } else if connectionState == .connected {
                        delegate?.didReceiveTelemetry(parsed)
                    }
                }
            } catch {
                logger.error("Frame processing error: \(error)")
            }
        }
    }
}
#endif
