//
//  AppCoordinator.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "Coordinator")

/// Central orchestrator wiring BLE → Register Reader → Ride Tracker → Upload → Live Activity.
/// This is the glue that makes "hop on and ride, everything logs automatically" work.
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

    private init() {
        connectionManager.delegate = self

        Task {
            await rideTracker.setOnComplete { [weak self] rideLog in
                guard let self else { return }
                Task {
                    await self.handleRideComplete(rideLog)
                }
            }
        }
    }

    /// Start the coordinator — called once on app launch.
    func start(storedPassword: Data? = nil) {
        self.storedPassword = storedPassword
        connectionManager.start(storedPassword: storedPassword)
        logger.info("AppCoordinator started — watching for GT3 Pro")
    }

    // MARK: - ScooterConnectionDelegate

    nonisolated func connectionStateChanged(_ state: ConnectionState) {
        Task { @MainActor in
            self.connectionState = state
        }
    }

    nonisolated func didAuthenticate(serialNumber: String) {
        Task { @MainActor in
            logger.info("Authenticated: \(serialNumber)")
            await self.onConnected()
        }
    }

    nonisolated func didReceiveTelemetry(_ frame: NinebotFrameBuilder.ParsedFrame) {
        Task { @MainActor in
            await self.handleTelemetryFrame(frame)
        }
    }

    nonisolated func didDisconnect(error: Error?) {
        Task { @MainActor in
            await self.onDisconnected()
        }
    }

    // MARK: - Connection Lifecycle

    private func onConnected() async {
        // Read cumulative registers (snapshot)
        await registerReader.configure { [weak self] frame in
            self?.connectionManager.sendFrame(frame)
        }
        await registerReader.readCumulativeRegisters()

        // Upload snapshot
        let snapshot = await registerReader.getDiagnosticSnapshot()
        await uploadQueue.uploadSnapshot(snapshot)

        // Start GPS + roughness tracking
        gpsTracker.startTracking()
        roughnessTracker.startTracking()

        // Start telemetry polling
        await registerReader.startPolling()

        // Start Live Activity
        await liveActivityManager.startRideActivity()

        logger.info("Fully connected — polling, GPS, roughness, Live Activity active")
    }

    private func onDisconnected() async {
        // Stop polling
        await registerReader.stopPolling()

        // Stop trackers
        gpsTracker.stopTracking()
        roughnessTracker.stopTracking()

        // Force-end ride if one is active
        let lastBattery = currentBattery
        await rideTracker.forceEndRide(endBattery: lastBattery)

        // End Live Activity with delay
        Task {
            try? await Task.sleep(for: .seconds(30))
            await liveActivityManager.endRideActivity()
        }

        logger.info("Disconnected — trackers stopped, ride finalized")
    }

    // MARK: - Telemetry Processing

    private func handleTelemetryFrame(_ frame: NinebotFrameBuilder.ParsedFrame) async {
        guard let result = await registerReader.processResponse(frame) else { return }

        // Update published state from known registers
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

        // Build telemetry sample with GPS + roughness
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

        // Feed to ride tracker (handles start/stop detection)
        await rideTracker.addSample(sample)
        isRiding = await rideTracker.state != .idle

        // Batch upload telemetry
        await uploadQueue.enqueueSamples([sample])

        // Update Live Activity
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

        // Flush remaining telemetry
        await uploadQueue.flushSamples()

        // Upload ride summary
        await uploadQueue.uploadRide(rideLog)
    }
}

// MARK: - RideTracker callback helper

extension RideTracker {
    func setOnComplete(_ callback: @escaping @Sendable (RideLog) -> Void) {
        self.onRideComplete = callback
    }
}
#endif
