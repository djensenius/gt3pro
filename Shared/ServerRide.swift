//
//  ServerRide.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

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
