//
//  ServerRide.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation

enum GT3APIConfig {
    static let baseURL = "https://api.fluxhaus.io"
}

/// Paginated response from GET /gt3/rides.
struct ServerRidesResponse: Decodable {
    let rides: [ServerRide]
    let page: Int
    let limit: Int
}

/// A single ride record as returned by the FluxHaus server.
struct ServerRide: Decodable {
    let id: String
    let startTime: Date
    let endTime: Date?
    let distance: Double
    let maxSpeed: Double
    let avgSpeed: Double
    let batteryUsed: Int
    let startBattery: Int
    let endBattery: Int?
    let weatherTemp: Double?
    let weatherFeelsLike: Double?
    let weatherHumidity: Double?
    let weatherWindSpeed: Double?
    let weatherWindDirection: Double?
    let weatherCondition: String?
    let weatherUVIndex: Double?
    let weatherPressure: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case distance
        case maxSpeed = "max_speed"
        case avgSpeed = "avg_speed"
        case batteryUsed = "battery_used"
        case startBattery = "start_battery"
        case endBattery = "end_battery"
        case weatherTemp = "weather_temp"
        case weatherFeelsLike = "weather_feels_like"
        case weatherHumidity = "weather_humidity"
        case weatherWindSpeed = "weather_wind_speed"
        case weatherWindDirection = "weather_wind_direction"
        case weatherCondition = "weather_condition"
        case weatherUVIndex = "weather_uv_index"
        case weatherPressure = "weather_pressure"
    }
}

/// Response from GET /gt3/rides/:id/samples.
struct ServerSamplesResponse: Decodable {
    let samples: [ServerSample]
    let rideId: String
    let source: String
}

/// A single telemetry sample from the server.
struct ServerSample: Decodable {
    let time: Date
    let speed: Double
    let battery: Int
    let bmsVoltage: Double?
    let bmsCurrent: Double?
    let bmsSoc: Int?
    let bmsTemp: Double?
    let bodyTemp: Double?
    let gearMode: Int?
    let tripDistance: Double?
    let tripTime: Int?
    let rangeEstimate: Double?
    let errorCode: Int?
    let warnCode: Int?
    let regenLevel: Int?
    let speedResponse: Int?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?
    let gpsSpeed: Double?
    let gpsCourse: Double?
    let horizontalAccuracy: Double?
    let roughnessScore: Double?
    let maxAcceleration: Double?
    let heartRate: Int?

    enum CodingKeys: String, CodingKey {
        case time = "_time"
        case speed, battery
        case bmsVoltage = "bms_voltage"
        case bmsCurrent = "bms_current"
        case bmsSoc = "bms_soc"
        case bmsTemp = "bms_temp"
        case bodyTemp = "body_temp"
        case gearMode = "gear_mode"
        case tripDistance = "trip_distance"
        case tripTime = "trip_time"
        case rangeEstimate = "range_estimate"
        case errorCode = "error_code"
        case warnCode = "warn_code"
        case regenLevel = "regen_level"
        case speedResponse = "speed_response"
        case latitude, longitude, altitude
        case gpsSpeed = "gps_speed"
        case gpsCourse = "gps_course"
        case horizontalAccuracy = "horizontal_accuracy"
        case roughnessScore = "roughness_score"
        case maxAcceleration = "max_acceleration"
        case heartRate = "heart_rate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle ISO 8601 dates with or without fractional seconds
        let timeString = try container.decode(String.self, forKey: .time)
        if let date = Self.iso8601Fractional.date(from: timeString) {
            self.time = date
        } else if let date = Self.iso8601Basic.date(from: timeString) {
            self.time = date
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .time, in: container,
                debugDescription: "Cannot parse date: \(timeString)"
            )
        }

        self.speed = (try? container.decode(Double.self, forKey: .speed)) ?? 0
        // battery may arrive as Double from JSON
        if let intVal = try? container.decode(Int.self, forKey: .battery) {
            self.battery = intVal
        } else if let dblVal = try? container.decode(Double.self, forKey: .battery) {
            self.battery = Int(dblVal)
        } else {
            self.battery = 0
        }

        self.bmsVoltage = try? container.decode(Double.self, forKey: .bmsVoltage)
        self.bmsCurrent = try? container.decode(Double.self, forKey: .bmsCurrent)
        self.bmsSoc = Self.decodeFlexibleInt(container: container, key: .bmsSoc)
        self.bmsTemp = try? container.decode(Double.self, forKey: .bmsTemp)
        self.bodyTemp = try? container.decode(Double.self, forKey: .bodyTemp)
        self.gearMode = Self.decodeFlexibleInt(container: container, key: .gearMode)
        self.tripDistance = try? container.decode(Double.self, forKey: .tripDistance)
        self.tripTime = Self.decodeFlexibleInt(container: container, key: .tripTime)
        self.rangeEstimate = try? container.decode(Double.self, forKey: .rangeEstimate)
        self.errorCode = Self.decodeFlexibleInt(container: container, key: .errorCode)
        self.warnCode = Self.decodeFlexibleInt(container: container, key: .warnCode)
        self.regenLevel = Self.decodeFlexibleInt(container: container, key: .regenLevel)
        self.speedResponse = Self.decodeFlexibleInt(container: container, key: .speedResponse)
        self.latitude = try? container.decode(Double.self, forKey: .latitude)
        self.longitude = try? container.decode(Double.self, forKey: .longitude)
        self.altitude = try? container.decode(Double.self, forKey: .altitude)
        self.gpsSpeed = try? container.decode(Double.self, forKey: .gpsSpeed)
        self.gpsCourse = try? container.decode(Double.self, forKey: .gpsCourse)
        self.horizontalAccuracy = try? container.decode(Double.self, forKey: .horizontalAccuracy)
        self.roughnessScore = try? container.decode(Double.self, forKey: .roughnessScore)
        self.maxAcceleration = try? container.decode(Double.self, forKey: .maxAcceleration)
        self.heartRate = Self.decodeFlexibleInt(container: container, key: .heartRate)
    }

    private static func decodeFlexibleInt(
        container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> Int? {
        if let intVal = try? container.decode(Int.self, forKey: key) {
            return intVal
        }
        if let dblVal = try? container.decode(Double.self, forKey: key) {
            return Int(dblVal)
        }
        return nil
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static let iso8601Basic: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt
    }()
}
