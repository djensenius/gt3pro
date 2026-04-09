//
//  SwiftDataModels.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftData

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
    @Relationship(deleteRule: .cascade) var samples: [PersistedSample]?
    var gpsTrackJSON: Data?
    var healthDataJSON: Data?
    var metadataJSON: Data?

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
        self.samples = []
    }
}

@Model
class PersistedSample {
    var timestamp: Date
    var speed: Double
    var battery: Int
    var bms1Voltage: Double
    var bms1Current: Double
    var bms1SOC: Int
    var bms1Temp: Double
    var bms2Voltage: Double
    var bms2Current: Double
    var bms2SOC: Int
    var bms2Temp: Double
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
        self.bms1Voltage = 0
        self.bms1Current = 0
        self.bms1SOC = 0
        self.bms1Temp = 0
        self.bms2Voltage = 0
        self.bms2Current = 0
        self.bms2SOC = 0
        self.bms2Temp = 0
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
