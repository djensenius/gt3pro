//
//  SwiftDataModels.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftData

// MARK: - PersistedRide view helpers

extension PersistedRide {
    var duration: TimeInterval {
        guard let end = endTime else { return 0 }
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Recompute totalDistance from GPS samples (haversine sum, km).
    /// Call this to fix rides that have stale scooter-reported distances.
    func recomputeGPSDistance() {
        let sorted = (samples ?? []).sorted { $0.timestamp < $1.timestamp }
        let coords = sorted.compactMap { sample -> (lat: Double, lon: Double)? in
            guard let lat = sample.latitude, let lon = sample.longitude,
                  lat != 0, lon != 0,
                  let acc = sample.horizontalAccuracy, acc > 0,
                  acc < gpsAccuracyThresholdMetres else { return nil }
            return (lat, lon)
        }
        guard coords.count >= 2 else { return }

        var total = 0.0
        for idx in 1..<coords.count {
            total += haversineDistanceKm(
                lat1: coords[idx - 1].lat, lon1: coords[idx - 1].lon,
                lat2: coords[idx].lat, lon2: coords[idx].lon
            )
        }
        totalDistance = total
    }

    var sortedPhotos: [PersistedRidePhoto] {
        (photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var ridePresentation: RidePresentation {
        RidePresentation(ride: self)
    }

    var healthSummary: PersistedRideHealthSummary? {
        let decoded = PersistedRideHealthSummary.decode(from: healthDataJSON)
        let presentation = ridePresentation
        let averageHeartRate = decoded?.averageHeartRate ?? presentation.averageHeartRate
        let maxHeartRate = decoded?.maxHeartRate ?? presentation.maxHeartRate
        let activeCalories = decoded?.activeCalories
        guard averageHeartRate != nil || maxHeartRate != nil || activeCalories != nil else { return nil }
        return PersistedRideHealthSummary(
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeCalories: activeCalories
        )
    }
}

struct PersistedRideHealthSummary {
    let averageHeartRate: Int?
    let maxHeartRate: Int?
    let activeCalories: Double?

    static func decode(from data: Data?) -> PersistedRideHealthSummary? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PersistedRideHealthSummary.self, from: data)
    }
}

extension PersistedRideHealthSummary: Decodable {
    enum CodingKeys: String, CodingKey {
        case averageHeartRate
        case avgHeartRate
        case maxHeartRate
        case activeCalories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.averageHeartRate = try container.decodeIfPresent(Int.self, forKey: .averageHeartRate)
            ?? container.decodeIfPresent(Int.self, forKey: .avgHeartRate)
        self.maxHeartRate = try container.decodeIfPresent(Int.self, forKey: .maxHeartRate)
        self.activeCalories = try container.decodeIfPresent(Double.self, forKey: .activeCalories)
    }
}

struct RidePresentation {
    let sortedSamples: [PersistedSample]
    let routeCoordinates: [RouteCoordinate]
    let speedSamples: [(timestamp: Date, value: Double)]
    let batterySamples: [(timestamp: Date, value: Int)]
    let bmsTempSamples: [(timestamp: Date, value: Double)]
    let roughnessSamples: [(timestamp: Date, value: Double)]
    let heartRateSamples: [(timestamp: Date, value: Int)]

    init(ride: PersistedRide) {
        let samples = (ride.samples ?? []).sorted { $0.timestamp < $1.timestamp }
        self.sortedSamples = samples
        self.routeCoordinates = samples.compactMap { sample in
            guard let latitude = sample.latitude,
                  let longitude = sample.longitude,
                  latitude != 0,
                  longitude != 0 else { return nil }
            if let accuracy = sample.horizontalAccuracy,
               accuracy <= 0 || accuracy >= gpsAccuracyThresholdMetres {
                return nil
            }
            return RouteCoordinate(latitude: latitude, longitude: longitude, speed: sample.speed)
        }
        self.speedSamples = samples.map { ($0.timestamp, $0.speed) }
        self.batterySamples = samples.map { ($0.timestamp, $0.battery) }
        self.bmsTempSamples = samples
            .filter { $0.bmsTemp > 0 }
            .map { ($0.timestamp, $0.bmsTemp) }
        self.roughnessSamples = samples.compactMap { sample in
            guard let roughness = sample.roughnessScore else { return nil }
            return (sample.timestamp, roughness)
        }
        self.heartRateSamples = samples.compactMap { sample in
            guard let heartRate = sample.heartRate, heartRate > 0 else { return nil }
            return (sample.timestamp, heartRate)
        }
    }

    var hasTelemetry: Bool {
        !sortedSamples.isEmpty
    }

    var hasRoute: Bool {
        routeCoordinates.count >= 2
    }

    var averageRoughness: Double? {
        average(roughnessSamples.map { $0.value })
    }

    var maxRoughness: Double? {
        roughnessSamples.map { $0.value }.max()
    }

    var averageHeartRate: Int? {
        guard let avg = average(heartRateSamples.map { Double($0.value) }) else { return nil }
        return Int(avg.rounded())
    }

    var maxHeartRate: Int? {
        heartRateSamples.map { $0.value }.max()
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

@Model
class PersistedRide {
    var rideId: String
    var startTime: Date
    var endTime: Date?
    var totalDistance: Double
    var maxSpeed: Double
    var avgSpeed: Double
    var batteryUsed: Int
    var startBattery: Int
    var endBattery: Int?
    var uploaded: Bool
    var primaryGearMode: Int
    @Relationship(deleteRule: .cascade) var samples: [PersistedSample]?
    @Relationship(deleteRule: .cascade, inverse: \PersistedRidePhoto.ride) var photos: [PersistedRidePhoto]?
    var gpsTrackJSON: Data?
    var healthDataJSON: Data?
    var metadataJSON: Data?
    var weatherTemp: Double?
    var weatherFeelsLike: Double?
    var weatherHumidity: Double?
    var weatherWindSpeed: Double?
    var weatherWindDirection: Double?
    var weatherCondition: String?
    var weatherConditionSymbol: String?
    var weatherUVIndex: Double?
    var weatherPressure: Double?
    var samplesHydrated: Bool?

    init(rideId: String, startTime: Date, startBattery: Int) {
        self.rideId = rideId
        self.startTime = startTime
        self.totalDistance = 0
        self.maxSpeed = 0
        self.avgSpeed = 0
        self.batteryUsed = 0
        self.startBattery = startBattery
        self.endBattery = nil
        self.uploaded = false
        self.primaryGearMode = 0
        self.samples = []
        self.photos = []
        self.samplesHydrated = false
    }
}

@Model
class PersistedRidePhoto {
    var photoId: String
    var createdAt: Date
    var imageData: Data
    var mimeType: String
    var latitude: Double?
    var longitude: Double?
    var uploaded: Bool
    var uploadAttemptedAt: Date?
    var pendingRideId: String?
    var ride: PersistedRide?

    init(
        imageData: Data,
        mimeType: String = "image/jpeg",
        createdAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        ride: PersistedRide? = nil,
        pendingRideId: String? = nil
    ) {
        self.photoId = UUID().uuidString
        self.createdAt = createdAt
        self.imageData = imageData
        self.mimeType = mimeType
        self.latitude = latitude
        self.longitude = longitude
        self.uploaded = false
        self.uploadAttemptedAt = nil
        self.pendingRideId = pendingRideId
        self.ride = ride
    }
}

@Model
class PersistedSample {
    var timestamp: Date
    var speed: Double
    var battery: Int
    var bmsVoltage: Double
    var bmsCurrent: Double
    var bmsSOC: Int
    var bmsTemp: Double
    var tripDistance: Double
    var bodyTemp: Double
    var gearMode: Int
    var estimatedRange: Double
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var gpsSpeed: Double?
    var gpsCourse: Double?
    var horizontalAccuracy: Double?
    var roughnessScore: Double?
    var maxAcceleration: Double?
    var heartRate: Int?
    var tripTime: Int
    var errorCode: Int
    var warnCode: Int
    var regenLevel: Int
    var speedResponse: Int

    init(timestamp: Date, speed: Double, battery: Int) {
        self.timestamp = timestamp
        self.speed = speed
        self.battery = battery
        self.bmsVoltage = 0
        self.bmsCurrent = 0
        self.bmsSOC = 0
        self.bmsTemp = 0
        self.tripDistance = 0
        self.bodyTemp = 0
        self.gearMode = 0
        self.estimatedRange = 0
        self.tripTime = 0
        self.errorCode = 0
        self.warnCode = 0
        self.regenLevel = 0
        self.speedResponse = 0
    }
}

@Model
class UploadQueueItem {
    var itemId: String
    var payload: Data
    var endpoint: String
    var createdAt: Date
    var retryCount: Int
    var lastAttempt: Date?

    init(payload: Data, endpoint: String) {
        self.itemId = UUID().uuidString
        self.payload = payload
        self.endpoint = endpoint
        self.createdAt = Date()
        self.retryCount = 0
    }
}

@Model
class StoredCredential {
    var serialNumber: String
    var password: Data
    var btName: String
    var lastConnected: Date

    init(serialNumber: String, password: Data, btName: String) {
        self.serialNumber = serialNumber
        self.password = password
        self.btName = btName
        self.lastConnected = Date()
    }
}
