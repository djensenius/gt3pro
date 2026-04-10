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

func bleLog(_ message: String, level: LogEntry.Level = .info) {
    Task { @MainActor in
        DebugLogStore.shared.log(message, category: "BLE", level: level)
    }
}

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
    var writeCharacteristic: CBCharacteristic?
    var notifyCharacteristic: CBCharacteristic?

    var transport: NinebotTransport?
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
            bleLog("Cannot scan — Bluetooth not ready", level: .warning)
            return
        }

        // Try previously-seen peripheral UUID first (fastest path), but only
        // short-circuit when CoreBluetooth already reports it as connected.
        if let savedUUID = ScooterConnectionManager.loadPeripheralUUID() {
            let known = central.retrievePeripherals(withIdentifiers: [savedUUID])
            if let existing = known.first, existing.state == .connected {
                btName = existing.name
                logger.info("Reconnecting to saved connected peripheral: \(self.btName ?? "unknown")")
                bleLog("Reconnecting to saved peripheral: \(existing.name ?? savedUUID.uuidString)")
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
            bleLog("Found already-connected peripheral: \(existing.name ?? "(no name)")")
            connectToPeripheral(existing)
            return
        }

        connectionState = .scanning
        central.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("Scanning for GT3 Pro...")
        bleLog("Scanning for GT3 Pro (service \(BLEConstants.serviceUUID.uuidString))…")
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
    func checkReadyForAuth() {
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
            bleLog("Auth failed — no BT name available", level: .error)
            return
        }

        connectionState = .authenticating

        // Strip leading emoji/whitespace — iOS may decorate the name (e.g. "🛴 Segway Scooter0023")
        // but the scooter firmware uses the plain name for key derivation
        let authName = ScooterConnectionManager.sanitizeBLEName(name)
        logger.info("Raw BT name: \(name) → auth name: \(authName) (bytes: \(Data(authName.utf8).count))")
        bleLog("Auth start — raw name: \"\(name)\" → sanitized: \"\(authName)\" (\(Data(authName.utf8).count) bytes)")
        bleLog("Stored password in keychain: \(storedPassword != nil ? "YES (\(storedPassword!.count) bytes)" : "NO")")

        // Single shared crypto instance — auth and transport MUST share the same object
        // so that key/counter updates during the handshake are visible to both sides.
        let key = KeyDerivation.deriveKey(key1: Data(authName.utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)

        let authActor = NinebotAuth(btName: authName, crypto: crypto, storedPassword: storedPassword)
        self.auth = authActor
        self.transport = NinebotTransport(crypto: crypto, mtu: mtu)

        Task {
            let frame = await authActor.startAuth()
            bleLog("Sending PRE_COMM (\(frame.count) bytes)")
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

    static func btStateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn:     return "powered on"
        case .poweredOff:    return "powered off"
        case .unauthorized:  return "unauthorized"
        case .unsupported:   return "unsupported"
        case .resetting:     return "resetting"
        default:             return "unknown"
        }
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

    func handleAuthResponse(_ parsed: NinebotFrameBuilder.ParsedFrame) {
        guard let auth = self.auth else { return }

        Task {
            let nextFrame = await auth.processResponse(parsed)
            let state = await auth.state

            switch state {
            case .authenticated:
                let serial = await auth.getSerialNumber() ?? "unknown"
                logger.info("Authenticated with GT3 Pro (SN: \(serial))")
                bleLog("✅ Authenticated! Serial: \(serial)")
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
                bleLog("🔴 Auth failed: \(reason)", level: .error)
                connectionState = .disconnected
                disconnect()

            default:
                await advanceAuthState(state: state, nextFrame: nextFrame)
            }
        }
    }

    private func advanceAuthState(state: AuthState, nextFrame: Data?) async {
        if case .setPwd = state {
            bleLog("Auth state → SET_PWD (waiting for button press on dashboard)")
        } else if case .auth = state {
            bleLog("Auth state → AUTH (sending credentials)")
        }
        if let frame = nextFrame {
            if case .setPwd = state {
                try? await Task.sleep(for: .seconds(2))
            }
            sendFrame(frame)
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
        bleLog("Bluetooth state: \(central.state.rawValue) (\(Self.btStateDescription(central.state)))")
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
        bleLog("Discovered peripheral: \"\(name ?? "(no name)")\" RSSI: \(RSSI)")

        guard let name, !name.isEmpty else {
            logger.warning("Skipping device with no name — key derivation requires a valid BT name")
            bleLog("Skipped device — no name (key derivation requires a name)", level: .warning)
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
        bleLog("Connected to \(peripheral.name ?? "unknown") — discovering services…")
        echoRetryCount = 0

        // Update btName from peripheral.name if we didn't have it from discovery
        if btName == nil, let name = peripheral.name {
            btName = name
        }

        let negotiatedMTU = peripheral.maximumWriteValueLength(for: .withResponse) + 3
        if negotiatedMTU > BLEConstants.defaultMTU {
            mtu = negotiatedMTU
            logger.info("Negotiated MTU: \(self.mtu)")
            bleLog("Negotiated MTU: \(self.mtu)")
        }

        discoverServices()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        bleLog("Failed to connect: \(error?.localizedDescription ?? "unknown error")", level: .error)
        connectionState = .disconnected
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.info("Disconnected: \(error?.localizedDescription ?? "clean")")
        bleLog("Disconnected: \(error?.localizedDescription ?? "clean disconnect")",
               level: error != nil ? .warning : .info)
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
#endif
