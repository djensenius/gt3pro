//
//  WeatherSnapshot.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation

/// A snapshot of weather conditions captured during a ride.
struct WeatherSnapshot: Codable, Sendable {
    let temp: Double
    let feelsLike: Double
    let humidity: Double
    let windSpeed: Double
    let windDirection: Double
    let condition: String
    let conditionSymbol: String
    let uvIndex: Double
    let pressure: Double
}

/// Returns an SF Symbol name for a weather condition string.
func weatherSymbol(for condition: String) -> String {
    let lower = condition.lowercased()
    if lower.contains("clear") || lower.contains("sunny") {
        return "sun.max.fill"
    } else if lower.contains("partly cloudy") || lower.contains("mostly clear") {
        return "cloud.sun.fill"
    } else if lower.contains("cloud") || lower.contains("overcast") {
        return "cloud.fill"
    } else if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") {
        return "cloud.rain.fill"
    } else if lower.contains("thunder") || lower.contains("storm") {
        return "cloud.bolt.rain.fill"
    } else if lower.contains("snow") || lower.contains("sleet") || lower.contains("flurr") {
        return "cloud.snow.fill"
    } else if lower.contains("fog") || lower.contains("haze") || lower.contains("mist") {
        return "cloud.fog.fill"
    } else if lower.contains("wind") || lower.contains("breezy") {
        return "wind"
    }
    return "cloud.fill"
}
