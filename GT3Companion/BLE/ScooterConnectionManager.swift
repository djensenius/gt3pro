//
//  ScooterConnectionManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//
// swiftlint:disable file_length

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

/// Returns a compact timestamp string: HH:MM:SS.mmm
func bleTS() -> String {
    let now = Date()
    let cal = Calendar.current
    let hour = cal.component(.hour, from: now)
    let min = cal.component(.minute, from: now)
    let sec = cal.component(.second, from: now)
    let msec = Int(now.timeIntervalSince1970 * 1000) % 1000
    return String(format: "%02d:%02d:%02d.%03d", hour, min, sec, msec)
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
    /// 006E-0003: second write in Ninebot service (purpose unknown — tested as auth channel)
    var rctpWriteCharacteristic: CBCharacteristic?
    /// Secondary write channel — tested as auth write (0005)
    var authWriteCharacteristic: CBCharacteristic?
    /// Secondary notify channel — tested as auth response (0006)
    var authNotifyCharacteristic: CBCharacteristic?
    /// Old Nordic UART service write (B5A3-0002) — the Segway app uses this for auth
    var oldWriteCharacteristic: CBCharacteristic?
    /// Old Nordic UART service notify (B5A3-0003) — the Segway app listens here for auth response
    var oldNotifyCharacteristic: CBCharacteristic?

    /// Cycles 0→3 across reconnects (never reset) to rotate write channel for diagnostics.
    /// 0=006E-0005, 1=006E-0002, 2=006E-0003, 3=B5A3-0002
    var authAttemptCount = 0
    /// The write characteristic chosen for this connection's auth attempt.
    private var currentAuthWriteChar: CBCharacteristic?

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
    let bleQueue = DispatchQueue(label: "org.davidjensenius.GT3Companion.ble", qos: .userInitiated)

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
        // Scan without service filter — the GT3 Pro does not include the Ninebot service UUID
        // in its advertisement packet (it only exposes it post-connection). Filter by name instead.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        let prefixes = BLEConstants.advertisingNamePrefixes.joined(separator: ", ")
        logger.info("Scanning for GT3 Pro (name prefixes: \(prefixes))...")
        bleLog("Scanning for GT3 Pro (name prefixes: \(prefixes))…")
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
        // Discover both the new Ninebot service and the old Nordic UART service (B5A3).
        // The old service is present only on first connect; asking for both is harmless.
        peripheral?.discoverServices([BLEConstants.serviceUUID, BLEConstants.oldServiceUUID])
    }

    // Set to true after CCCD ON is sent; beginAuthentication fires on the ACK
    var pendingBeginAuthOnCCCDOn = false

    /// Try to begin auth when both a write and notify characteristic are discovered.
    /// Requires 006E-0004 specifically — that's the characteristic we toggle for the iOS
    /// stale-notification workaround, and auth fires on its CCCD ON confirmation.
    /// B5A3-0003 and 006E-0006 are subscribed passively and are never toggled.
    func checkReadyForAuth() {
        let hasWrite = oldWriteCharacteristic != nil
            || authWriteCharacteristic != nil
            || writeCharacteristic != nil
        // Must have 006E-0004 (toggle target + auth trigger) AND B5A3-0003 (also toggled).
        // Requiring both ensures toggleNotifications captures non-nil oldNotifyCharacteristic,
        // because B5A3-0003 is discovered after 006E-0004 in most connection orderings.
        guard hasWrite, notifyCharacteristic != nil, oldNotifyCharacteristic != nil else { return }
        // Only start the CCCD toggle if we haven't already for this connection
        guard !pendingBeginAuthOnCCCDOn else { return }
        toggleNotifications()
    }

    /// CCCD toggle workaround for iOS stale notifications on reconnect.
    /// Toggles 006E-0004 (auth trigger) AND B5A3-0003 (legacy — toggling this appeared
    /// to trigger the scooter's auth mode in prior testing, giving an 8s auth timeout
    /// instead of the 20-55s supervision timeout we get without it).
    /// beginAuthentication fires on the 006E-0004 CCCD ON ACK + drain delay.
    private func toggleNotifications() {
        guard let notifyChar = notifyCharacteristic, let peripheral = peripheral else { return }

        // Set the guard synchronously before any async work.
        pendingBeginAuthOnCCCDOn = true

        let oldNotify = oldNotifyCharacteristic  // capture before async dispatch

        bleQueue.async {
            peripheral.setNotifyValue(false, for: notifyChar)
            if let old = oldNotify {
                peripheral.setNotifyValue(false, for: old)
            }
            self.bleQueue.asyncAfter(
                deadline: .now() + .milliseconds(Int(BLEConstants.cccdToggleOffDelayMs))
            ) {
                peripheral.setNotifyValue(true, for: notifyChar)
                if let old = oldNotify {
                    peripheral.setNotifyValue(true, for: old)
                }
            }
        }
    }

    func beginAuthentication() {
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

        // Rotate through all write characteristics on successive reconnects to discover
        // which channel the scooter expects PRE_COMM on.
        // Order: 006E-0005 → 006E-0002 → 006E-0003 → B5A3-0002 → repeat
        let channelCandidates: [(CBCharacteristic?, String)] = [
            (authWriteCharacteristic, "006E-0005"),
            (writeCharacteristic, "006E-0002"),
            (rctpWriteCharacteristic, "006E-0003"),
            (oldWriteCharacteristic, "B5A3-0002")
        ]
        var selectedChannel: CBCharacteristic?
        var selectedChannelName = "none"
        for offset in 0..<channelCandidates.count {
            let (char, chanName) = channelCandidates[(authAttemptCount + offset) % channelCandidates.count]
            if let char {
                selectedChannel = char
                selectedChannelName = chanName
                break
            }
        }
        currentAuthWriteChar = selectedChannel
        authAttemptCount += 1
        bleLog("Auth attempt \(authAttemptCount) — write channel: \(selectedChannelName)")
        print("[GT3] [AUTH] Attempt \(authAttemptCount): PRE_COMM → \(selectedChannelName)")

        // Single shared crypto instance — auth and transport MUST share the same object
        // so that key/counter updates during the handshake are visible to both sides.
        let key = KeyDerivation.deriveKey(key1: Data(authName.utf8), key2: nil)
        let crypto = NinebotCrypto(key: key, counter: 0)

        let authActor = NinebotAuth(btName: authName, crypto: crypto, storedPassword: storedPassword)
        self.auth = authActor
        self.transport = NinebotTransport(crypto: crypto, mtu: mtu)

        Task {
            let frame = await authActor.startAuth()
            let timestamp = bleTS()
            bleLog("Sending PRE_COMM plain (\(frame.count) bytes)")
            print("[GT3] \(timestamp) [AUTH] Sending PRE_COMM plain")
            sendFramePlain(frame)
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

    /// Returns true if `name` looks like a raw Ninebot serial number advertised directly over BLE.
    /// Ninebot serials are 12–16 uppercase alphanumeric characters, starting with a digit.
    /// Example: "03GGG2539C0023"
    static func looksLikeNinebotSerial(_ name: String) -> Bool {
        let chars = name.unicodeScalars
        guard (12...16).contains(chars.count) else { return false }
        guard let first = chars.first, first.value >= 48 && first.value <= 57 else { return false } // starts with digit
        return chars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) ||   // 0-9
            (scalar.value >= 65 && scalar.value <= 90)        // A-Z
        }
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
        // Prefer old Nordic UART service, then new auth char, then new primary
        guard let characteristic = oldWriteCharacteristic ?? authWriteCharacteristic ?? writeCharacteristic,
              let peripheral = peripheral else {
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

    /// Send a plain (unencrypted) frame with trailing 2-byte checksum — used for PRE_COMM.
    /// Uses currentAuthWriteChar (set per-attempt by beginAuthentication for channel rotation),
    /// falling back to any available write char.
    private func sendFramePlain(_ frame: Data) {
        guard let char = currentAuthWriteChar
                ?? authWriteCharacteristic
                ?? oldWriteCharacteristic
                ?? writeCharacteristic,
              let periph = peripheral, frame.count > 3 else { return }
        let chksum = UInt16(truncatingIfNeeded: ~Data(frame[2...]).reduce(UInt32(0)) { $0 + UInt32($1) })
        var outFrame = frame
        outFrame.append(UInt8(chksum & 0xFF))
        outFrame.append(UInt8(chksum >> 8))
        let charDesc = char.uuid.uuidString.suffix(4)
        print("[GT3] \(bleTS()) [TRANSPORT] sendFramePlain on \(charDesc): \(outFrame.hexString)")
        let chunkSize = max(1, mtu - 3)
        var chunks: [Data] = []
        var offset = 0
        while offset < outFrame.count {
            let end = min(offset + chunkSize, outFrame.count)
            chunks.append(Data(outFrame[offset..<end]))
            offset = end
        }
        bleQueue.async {
            for (idx, chunk) in chunks.enumerated() {
                periph.writeValue(chunk, for: char, type: .withResponse)
                if idx < chunks.count - 1 {
                    Thread.sleep(forTimeInterval: Double(BLEConstants.fragmentDelayMs) / 1000.0)
                }
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
            bleLog("Skipped device — no name (key derivation requires a name)", level: .warning)
            return
        }

        // Check if the advertisement includes the Ninebot service UUID (some firmware versions)
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let hasNinebotService = advertisedServices.contains(BLEConstants.serviceUUID)

        // Filter: accept if Ninebot service UUID is advertised, name matches known prefixes,
        // or name looks like a raw Ninebot serial (all-caps alphanumeric, 12–16 chars, starts with digit)
        let sanitized = ScooterConnectionManager.sanitizeBLEName(name)
        let hasKnownPrefix = BLEConstants.advertisingNamePrefixes.contains(where: { sanitized.hasPrefix($0) })
        let looksLikeSerial = ScooterConnectionManager.looksLikeNinebotSerial(sanitized)
        guard hasNinebotService || hasKnownPrefix || looksLikeSerial else {
            bleLog("Skipped \"\(name)\" — not a GT3 Pro", level: .debug)
            return
        }
        bleLog("Matched GT3 Pro: \"\(name)\"" +
               " (service=\(hasNinebotService) prefix=\(hasKnownPrefix) serial=\(looksLikeSerial))")
        rawBtName = name
        btName = name
        connectToPeripheral(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        let timestamp = bleTS()
        logger.info("Connected to \(peripheral.name ?? "unknown")")
        bleLog("Connected to \(peripheral.name ?? "unknown") — discovering services…")
        print("[GT3] \(timestamp) [BLE] Connected to \(peripheral.name ?? "unknown")")
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
        let timestamp = bleTS()
        logger.info("Disconnected: \(error?.localizedDescription ?? "clean")")
        bleLog("Disconnected: \(error?.localizedDescription ?? "clean disconnect")",
               level: error != nil ? .warning : .info)
        print("[GT3] \(timestamp) [BLE] Disconnected: \(error?.localizedDescription ?? "clean")")

        // Clear per-connection state so checkReadyForAuth() doesn't fire
        // prematurely on the next connection's characteristic discovery.
        writeCharacteristic = nil
        notifyCharacteristic = nil
        authWriteCharacteristic = nil
        authNotifyCharacteristic = nil
        oldWriteCharacteristic = nil
        oldNotifyCharacteristic = nil
        pendingBeginAuthOnCCCDOn = false
        auth = nil
        transport = nil

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
