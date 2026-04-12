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
import UserNotifications

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Coordinator")
private let debugLog = DebugLogStore.shared

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
    private let registerReader = RegisterReader()
    private let rideTracker = RideTracker()
    private let uploadQueue = UploadQueue()
    private let apiClient = GT3APIClient()
    private let gpsTracker = GPSTracker()
    private let roughnessTracker = SurfaceRoughnessTracker()
    private let liveActivityManager = GT3LiveActivityManager.shared
    private let watchSession = PhoneWatchSessionManager.shared

    private var storedPassword: Data?
    private var hasStarted = false
    private var telemetryWatchdog: Task<Void, Never>?
    private var lastTelemetryTime: Date?

    /// How long to wait without telemetry before assuming VCU standby.
    private let telemetryTimeout: TimeInterval = 10

    private init() {
        connectionManager.delegate = self
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

    /// Ask server to send APNs push-to-start (background reconnect fallback).
    private func requestServerPushToStart() {
        debugLog.log("Calling POST /gt3/activity/start", category: "Reconnect")
        Task {
            do {
                try await apiClient.requestActivityStart()
                debugLog.log("Server push-to-start POST succeeded", category: "Reconnect")
            } catch {
                debugLog.log("Server push-to-start POST failed: \(error)", category: "Reconnect", level: .error)
            }
        }
    }

    // MARK: - ScooterConnectionDelegate

    func connectionStateChanged(_ state: ConnectionState) {
        let prev = self.connectionState
        self.connectionState = state
        let msg = "Connection state: \(String(describing: prev)) → \(String(describing: state))"
        logger.info("[RECONNECT] \(msg)")
        debugLog.log(msg, category: "Reconnect")
        if state == .authenticating {
            debugLog.log("State is authenticating — starting Live Activity early", category: "Reconnect")
            Task { await liveActivityManager.startRideActivity() }
        }
    }

    func didAuthenticate(serialNumber: String) {
        let msg = "didAuthenticate fired — SN: \(serialNumber)"
        logger.info("[RECONNECT] \(msg)")
        debugLog.log(msg, category: "Reconnect")
        self.serialNumber = serialNumber
        Task { await self.onConnected() }
    }

    func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame) {
        Task { await self.handleTelemetryFrame(frame) }
    }

    func didDisconnect(error: Error?) {
        let msg = "didDisconnect — error: \(error?.localizedDescription ?? "none")"
        logger.info("[RECONNECT] \(msg)")
        debugLog.log(msg, category: "Reconnect")
        Task { await self.onDisconnected() }
    }

    // MARK: - Connection Lifecycle

    private func onConnected() async {
        debugLog.log("onConnected() — starting connection setup", category: "Reconnect")
        await registerReader.configure { [weak self] frame in
            self?.connectionManager.sendFrame(frame)
        }
        await registerReader.readCumulativeRegisters()

        let snapshot = await registerReader.getDiagnosticSnapshot()
        await uploadQueue.uploadSnapshot(snapshot)

        gpsTracker.requestPermissions()
        gpsTracker.startTracking()
        roughnessTracker.startTracking()

        let activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existingCount = Activity<GT3RideAttributes>.activities.count
        let activeCount = Activity<GT3RideAttributes>.activities.filter { $0.activityState == .active }.count
        let laStatus = "LA check: enabled=\(activitiesEnabled) existing=\(existingCount) active=\(activeCount) isActive=\(liveActivityManager.isActive)"
        logger.info("[RECONNECT] \(laStatus)")
        debugLog.log(laStatus, category: "Reconnect")

        if liveActivityManager.isActive {
            debugLog.log("Live Activity already active — keeping it", category: "Reconnect")
        } else {
            debugLog.log("No active Live Activity — trying foreground start", category: "Reconnect")
            await liveActivityManager.startRideActivity()
            if liveActivityManager.isActive {
                debugLog.log("Foreground Live Activity started successfully", category: "Reconnect")
            } else {
                debugLog.log("Foreground start failed — requesting server push-to-start", category: "Reconnect")
                requestServerPushToStart()
            }
        }

        await registerReader.startPolling()
        watchSession.updateContext(battery: 0, isConnected: true)
        await retryPendingUploads()

        logger.info("Fully connected — polling, GPS, roughness, Live Activity active")
    }

    private func onDisconnected() async {
        debugLog.log("onDisconnected() — finalizing ride", category: "Reconnect")
        await registerReader.stopPolling()
        stopTelemetryWatchdog()
        let lastBattery = currentBattery
        resetDashboardValues()
        isScooterAwake = false
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()
        watchSession.updateContext(battery: 0, isConnected: false)
        await rideTracker.forceEndRide(endBattery: lastBattery)
        await uploadQueue.flushSamples()
        await uploadQueue.persistRemainingsamples()

        let preEndCount = Activity<GT3RideAttributes>.activities.count
        await liveActivityManager.endRideActivity()
        let postEndCount = Activity<GT3RideAttributes>.activities.count
        debugLog.log("Ended Live Activities (before=\(preEndCount) after=\(postEndCount))", category: "Reconnect")
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

    /// Detect power state from VCU register 0x1C (rBool).
    private func handleRBoolUpdate(_ rawValue: Int) {
        let isStandby = (rawValue & 0x20) != 0
        let isPowered = (rawValue & 0x01) != 0

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
        watchSession.sendTelemetry(speed: 0, battery: 0, tripDistance: 0, range: 0, mode: 0)
        sendScooterSleepNotification()
    }

    private func sendScooterSleepNotification() {
        sendNotification(title: "Scooter Standby 💤", body: "GT3 Pro powered off. Still connected via Bluetooth.")
    }

    private func emitSample() async {
        let gpsSample = gpsTracker.latestSample
        let roughness = roughnessTracker.latestSample
        let sample = TelemetrySample(
            timestamp: Date(),
            speed: currentSpeed,
            battery: currentBattery,
            bmsVoltage: await registerReader.getTelemetryDouble("rBMSVolt2") ?? 0,
            bmsCurrent: await registerReader.getTelemetryDouble("rBMSCur2") ?? 0,
            bmsSOC: await registerReader.getTelemetryInt("rBmsSOC2") ?? 0,
            bmsTemp: await registerReader.getTelemetryDouble("rBmsTmp2") ?? 0,
            tripDistance: tripDistance,
            tripTime: await registerReader.getTelemetryInt("rSingleRideTime") ?? 0,
            bodyTemp: await registerReader.getTelemetryDouble("rBodyTemp") ?? 0,
            gearMode: await registerReader.getTelemetryInt("rGearMode") ?? 0,
            estimatedRange: estimatedRange,
            errorCode: await registerReader.getTelemetryInt("rErrorCode") ?? 0,
            warnCode: await registerReader.getTelemetryInt("rWarnCode") ?? 0,
            regenLevel: await registerReader.getTelemetryInt("rGearED") ?? 0,
            speedResponse: await registerReader.getTelemetryInt("rGearSR") ?? 0,
            latitude: gpsSample?.latitude,
            longitude: gpsSample?.longitude,
            altitude: gpsSample?.altitude,
            gpsSpeed: gpsSample?.speed,
            gpsCourse: gpsSample?.course,
            horizontalAccuracy: gpsSample?.horizontalAccuracy,
            roughnessScore: roughness?.roughnessScore,
            maxAcceleration: roughness?.maxAcceleration,
            heartRate: watchSession.latestHeartRate > 0 ? watchSession.latestHeartRate : nil
        )

        let wasIdle = await rideTracker.state == .idle
        await rideTracker.addSample(sample)
        let nowRiding = await rideTracker.state == .riding

        // Detect ride start transition and notify user
        if wasIdle && nowRiding {
            isRiding = true
            sendRideStartNotification()
            logger.info("Ride auto-started — notifying user")

            // Fetch weather at ride start
            if let gpsSample {
                let location = CLLocation(
                    latitude: gpsSample.latitude,
                    longitude: gpsSample.longitude
                )
                let rideId = await self.rideTracker.getCurrentRideId()
                Task {
                    let weather = await WeatherService.shared.fetchWeather(at: location)
                    guard await self.rideTracker.getCurrentRideId() == rideId else { return }
                    await self.rideTracker.setWeather(weather)
                }
            }
        }
        isRiding = await rideTracker.state != .idle

        await uploadQueue.enqueueSamples([sample])

        // Send telemetry to Watch
        watchSession.sendTelemetry(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: tripDistance,
            range: estimatedRange,
            mode: sample.gearMode
        )

        await liveActivityManager.updateActivity(state: .init(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: tripDistance,
            estimatedRange: estimatedRange,
            gearMode: sample.gearMode,
            bmsTemp: sample.bmsTemp,
            isCharging: false,
            isAwake: isScooterAwake,
            isConnected: true
        ))
    }

    // MARK: - Notifications

    private func sendRideStartNotification() {
        sendNotification(title: "Ride Started 🛴", body: "GT3 Pro ride logging is active. Battery: \(currentBattery)%")
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "\(title)-\(UUID().uuidString)",
            content: content, trigger: nil
        ))
    }

    // MARK: - Ride Completion

    private func handleRideComplete(_ rideLog: RideLog) async {
        logger.info("Ride complete: \(rideLog.totalDistance) km")
        let context = PersistenceController.shared.context
        let persisted = PersistedRide(
            rideId: rideLog.rideId,
            startTime: rideLog.startTime,
            startBattery: rideLog.startBattery
        )
        persisted.endTime = rideLog.endTime
        persisted.totalDistance = rideLog.totalDistance
        persisted.maxSpeed = rideLog.maxSpeed
        persisted.avgSpeed = rideLog.avgSpeed
        persisted.batteryUsed = rideLog.batteryUsed
        persisted.endBattery = rideLog.endBattery
        persisted.primaryGearMode = rideLog.primaryGearMode

        if let weather = rideLog.weather {
            persisted.weatherTemp = weather.temp
            persisted.weatherFeelsLike = weather.feelsLike
            persisted.weatherHumidity = weather.humidity
            persisted.weatherWindSpeed = weather.windSpeed
            persisted.weatherWindDirection = weather.windDirection
            persisted.weatherCondition = weather.condition
            persisted.weatherConditionSymbol = weather.conditionSymbol
            persisted.weatherUVIndex = weather.uvIndex
            persisted.weatherPressure = weather.pressure
        }

        context.insert(persisted)
        try? context.save()
        await uploadQueue.flushSamples()
        if let serverId = await uploadQueue.uploadRide(rideLog) {
            persisted.rideId = serverId
            persisted.uploaded = true
            try? context.save()
        } else {
            // Persist for retry — encode the full RideLog as JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let payload = try? encoder.encode(rideLog) {
                let queueItem = UploadQueueItem(payload: payload, endpoint: "/gt3/ride")
                context.insert(queueItem)
                try? context.save()
                logger.info("Queued ride \(rideLog.rideId) for retry")
            }
        }
    }

    /// Retry uploading any rides/telemetry that failed previously.
    private func retryPendingUploads() async {
        let context = PersistenceController.shared.context
        guard let items = try? context.fetch(FetchDescriptor<UploadQueueItem>()),
              !items.isEmpty else { return }
        logger.info("Found \(items.count) pending upload(s) to retry")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for item in items {
            do {
                let data = try await uploadQueue.retryUpload(
                    payload: item.payload, endpoint: item.endpoint
                )
                if item.endpoint == "/gt3/ride",
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serverId = json["id"] as? String,
                   let ride = try? decoder.decode(RideLog.self, from: item.payload) {
                    let pred = #Predicate<PersistedRide> { $0.rideId == ride.rideId }
                    if let match = try? context.fetch(FetchDescriptor(predicate: pred)).first {
                        match.rideId = serverId
                        match.uploaded = true
                    }
                }
                context.delete(item)
                try? context.save()
                logger.info("Retry succeeded: \(item.endpoint)")
            } catch {
                item.retryCount += 1
                item.lastAttempt = Date()
                try? context.save()
                logger.warning("Retry \(item.endpoint) failed (#\(item.retryCount)): \(error)")
            }
        }
    }
}

extension RideTracker {
    func setOnComplete(_ callback: @escaping @Sendable (RideLog) -> Void) {
        self.onRideComplete = callback
    }
}
#endif
