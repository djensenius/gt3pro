//
//  ScooterConnectionManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
@preconcurrency import CoreBluetooth
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "BLE")

/// Connection states for the BLE lifecycle.
enum ConnectionState: Sendable, Equatable, CaseIterable {
    case disconnected
    case scanning
    case connecting
    case discovering
    case authenticating
    case connected
    case reconnecting
}

/// Delegate protocol for ScooterConnectionManager events.
/// Callbacks are dispatched to the main actor for safe UI updates.
@MainActor
protocol ScooterConnectionDelegate: AnyObject {
    func connectionStateChanged(_ state: ConnectionState)
    func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame)
    func didAuthenticate(serialNumber: String)
    func didDisconnect(error: Error?)
}

/// CBCentralManager wrapper managing the full GT3 Pro BLE lifecycle.
///
/// All CoreBluetooth interactions are serialized on `bleQueue`.
/// Uses NinebotAuth for handshake and NinebotTransport for encrypted frame I/O.
final class ScooterConnectionManager: NSObject, @unchecked Sendable {
    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var transport: NinebotTransport?
    private var auth: NinebotAuth?
    private var mtu: Int = BLEConstants.defaultMTU
    private var intentionalDisconnect = false

    private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            logger.info("Connection state: \(String(describing: self.connectionState))")
            let state = connectionState
            Task { @MainActor [weak self] in
                self?.delegate?.connectionStateChanged(state)
            }
        }
    }

    weak var delegate: (any ScooterConnectionDelegate)?

    private var btName: String?
    private var rawBtName: String?
    private var storedPassword: Data?
    private var echoRetryCount = 0
    private let bleQueue = DispatchQueue(label: "org.davidjensenius.GT3Companion.ble", qos: .userInitiated)

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
        guard let central = centralManager, central.state == .poweredOn else {
            logger.warning("Cannot scan: Bluetooth not ready (centralManager not started or not powered on)")
            return
        }

        // Try previously-seen peripheral UUID first (fastest path), but only
        // short-circuit when CoreBluetooth already reports it as connected.
        if let savedUUID = ScooterConnectionManager.loadPeripheralUUID() {
            let known = central.retrievePeripherals(withIdentifiers: [savedUUID])
            if let existing = known.first, existing.state == .connected {
                btName = existing.name
                logger.info("Reconnecting to saved connected peripheral: \(self.btName ?? "unknown")")
                connectToPeripheral(existing)
                return
            }
        }

        // Check for already-connected (bonded) peripherals
        let connected = central.retrieveConnectedPeripherals(
            withServices: [BLEConstants.serviceUUID]
        )
        if let existing = connected.first {
            btName = existing.name
            logger.info("Found bonded peripheral: \(self.btName ?? "unknown")")
            connectToPeripheral(existing)
            return
        }

        connectionState = .scanning
        central.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Scanning for GT3 Pro...")
    }

    // MARK: - Peripheral UUID Persistence

    private static let peripheralUUIDKey = "GT3Companion.peripheralUUID"

    static func savePeripheralUUID(_ uuid: UUID, defaults: UserDefaults = .standard) {
        defaults.set(uuid.uuidString, forKey: peripheralUUIDKey)
    }

    static func loadPeripheralUUID(defaults: UserDefaults = .standard) -> UUID? {
        guard let str = defaults.string(forKey: peripheralUUIDKey) else { return nil }
        return UUID(uuidString: str)
    }

    /// Disconnect from the peripheral intentionally (no auto-reconnect).
    func disconnect() {
        intentionalDisconnect = true
        if let peripheral = peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectionState = .disconnected
    }

    // MARK: - Private Helpers

    private func connectToPeripheral(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        intentionalDisconnect = false
        centralManager?.stopScan()
        centralManager?.connect(peripheral, options: nil)
        logger.info("Connecting to \(peripheral.name ?? "unknown")...")
    }

    private func discoverServices() {
        connectionState = .discovering
        peripheral?.discoverServices([BLEConstants.serviceUUID])
    }

    /// Try to begin auth if both characteristics are discovered.
    private func checkReadyForAuth() {
        guard writeCharacteristic != nil, notifyCharacteristic != nil else { return }
        toggleNotifications()
    }

    /// CCCD toggle workaround for iOS stale notifications on reconnect.
    /// All CB calls stay on bleQueue for proper serialization.
    private func toggleNotifications() {
        guard let peripheral = peripheral, let characteristic = notifyCharacteristic else { return }

        bleQueue.async { [weak self] in
            peripheral.setNotifyValue(false, for: characteristic)
            self?.bleQueue.asyncAfter(
                deadline: .now() + .milliseconds(Int(BLEConstants.cccdToggleOffDelayMs))
            ) { [weak self] in
                peripheral.setNotifyValue(true, for: characteristic)
                self?.bleQueue.asyncAfter(
                    deadline: .now() + .milliseconds(Int(BLEConstants.cccdDrainDelayMs))
                ) { [weak self] in
                    self?.beginAuthentication()
                }
            }
        }
    }

    private func beginAuthentication() {
        guard let name = btName else {
            logger.error("No BT name available for auth")
            return
        }

        connectionState = .authenticating

        // Strip leading emoji/whitespace — iOS may decorate the name (e.g. "🛴 Segway Scooter0023")
        // but the scooter firmware uses the plain name for key derivation
        let authName = ScooterConnectionManager.sanitizeBLEName(name)
        logger.info("Raw BT name: \(name) → auth name: \(authName) (bytes: \(Data(authName.utf8).count))")

        // Single shared crypto instance for both auth and transport
        let key = KeyDerivation.deriveKey(key1: Data(authName.utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)

        let authActor = NinebotAuth(btName: authName, storedPassword: storedPassword)
        self.auth = authActor
        self.transport = NinebotTransport(crypto: crypto, mtu: mtu)

        Task {
            let frame = await authActor.startAuth()
            sendFrame(frame)
        }
    }

    /// Strips leading emoji and whitespace from a BLE device name.
    /// iOS may prepend decorative emoji (e.g. 🛴) to the advertised name.
    static func sanitizeBLEName(_ name: String) -> String {
        let stripped = String(name.drop { char in
            char.isWhitespace || char.unicodeScalars.allSatisfy { scalar in
                scalar.properties.isEmoji && !scalar.properties.isASCIIHexDigit
            }
        })
        return stripped.isEmpty ? name : stripped
    }

    func sendFrame(_ frame: Data) {
        guard let characteristic = writeCharacteristic, let peripheral = peripheral else {
            logger.error("Cannot send: write characteristic not available")
            return
        }

        Task {
            guard let transport = self.transport else { return }
            do {
                let chunks = try await transport.prepareOutbound(plaintextFrame: frame)
                // Dispatch writes back to bleQueue for CB serialization
                self.bleQueue.async {
                    for (index, chunk) in chunks.enumerated() {
                        peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                        if index < chunks.count - 1 {
                            Thread.sleep(forTimeInterval: Double(BLEConstants.fragmentDelayMs) / 1000.0)
                        }
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
                // Persist peripheral UUID only after successful auth
                if let peripheralID = self.peripheral?.identifier {
                    ScooterConnectionManager.savePeripheralUUID(peripheralID)
                }
                Task { @MainActor [weak self] in
                    self?.delegate?.didAuthenticate(serialNumber: serial)
                }

            case .failed(let reason):
                logger.error("Auth failed: \(reason)")
                connectionState = .disconnected
                disconnect()

            default:
                if let frame = nextFrame {
                    if case .setPwd = state {
                        try? await Task.sleep(for: .seconds(2))
                    }
                    sendFrame(frame)
                }
            }
        }
    }

    /// Issue a persistent connection request for background reconnection.
    func watchForReconnection() {
        guard let peripheral = peripheral else { return }
        connectionState = .reconnecting
        centralManager?.connect(peripheral, options: nil)
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
            self.btName = restored.name
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
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        logger.info("Discovered: \(name ?? "(no name)") RSSI: \(RSSI)")

        guard let name, !name.isEmpty else {
            logger.warning("Skipping device with no name — key derivation requires a valid BT name")
            return
        }

        // Service UUID filter in scanForPeripherals is sufficient —
        // device names vary by firmware ("NB-...", "Segway Scooter...", may include emoji)
        rawBtName = name
        btName = name
        connectToPeripheral(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        logger.info("Connected to \(peripheral.name ?? "unknown")")
        echoRetryCount = 0

        // Update btName from peripheral.name if we didn't have it from discovery
        if btName == nil, let name = peripheral.name {
            btName = name
        }

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
        let err = error
        Task { @MainActor [weak self] in
            self?.delegate?.didDisconnect(error: err)
        }

        // Only auto-reconnect if disconnect was unexpected
        if !intentionalDisconnect {
            watchForReconnection()
        } else {
            connectionState = .disconnected
        }
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
                checkReadyForAuth()
            case BLEConstants.notifyCharUUID:
                notifyCharacteristic = characteristic
                logger.info("Found notify characteristic (0004)")
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

        Task {
            do {
                if let parsed = try await transport.processInbound(chunk: data) {
                    if connectionState == .authenticating {
                        handleAuthResponse(parsed)
                    } else if connectionState == .connected {
                        Task { @MainActor [weak self] in
                            self?.delegate?.didReceiveTelemetry(parsed)
                        }
                    }
                }
            } catch {
                logger.error("Frame processing error: \(error)")
            }
        }
    }
}
#endif
