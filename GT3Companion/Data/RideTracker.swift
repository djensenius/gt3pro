//
//  RideTracker.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "RideTracker")

/// A complete telemetry sample with GPS and roughness data.
struct TelemetrySample: Codable, Sendable {
    let timestamp: Date
    let speed: Double
    let battery: Int
    let bmsVoltage: Double
    let bmsCurrent: Double
    let bmsSOC: Int
    let bmsTemp: Double
    let tripDistance: Double
    let tripTime: Int
    let bodyTemp: Double
    let gearMode: Int
    let estimatedRange: Double
    let errorCode: Int
    let warnCode: Int
    let regenLevel: Int
    let speedResponse: Int
    // GPS
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let gpsSpeed: Double?
    let gpsCourse: Double?
    let horizontalAccuracy: Double?
    // Surface roughness
    let roughnessScore: Double?
    let maxAcceleration: Double?
    // Health
    let heartRate: Int?
}

/// A completed ride log.
struct RideLog: Codable, Sendable {
    let rideId: String
    let startTime: Date
    let endTime: Date
    let samples: [TelemetrySample]
    let totalDistance: Double
    let maxSpeed: Double
    let avgSpeed: Double
    let batteryUsed: Int
    let startBattery: Int
    let endBattery: Int
}

/// Tracks ride lifecycle: start detection, sample collection, stop detection.
actor RideTracker {
    enum RideState: Sendable {
        case idle
        case riding
        case stopped  // temporarily stopped (traffic light)
    }

    private(set) var state: RideState = .idle
    private var currentRideId: String?
    private var rideStartTime: Date?
    private var samples: [TelemetrySample] = []
    private var startBattery: Int = 0
    private var maxSpeed: Double = 0
    private var speedSum: Double = 0
    private var speedCount: Int = 0
    private var stoppedSince: Date?
    // 5 minutes of no movement → end ride
    private let stopTimeout: TimeInterval = 300

    /// Callback when a ride ends.
    var onRideComplete: (@Sendable (RideLog) -> Void)?

    /// Process a new telemetry sample. Handles ride start/stop detection.
    func addSample(_ sample: TelemetrySample) {
        switch state {
        case .idle:
            if sample.speed > 0 {
                startRide(firstSample: sample)
            }

        case .riding:
            samples.append(sample)
            updateStats(sample)

            if sample.speed == 0 {
                state = .stopped
                stoppedSince = Date()
            }

        case .stopped:
            samples.append(sample)
            updateStats(sample)

            if sample.speed > 0 {
                state = .riding
                stoppedSince = nil
            } else if let stopped = stoppedSince,
                      Date().timeIntervalSince(stopped) > stopTimeout {
                endRide(endBattery: sample.battery)
            }
        }
    }

    /// Force-end the current ride (e.g., BLE disconnect).
    func forceEndRide(endBattery: Int) {
        guard state != .idle else { return }
        endRide(endBattery: endBattery)
    }

    private func startRide(firstSample: TelemetrySample) {
        currentRideId = UUID().uuidString
        rideStartTime = Date()
        startBattery = firstSample.battery
        maxSpeed = 0
        speedSum = 0
        speedCount = 0
        samples = [firstSample]
        state = .riding
        updateStats(firstSample)
        logger.info("Ride started: \(self.currentRideId ?? "")")
    }

    private func updateStats(_ sample: TelemetrySample) {
        if sample.speed > maxSpeed { maxSpeed = sample.speed }
        speedSum += sample.speed
        speedCount += 1
    }

    private func endRide(endBattery: Int) {
        guard let rideId = currentRideId, let startTime = rideStartTime else { return }

        let rideLog = RideLog(
            rideId: rideId,
            startTime: startTime,
            endTime: Date(),
            samples: samples,
            totalDistance: samples.last?.tripDistance ?? 0,
            maxSpeed: maxSpeed,
            avgSpeed: speedCount > 0 ? speedSum / Double(speedCount) : 0,
            batteryUsed: max(0, startBattery - endBattery),
            startBattery: startBattery,
            endBattery: endBattery
        )

        logger.info("Ride ended: \(rideId) distance=\(rideLog.totalDistance)km")
        onRideComplete?(rideLog)

        state = .idle
        currentRideId = nil
        rideStartTime = nil
        samples.removeAll()
        stoppedSince = nil
    }

    func getCurrentRideId() -> String? { currentRideId }
    func getSampleCount() -> Int { samples.count }
}
#endif
