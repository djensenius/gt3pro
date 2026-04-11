//
//  AppCoordinator.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import os
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
    private let registerReader = RegisterReader()
    private let rideTracker = RideTracker()
    private let uploadQueue = UploadQueue()
    private let gpsTracker = GPSTracker()
    private let roughnessTracker = SurfaceRoughnessTracker()
    private let liveActivityManager = GT3LiveActivityManager.shared
    private let watchSession = PhoneWatchSessionManager.shared

    private var storedPassword: Data?
    private var hasStarted = false
    private var pendingEndTask: Task<Void, Never>?
    private var powerOnTask: Task<Void, Never>?

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
        logger.info("AppCoordinator started — watching for GT3 Pro")
    }

    /// Populate mock data for App Store screenshots.
    private func loadScreenshotData() {
        connectionState = .connected
        isScooterAwake = true
        isRiding = true
        currentSpeed = 47
        currentBattery = 82
        tripDistance = 6.3
        estimatedRange = 38
        gearMode = 3
        bmsTemp = 32.5
        bodyTemp = 28.0
        serialNumber = "03GGG2539C0023"
        odometer = 109.4
        totalRideTime = 7200
        controllerFirmware = "2.1.8"
        mcuFirmware = "1.3.4"
        bms1Firmware = "1.0.9"
        bleFirmware = "1.2.1"
        chargeStatus = 0
        partNumber = "AA.50.0026.10"
        bmsVoltage = 58.2
        bmsCurrent = 12.4
        chargeCycles = 15
        bmsRemainingCapacity = 1890
        logger.info("Screenshot mode — loaded mock data")
    }

    /// Restart BLE scanning — used when the user taps "Retry Connection".
    func retryScan() {
        connectionManager.scan()
    }

    // MARK: - ScooterConnectionDelegate

    func connectionStateChanged(_ state: ConnectionState) {
        self.connectionState = state
        if state == .authenticating {
            Task { await liveActivityManager.startRideActivity() }
        }
    }

    func didAuthenticate(serialNumber: String) {
        logger.info("Authenticated: \(serialNumber)")
        self.serialNumber = serialNumber
        Task { await self.onConnected() }
    }

    func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame) {
        Task { await self.handleTelemetryFrame(frame) }
    }

    func didDisconnect(error: Error?) {
        Task { await self.onDisconnected() }
    }

    // MARK: - Connection Lifecycle

    private func onConnected() async {
        pendingEndTask?.cancel()
        pendingEndTask = nil

        await registerReader.configure { [weak self] frame in
            self?.connectionManager.sendFrame(frame)
        }
        await registerReader.readCumulativeRegisters()

        let snapshot = await registerReader.getDiagnosticSnapshot()
        await uploadQueue.uploadSnapshot(snapshot)

        gpsTracker.requestPermissions()
        gpsTracker.startTracking()
        roughnessTracker.startTracking()

        await registerReader.startPolling()
        watchSession.updateContext(battery: 0, isConnected: true)

        sendPowerOn()
        startPowerOnPolling()

        logger.info("Fully connected — polling, GPS, roughness, Live Activity active")
    }

    private func onDisconnected() async {
        await registerReader.stopPolling()
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()
        stopPowerOnPolling()
        isScooterAwake = false
        watchSession.updateContext(battery: 0, isConnected: false)

        let lastBattery = currentBattery
        await rideTracker.forceEndRide(endBattery: lastBattery)

        pendingEndTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await liveActivityManager.endRideActivity()
        }

        logger.info("Disconnected — trackers stopped, ride finalized")
    }

    // MARK: - Power Control

    /// Send the power-on command to the VCU.
    func sendPowerOn() {
        let frame = NinebotFrameBuilder.buildPowerOnFrame()
        connectionManager.sendFrame(frame)
        logger.info("Sent power-on command to VCU")
    }

    /// Send the power-off command to the VCU.
    func sendPowerOff() {
        let frame = NinebotFrameBuilder.buildPowerOffFrame()
        connectionManager.sendFrame(frame)
        logger.info("Sent power-off command to VCU")
    }

    private func startPowerOnPolling() {
        powerOnTask?.cancel()
        powerOnTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                if self.currentBattery == 0 {
                    self.sendPowerOn()
                } else {
                    break
                }
            }
        }
    }

    private func stopPowerOnPolling() {
        powerOnTask?.cancel()
        powerOnTask = nil
    }

    // MARK: - Telemetry Processing

    private func handleTelemetryFrame(_ frame: NinebotFrameBuilder.ParsedFrame) async {
        guard let result = await registerReader.processResponse(frame) else { return }
        updatePublishedValue(for: result)
        guard result.name == "rSpeed" else { return }
        await emitSample()
    }

    private func updatePublishedValue(for result: RegisterReadResult) {
        updateDashboardValues(for: result)
        updateInfoValues(for: result)
    }

    private func updateDashboardValues(for result: RegisterReadResult) {
        switch result.name {
        case "rSpeed":            currentSpeed = result.doubleValue ?? 0
        case "rBattery":          handleBatteryUpdate(result.intValue ?? 0)
        case "rSingleMileage":    tripDistance = result.doubleValue ?? 0
        case "rLeftMileage":      estimatedRange = result.doubleValue ?? 0
        case "rGearMode":         gearMode = result.intValue ?? 0
        case "rBmsTmp2":          bmsTemp = result.doubleValue ?? 0
        case "rBodyTemp":         bodyTemp = result.doubleValue ?? 0
        case "rBMSVolt2":        bmsVoltage = result.doubleValue ?? 0
        case "rBMSCur2":         bmsCurrent = result.doubleValue ?? 0
        default:                  break
        }
    }

    private func updateInfoValues(for result: RegisterReadResult) {
        switch result.name {
        case "rPreciseMileage":    odometer = result.doubleValue ?? 0
        case "rMileage":
            if odometer == 0 { odometer = result.doubleValue ?? 0 }
        case "rRideTime":         totalRideTime = result.intValue ?? 0
        case "rRuntime":          totalRuntime = result.intValue ?? 0
        case "rChargeStatus":     chargeStatus = result.intValue ?? 0
        case "rTimeFull":         timeToFull = result.intValue ?? 0
        case "rPN":               partNumber = result.stringValue ?? "—"
        default:                  updateBatteryInfoValues(for: result)
        }
    }

    private func updateBatteryInfoValues(for result: RegisterReadResult) {
        switch result.name {
        case "rBms2CycleCountLT":       chargeCycles = result.intValue ?? 0
        case "rBms2RemainCapacityLT":   bmsRemainingCapacity = result.intValue ?? 0
        case "rBms2ManufactureDateLT":  bmsManufactureDate = result.intValue ?? 0
        default:                        updateFirmwareValues(for: result)
        }
    }

    private func updateFirmwareValues(for result: RegisterReadResult) {
        switch result.name {
        case "rCtrlV":  controllerFirmware = result.stringValue ?? "—"
        case "rMCUV":   mcuFirmware = result.stringValue ?? "—"
        case "rBmsV":   bms1Firmware = result.stringValue ?? "—"
        case "rBleV":   bleFirmware = result.stringValue ?? "—"
        default:        break
        }
    }

    private func handleBatteryUpdate(_ value: Int) {
        let wasAwake = isScooterAwake
        currentBattery = value

        if value > 0 {
            isScooterAwake = true
            stopPowerOnPolling()

            if !wasAwake {
                logger.info("Scooter woke up — battery \(value)%")
                gpsTracker.startTracking()
                roughnessTracker.startTracking()
            }
        } else if wasAwake {
            Task { await handleScooterSleep() }
        }
    }

    /// Handle the scooter powering off while still BLE-connected.
    private func handleScooterSleep() async {
        logger.info("Scooter entered standby — cleaning up ride state")
        isScooterAwake = false

        // End any active ride
        let lastBattery = currentBattery
        await rideTracker.forceEndRide(endBattery: lastBattery)
        isRiding = false

        // Stop location/motion tracking while asleep
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()

        // Immediately push standby state to Live Activity
        await liveActivityManager.updateActivity(state: .init(
            speed: 0,
            battery: 0,
            tripDistance: 0,
            estimatedRange: 0,
            gearMode: 0,
            bmsTemp: 0,
            isCharging: false,
            isAwake: false
        ))

        // Tell the Watch we're in standby
        watchSession.sendTelemetry(speed: 0, battery: 0, tripDistance: 0, range: 0, mode: 0)

        // Resume power-on polling so we detect wake-up
        startPowerOnPolling()

        sendScooterSleepNotification()
    }

    private func sendScooterSleepNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Scooter Standby 💤"
        content.body = "GT3 Pro powered off. Still connected via Bluetooth."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "scooter-sleep-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
            isAwake: isScooterAwake
        ))
    }

    // MARK: - Notifications

    private func sendRideStartNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ride Started 🛴"
        content.body = "GT3 Pro ride logging is active. Battery: \(currentBattery)%"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ride-start-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        context.insert(persisted)
        try? context.save()

        await uploadQueue.flushSamples()
        if let serverId = await uploadQueue.uploadRide(rideLog) {
            persisted.rideId = serverId
            persisted.uploaded = true
            try? context.save()
        }
    }
}

extension RideTracker {
    func setOnComplete(_ callback: @escaping @Sendable (RideLog) -> Void) {
        self.onRideComplete = callback
    }
}
#endif
