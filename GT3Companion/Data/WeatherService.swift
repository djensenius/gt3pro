//
//  WeatherService.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreLocation
import Foundation
import os
@preconcurrency import WeatherKit

private let logger = Logger(
    subsystem: "org.davidjensenius.GT3Companion",
    category: "Weather"
)

/// Fetches current weather conditions using Apple WeatherKit.
actor WeatherService {
    static let shared = WeatherService()
    private let service = WeatherKit.WeatherService()

    /// Fetch current weather for a location.
    func fetchWeather(at location: CLLocation) async -> WeatherSnapshot? {
        do {
            let weather = try await service.weather(for: location)
            let current = weather.currentWeather
            let snapshot = WeatherSnapshot(
                temp: current.temperature.converted(to: .celsius).value,
                feelsLike: current.apparentTemperature.converted(to: .celsius).value,
                humidity: current.humidity * 100,
                windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
                windDirection: current.wind.direction.converted(to: .degrees).value,
                condition: current.condition.description,
                conditionSymbol: current.symbolName,
                uvIndex: Double(current.uvIndex.value),
                pressure: current.pressure.converted(to: .hectopascals).value
            )
            logger.info("Weather: \(snapshot.condition) \(snapshot.temp)°C")
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "Weather fetched: \(snapshot.condition) \(String(format: "%.0f", snapshot.temp))°C",
                    category: "Weather"
                )
            }
            return snapshot
        } catch {
            logger.error("WeatherKit error: \(error.localizedDescription)")
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "WeatherKit error: \(error.localizedDescription)",
                    category: "Weather",
                    level: .error
                )
            }
            return nil
        }
    }
}
#endif
