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
    /// Most-used gear mode during the ride (1=Walk, 2=Eco, 3=Sport, 4=Race).
    let primaryGearMode: Int
    let weather: WeatherSnapshot?
    /// GeoJSON-style coordinates: [[longitude, latitude, altitude]].
    let gpsTrack: [[Double]]?
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
    private var gearModeHistogram: [Int: Int] = [:]
    private var currentWeather: WeatherSnapshot?
    private var fetchingWeather = false
    // 5 minutes of no movement → end ride
    private let stopTimeout: TimeInterval = 300

    /// Callback when a ride ends.
    var onRideComplete: (@Sendable (RideLog) -> Void)?

    /// Process a new telemetry sample. Handles ride start/stop detection.
    func addSample(_ sample: TelemetrySample) {
        switch state {
        case .idle:
            // Don't start tracking until actually riding (not walking/pushing)
            let isWalkMode = sample.gearMode == 1
            if sample.speed > 5 && !isWalkMode {
                startRide(firstSample: sample)
            }

        case .riding:
            // Treat walk mode under 10 km/h as stopped (not real riding)
            let isWalking = sample.gearMode == 1 && sample.speed < 10
            if sample.speed == 0 || isWalking {
                state = .stopped
                stoppedSince = stoppedSince ?? Date()
            } else {
                samples.append(sample)
                updateStats(sample)
            }

        case .stopped:
            let isWalking = sample.gearMode == 1 && sample.speed < 10
            if sample.speed > 0 && !isWalking {
                state = .riding
                stoppedSince = nil
                samples.append(sample)
                updateStats(sample)
            } else if let stopped = stoppedSince,
                      Date().timeIntervalSince(stopped) > stopTimeout {
                endRide(endBattery: sample.battery, weather: currentWeather)
            }
        }
    }

    /// Force-end the current ride (e.g., BLE disconnect).
    func forceEndRide(endBattery: Int) {
        guard state != .idle else { return }
        endRide(endBattery: endBattery, weather: currentWeather)
    }

    /// Set the weather snapshot for the current ride.
    func setWeather(_ weather: WeatherSnapshot?) {
        self.currentWeather = weather
    }

    private func startRide(firstSample: TelemetrySample) {
        currentRideId = UUID().uuidString
        rideStartTime = Date()
        startBattery = firstSample.battery
        maxSpeed = 0
        speedSum = 0
        speedCount = 0
        gearModeHistogram = [:]
        currentWeather = nil
        samples = [firstSample]
        state = .riding
        updateStats(firstSample)
        logger.info("Ride started: \(self.currentRideId ?? "")")
    }

    private func updateStats(_ sample: TelemetrySample) {
        if sample.speed > maxSpeed { maxSpeed = sample.speed }
        speedSum += sample.speed
        speedCount += 1
        if sample.gearMode > 0 {
            gearModeHistogram[sample.gearMode, default: 0] += 1
        }
    }

    private func endRide(endBattery: Int, weather: WeatherSnapshot?) {
        guard let rideId = currentRideId, let startTime = rideStartTime else { return }

        let primaryMode = gearModeHistogram.max(by: { $0.value < $1.value })?.key ?? 0

        // Build GeoJSON-style coordinate array from GPS samples
        let gpsTrack: [[Double]]? = {
            let coords = samples.compactMap { sample -> [Double]? in
                guard let lat = sample.latitude, let lon = sample.longitude,
                      lat != 0, lon != 0 else { return nil }
                return [lon, lat, sample.altitude ?? 0]
            }
            return coords.count >= 2 ? coords : nil
        }()

        let gpsDistance = computeGPSDistance()
        let scooterDistance = samples.last?.tripDistance ?? 0
        let distance = gpsDistance > 0 ? gpsDistance : scooterDistance

        let rideLog = RideLog(
            rideId: rideId,
            startTime: startTime,
            endTime: Date(),
            samples: samples,
            totalDistance: distance,
            maxSpeed: maxSpeed,
            avgSpeed: speedCount > 0 ? speedSum / Double(speedCount) : 0,
            batteryUsed: max(0, startBattery - endBattery),
            startBattery: startBattery,
            endBattery: endBattery,
            primaryGearMode: primaryMode,
            weather: weather,
            gpsTrack: gpsTrack
        )

        let distStr = String(format: "%.2f", distance)
        let gpsStr = String(format: "%.2f", gpsDistance)
        let scoStr = String(format: "%.2f", scooterDistance)
        logger.info("Ride ended: \(rideId) distance=\(distStr)km (gps=\(gpsStr) scooter=\(scoStr)) mode=\(primaryMode)")
        onRideComplete?(rideLog)

        state = .idle
        currentRideId = nil
        rideStartTime = nil
        samples.removeAll()
        stoppedSince = nil
        gearModeHistogram = [:]
        currentWeather = nil
        fetchingWeather = false
    }

    func getCurrentRideId() -> String? { currentRideId }
    func getSampleCount() -> Int { samples.count }
    func hasWeather() -> Bool { currentWeather != nil }
    func isFetchingWeather() -> Bool { fetchingWeather }
    func setFetchingWeather(_ value: Bool) { fetchingWeather = value }

    // MARK: - GPS Distance

    /// Sum haversine distances between consecutive GPS samples (km).
    private func computeGPSDistance() -> Double {
        Self.gpsDistance(from: samples)
    }

    /// Compute total GPS distance from an array of telemetry samples.
    static func gpsDistance(from samples: [TelemetrySample]) -> Double {
        let coords = samples.compactMap { sample -> (lat: Double, lon: Double)? in
            guard let lat = sample.latitude, let lon = sample.longitude,
                  lat != 0, lon != 0,
                  let acc = sample.horizontalAccuracy, acc > 0,
                  acc < gpsAccuracyThresholdMetres else { return nil }
            return (lat, lon)
        }
        guard coords.count >= 2 else { return 0 }

        var total = 0.0
        for idx in 1..<coords.count {
            total += haversineDistanceKm(
                lat1: coords[idx - 1].lat, lon1: coords[idx - 1].lon,
                lat2: coords[idx].lat, lon2: coords[idx].lon
            )
        }
        return total
    }
}
#endif
