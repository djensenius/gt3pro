//
//  SurfaceRoughnessTracker.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreMotion
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Roughness")

/// Surface roughness measurement from accelerometer data.
struct RoughnessSample: Sendable {
    let timestamp: Date
    let roughnessScore: Double      // RMS of Z-axis acceleration
    let maxAcceleration: Double     // Peak G-force in window
    let accelerometerVariance: Double
}

/// CoreMotion accelerometer-based surface roughness tracker.
/// Records at 50 Hz internally, outputs smoothed samples at ~1 Hz.
final class SurfaceRoughnessTracker: @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private let processingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "org.davidjensenius.GT3Companion.roughness"
        return queue
    }()
    private nonisolated(unsafe) var zValues: [Double] = []
    private let windowSize = 50  // 1 second at 50 Hz
    private nonisolated(unsafe) var _isTracking = false
    var isTracking: Bool { _isTracking }
    private nonisolated(unsafe) var _latestSample: RoughnessSample?
    var latestSample: RoughnessSample? { _latestSample }

    var onSample: (@Sendable (RoughnessSample) -> Void)?

    func startTracking() {
        guard motionManager.isAccelerometerAvailable, !_isTracking else { return }
        _isTracking = true
        zValues.removeAll()

        motionManager.accelerometerUpdateInterval = 1.0 / 50.0  // 50 Hz
        motionManager.startAccelerometerUpdates(to: processingQueue) { [weak self] data, error in
            guard let self, let acceleration = data?.acceleration else {
                if let error { logger.error("Accelerometer error: \(error.localizedDescription)") }
                return
            }
            self.processAcceleration(zValue: acceleration.z)
        }
        logger.info("Surface roughness tracking started")
    }

    func stopTracking() {
        _isTracking = false
        motionManager.stopAccelerometerUpdates()
        zValues.removeAll()
        logger.info("Surface roughness tracking stopped")
    }

    private func processAcceleration(zValue: Double) {
        zValues.append(zValue)

        guard zValues.count >= windowSize else { return }

        let mean = zValues.reduce(0, +) / Double(zValues.count)
        let variance = zValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(zValues.count)
        let sumOfSquares = zValues.reduce(0) { $0 + $1 * $1 }
        let rms = (sumOfSquares / Double(zValues.count)).squareRoot()
        let maxAcc = zValues.map { abs($0) }.max() ?? 0

        let sample = RoughnessSample(
            timestamp: Date(),
            roughnessScore: rms,
            maxAcceleration: maxAcc,
            accelerometerVariance: variance
        )

        _latestSample = sample
        onSample?(sample)
        zValues.removeAll()
    }
}
#endif
