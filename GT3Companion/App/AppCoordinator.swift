//
//  AppCoordinator.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import ActivityKit
import CoreLocation
import Foundation
import os
import SwiftData
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Coordinator")

/// Central orchestrator wiring BLE → Register Reader → Ride Tracker → Upload → Live Activity.
@MainActor
class AppCoordinator: ObservableObject, ScooterConnectionDelegate {
    static let shared = AppCoordinator()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var isRiding = false
    @Published var currentSpeed: Double = 0
    @Published var currentBattery: Int = 0
    @Published var tripDistance: Double = 0
    @Published var estimatedRange: Double = 0
    @Published var gearMode: Int = 0
    @Published var bmsTemp: Double = 0
    @Published var bodyTemp: Double = 0
    @Published var serialNumber: String?
    @Published var odometer: Double = 0
    @Published var totalRideTime: Int = 0
    @Published var controllerFirmware: String = "—"
    @Published var mcuFirmware: String = "—"
    @Published var bms1Firmware: String = "—"
    @Published var bleFirmware: String = "—"
    @Published var chargeStatus: Int = 0
    @Published var timeToFull: Int = 0
    @Published var partNumber: String = "—"
    @Published var totalRuntime: Int = 0
    @Published var bmsVoltage: Double = 0
    @Published var bmsCurrent: Double = 0
    @Published var chargeCycles: Int = 0
    @Published var bmsRemainingCapacity: Int = 0
    @Published var bmsManufactureDate: Int = 0
    @Published var isScooterAwake: Bool = false

    private let connectionManager = ScooterConnectionManager()
    let registerReader = RegisterReader()
    let rideTracker = RideTracker()
    let uploadQueue = UploadQueue()
    private let apiClient = GT3APIClient()
    let gpsTracker = GPSTracker()
    let roughnessTracker = SurfaceRoughnessTracker()
    let liveActivityManager = GT3LiveActivityManager.shared
    let watchSession = PhoneWatchSessionManager.shared
    private let debugLog = DebugLogStore.shared

    /// GPS-accumulated trip distance (km), updated each sample via haversine.
    var gpsAccumulatedDistance: Double = 0
    var lastGPSCoord: (lat: Double, lon: Double)?
    /// Raw scooter register distance, kept separate so GPS can override tripDistance.
    var scooterTripDistance: Double = 0

    private var storedPassword: Data?
    private var hasStarted = false
    private var telemetryWatchdog: Task<Void, Never>?
    private var lastTelemetryTime: Date?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    /// How long to wait without telemetry before assuming VCU standby.
    private let telemetryTimeout: TimeInterval = 10

    private init() {
        connectionManager.delegate = self
        watchSession.onHealthDataReceived = { [weak self] heartRateSamples, activeCalories in
            guard let self else { return }
            Task {
                await self.rideTracker.applyHeartRateSamples(heartRateSamples)
                await self.rideTracker.setActiveCalories(activeCalories)
                await MainActor.run {
                    self.backfillPersistedHealthData(
                        heartRateSamples: heartRateSamples,
                        activeCalories: activeCalories
                    )
                }
            }
        }
        Task {
            await rideTracker.setOnComplete { [weak self] rideLog in
                guard let self else { return }
                Task { await self.handleRideComplete(rideLog) }
            }
        }
    }

    /// Start the coordinator — called once on app launch.
    func start(storedPassword: Data? = nil) {
        guard !hasStarted else { return }
        hasStarted = true
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            loadScreenshotData()
            return
        }
        self.storedPassword = storedPassword
        connectionManager.start(storedPassword: storedPassword)
        liveActivityManager.observePushToStartToken(apiClient: apiClient)
        liveActivityManager.reregisterTokenIfNeeded(apiClient: apiClient)
        Task {
            await liveActivityManager.endRideActivity()
            await retryPendingUploads()
        }
        logger.info("AppCoordinator started — watching for GT3 Pro")
    }

    /// Restart BLE scanning.
    func retryScan() { connectionManager.scan() }

    /// Called when the app returns to foreground — restarts Live Activity if needed.
    func resumeFromBackground() {
        let isConnected = connectionState == .connected || connectionState == .authenticating
        guard isConnected, !liveActivityManager.isActive else { return }
        logger.info("App foregrounded while connected — restarting Live Activity")
        Task { await liveActivityManager.startRideActivity() }
    }

    private func requestServerPushToStart() {
        debugLog.log("Calling POST /gt3/activity/start", category: "BLE")
        Task {
            do {
                let success = try await apiClient.requestActivityStart()
                if success {
                    debugLog.log("Push-to-start request succeeded", category: "BLE")
                } else {
                    debugLog.log(
                        "Push-to-start: server reported all tokens failed — clearing cached token",
                        category: "BLE", level: .warning
                    )
                    liveActivityManager.clearCachedToken()
                }
            } catch {
                debugLog.log("Push-to-start failed: \(error)", category: "BLE", level: .error)
            }
        }
    }

    // MARK: - ScooterConnectionDelegate

    func connectionStateChanged(_ state: ConnectionState) {
        let prev = self.connectionState
        self.connectionState = state
        let msg = "BLE state: \(String(describing: prev)) → \(String(describing: state))"
        logger.info("\(msg)")
        debugLog.log(msg, category: "BLE")
        if state == .authenticating {
            debugLog.log("Authenticating — starting Live Activity early", category: "BLE")
            Task { await liveActivityManager.startRideActivity() }
        }
    }

    func didAuthenticate(serialNumber: String) {
        let msg = "Authenticated — SN: \(serialNumber)"
        logger.info("\(msg)")
        debugLog.log(msg, category: "BLE")
        self.serialNumber = serialNumber
        Task { await self.onConnected() }
    }

    func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame) {
        Task { await self.handleTelemetryFrame(frame) }
    }

    func didDisconnect(error: Error?) {
        let msg = "Disconnected — error: \(error?.localizedDescription ?? "none")"
        logger.info("\(msg)")
        debugLog.log(msg, category: "BLE")
        Task { await self.onDisconnected() }
    }

    // MARK: - Connection Lifecycle

    private func onConnected() async {
        debugLog.log("onConnected() — starting setup", category: "BLE")

        // Request background execution time so GPS and telemetry can start
        // even if the Live Activity fails to launch from background.
        beginBackgroundTask()

        await registerReader.configure { [weak self] frame in
            self?.connectionManager.sendFrame(frame)
        }
        await registerReader.readCumulativeRegisters()

        gpsTracker.requestPermissions()
        gpsTracker.startTracking()
        roughnessTracker.startTracking()

        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existing = Activity<GT3RideAttributes>.activities.count
        let active = Activity<GT3RideAttributes>.activities
            .filter { $0.activityState == .active }.count
        let laStatus = "LA: enabled=\(enabled) existing=\(existing) active=\(active)"
        debugLog.log(laStatus, category: "BLE")

        if liveActivityManager.isActive {
            debugLog.log("Live Activity already active", category: "BLE")
        } else {
            debugLog.log("No Live Activity — trying foreground start", category: "BLE")
            await liveActivityManager.startRideActivity()
            if liveActivityManager.isActive {
                debugLog.log("Live Activity started", category: "BLE")
            } else {
                debugLog.log("Foreground start failed — requesting push-to-start", category: "BLE")
                requestServerPushToStart()
            }
        }

        await registerReader.startPolling()
        watchSession.updateContext(battery: 0, isConnected: true)
        await retryPendingUploads()

        // Upload snapshot after cumulative data has arrived (not immediately)
        Task { [weak self] in
            guard let self else { return }
            await self.registerReader.awaitCumulativeData()
            let battery = self.currentBattery > 0 ? self.currentBattery : nil
            let range = self.estimatedRange > 0 ? self.estimatedRange : nil
            let snapshot = await self.registerReader.getDiagnosticSnapshot(
                batteryLevel: battery, estimatedRange: range)
            guard let serial = snapshot["serialNumber"], !serial.isEmpty else {
                debugLog.log("Snapshot missing serialNumber — skipping upload", category: "BLE")
                return
            }
            debugLog.log("Uploading initial snapshot (\(snapshot.count) fields)", category: "BLE")
            await self.uploadQueue.uploadSnapshot(snapshot)
        }

        logger.info("Fully connected — polling, GPS, roughness, Live Activity active")

        // Setup complete — end the background task. If the Live Activity is running
        // it keeps the app alive; otherwise significant-location will wake us.
        endBackgroundTask()
    }

    private func onDisconnected() async {
        debugLog.log("onDisconnected() — finalizing ride", category: "BLE")
        await registerReader.stopPolling()
        stopTelemetryWatchdog()
        let lastBattery = currentBattery
        resetDashboardValues()
        isScooterAwake = false
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()
        watchSession.updateContext(battery: 0, isConnected: false, rideActive: false)
        await rideTracker.forceEndRide(endBattery: lastBattery)
        await uploadQueue.flushSamples()
        await uploadQueue.persistRemainingsamples()

        let preEndCount = Activity<GT3RideAttributes>.activities.count
        await liveActivityManager.endRideActivity()
        let postEndCount = Activity<GT3RideAttributes>.activities.count
        debugLog.log("Ended Live Activities (before=\(preEndCount) after=\(postEndCount))", category: "BLE")
    }

    // MARK: - Background Task

    /// Request background execution time to keep GPS and telemetry alive
    /// when the Live Activity fails to start from background.
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "GT3-BLE-Setup") { [weak self] in
            self?.debugLog.log("Background task expiring", category: "BLE", level: .warning)
            self?.endBackgroundTask()
        }
        debugLog.log("Background task started (id=\(backgroundTaskID.rawValue))", category: "BLE")
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        debugLog.log("Background task ended", category: "BLE")
        backgroundTaskID = .invalid
    }

    // MARK: - Power Control

    /// Reset all dashboard telemetry values to zero.
    private func resetDashboardValues() {
        currentSpeed = 0
        currentBattery = 0
        tripDistance = 0
        estimatedRange = 0
        gearMode = 0
        bmsTemp = 0
        bodyTemp = 0
        bmsVoltage = 0
        bmsCurrent = 0
        gpsAccumulatedDistance = 0
        lastGPSCoord = nil
        scooterTripDistance = 0
    }
    /// Send the power-on command to the VCU.
    func sendPowerOn() {
        let frame = NinebotFrameBuilder.buildPowerOnFrame()
        connectionManager.sendFrame(frame)
        logger.info("Sent power-on command to VCU")
    }

    /// Send the power-off command to the scooter.
    func sendPowerOff() {
        let frame = NinebotFrameBuilder.buildPowerOffFrame()
        connectionManager.sendFrame(frame)
        logger.info("Sent power-off command to VCU")
    }

    // MARK: - Telemetry Watchdog

    /// Fires if no telemetry arrives within `telemetryTimeout`.
    private func startTelemetryWatchdog() {
        telemetryWatchdog?.cancel()
        lastTelemetryTime = Date()
        telemetryWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                guard self.isScooterAwake else { break }
                guard let lastTime = self.lastTelemetryTime else { continue }
                if Date().timeIntervalSince(lastTime) > self.telemetryTimeout {
                    logger.info("Telemetry watchdog: no response for \(self.telemetryTimeout)s — assuming standby")
                    let lastBattery = self.currentBattery
                    await self.handleScooterSleep(lastBattery: lastBattery)
                    break
                }
            }
        }
    }

    private func stopTelemetryWatchdog() {
        telemetryWatchdog?.cancel()
        telemetryWatchdog = nil
        lastTelemetryTime = nil
    }

    // MARK: - Telemetry Processing

    private func handleTelemetryFrame(_ frame: NinebotFrameBuilder.ParsedFrame) async {
        guard let result = await registerReader.processResponse(frame) else { return }
        lastTelemetryTime = Date()

        if result.name == "rBool", let rawValue = result.intValue {
            handleRBoolUpdate(rawValue)
        } else if let batteryValue = updatePublishedValue(for: result) {
            handleBatteryUpdate(batteryValue)
        }

        guard result.name == "rSpeed" else { return }
        await emitSample()
    }

    // rBool bit 0 = powered, bit 5 = standby.
    private let rBoolPoweredMask = 0x01
    private let rBoolStandbyMask = 0x20

    private func handleRBoolUpdate(_ rawValue: Int) {
        let isStandby = (rawValue & rBoolStandbyMask) != 0
        let isPowered = (rawValue & rBoolPoweredMask) != 0

        if isPowered && !isStandby && !isScooterAwake {
            logger.info("rBool=0x\(String(rawValue, radix: 16)): scooter powered ON")
            isScooterAwake = true
            gpsTracker.startTracking()
            roughnessTracker.startTracking()
            startTelemetryWatchdog()
        } else if isStandby && !isPowered && isScooterAwake {
            logger.info("rBool=0x\(String(rawValue, radix: 16)): scooter entered STANDBY")
            let lastBattery = currentBattery
            Task { await handleScooterSleep(lastBattery: lastBattery) }
        }
    }

    private func handleBatteryUpdate(_ value: Int) {
        currentBattery = value
    }

    /// Handle the scooter powering off while still BLE-connected.
    private func handleScooterSleep(lastBattery: Int) async {
        logger.info("Scooter entered standby — cleaning up ride state")
        isScooterAwake = false
        stopTelemetryWatchdog()
        resetDashboardValues()
        await registerReader.clearTelemetry()
        await rideTracker.forceEndRide(endBattery: lastBattery)
        await uploadQueue.flushSamples()
        await uploadQueue.persistRemainingsamples()
        isRiding = false
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()
        await liveActivityManager.updateActivity(state: .idle(isConnected: true))
        watchSession.sendTelemetry(WatchTelemetryContext(
            battery: 0,
            isConnected: true,
            rideActive: false,
            speed: 0,
            tripDistance: 0,
            range: 0,
            mode: 0
        ))
        watchSession.updateContext(battery: 0, isConnected: true, rideActive: false)
        sendScooterSleepNotification()
    }

    func sendScooterSleepNotification() {
        sendNotification(title: "Scooter Standby 💤", body: "GT3 Pro powered off. Still connected via Bluetooth.")
    }

    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(title)-\(UUID().uuidString)",
            content: content, trigger: nil
        ))
    }

    // MARK: - Ride Completion (see AppCoordinator+Rides.swift)
}

extension RideTracker {
    func setOnComplete(_ callback: @escaping @Sendable (RideLog) -> Void) {
        self.onRideComplete = callback
    }
}
#endif
