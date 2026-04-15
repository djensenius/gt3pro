//
//  SwiftDataModels.swift
//  GT3Companion
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
                  let acc = sample.horizontalAccuracy, acc > 0, acc < 50 else { return nil }
            return (lat, lon)
        }
        guard coords.count >= 2 else { return }

        var total = 0.0
        for idx in 1..<coords.count {
            let dLat = (coords[idx].lat - coords[idx - 1].lat) * .pi / 180
            let dLon = (coords[idx].lon - coords[idx - 1].lon) * .pi / 180
            let aVal = sin(dLat / 2) * sin(dLat / 2)
                + cos(coords[idx - 1].lat * .pi / 180) * cos(coords[idx].lat * .pi / 180)
                * sin(dLon / 2) * sin(dLon / 2)
            total += 6371.0 * 2 * atan2(sqrt(aVal), sqrt(1 - aVal))
        }
        totalDistance = total
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
