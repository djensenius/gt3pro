//
//  AppCoordinator.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import os

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

    private let connectionManager = ScooterConnectionManager()
    private let registerReader = RegisterReader()
    private let rideTracker = RideTracker()
    private let uploadQueue = UploadQueue()
    private let gpsTracker = GPSTracker()
    private let roughnessTracker = SurfaceRoughnessTracker()
    private let liveActivityManager = GT3LiveActivityManager.shared

    private var storedPassword: Data?
    private var hasStarted = false
    private var pendingEndTask: Task<Void, Never>?

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
        self.storedPassword = storedPassword
        connectionManager.start(storedPassword: storedPassword)
        logger.info("AppCoordinator started — watching for GT3 Pro")
    }

    // MARK: - ScooterConnectionDelegate

    func connectionStateChanged(_ state: ConnectionState) {
        self.connectionState = state
    }

    func didAuthenticate(serialNumber: String) {
        logger.info("Authenticated: \(serialNumber)")
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
        await liveActivityManager.startRideActivity()

        logger.info("Fully connected — polling, GPS, roughness, Live Activity active")
    }

    private func onDisconnected() async {
        await registerReader.stopPolling()
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()

        let lastBattery = currentBattery
        await rideTracker.forceEndRide(endBattery: lastBattery)

        pendingEndTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await liveActivityManager.endRideActivity()
        }

        logger.info("Disconnected — trackers stopped, ride finalized")
    }

    // MARK: - Telemetry Processing

    private func handleTelemetryFrame(_ frame: NinebotFrameBuilder.ParsedFrame) async {
        guard let result = await registerReader.processResponse(frame) else { return }

        switch result.name {
        case "rSpeed":
            currentSpeed = result.doubleValue ?? 0
        case "rBattery":
            currentBattery = result.intValue ?? 0
        case "rSingleMileage":
            tripDistance = result.doubleValue ?? 0
        case "rLeftMileage":
            estimatedRange = result.doubleValue ?? 0
        default:
            break
        }

        // Only emit a full sample when speed arrives (one per polling cycle)
        guard result.name == "rSpeed" else { return }

        let gpsSample = gpsTracker.latestSample
        let roughness = roughnessTracker.latestSample

        let sample = TelemetrySample(
            timestamp: Date(),
            speed: currentSpeed,
            battery: currentBattery,
            bms1Voltage: await registerReader.getTelemetryDouble("rBMSVolt") ?? 0,
            bms1Current: await registerReader.getTelemetryDouble("rBMSCur") ?? 0,
            bms1SOC: await registerReader.getTelemetryInt("rBmsSOC") ?? 0,
            bms1Temp: await registerReader.getTelemetryDouble("rBmsTmp") ?? 0,
            bms2Voltage: await registerReader.getTelemetryDouble("rBMSVolt2") ?? 0,
            bms2Current: await registerReader.getTelemetryDouble("rBMSCur2") ?? 0,
            bms2SOC: await registerReader.getTelemetryInt("rBmsSOC2") ?? 0,
            bms2Temp: await registerReader.getTelemetryDouble("rBmsTmp2") ?? 0,
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
            heartRate: nil
        )

        await rideTracker.addSample(sample)
        isRiding = await rideTracker.state != .idle
        await uploadQueue.enqueueSamples([sample])

        await liveActivityManager.updateActivity(state: .init(
            speed: currentSpeed,
            battery: currentBattery,
            tripDistance: tripDistance,
            estimatedRange: estimatedRange,
            gearMode: sample.gearMode,
            bms1Temp: sample.bms1Temp,
            bms2Temp: sample.bms2Temp,
            isCharging: false
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
