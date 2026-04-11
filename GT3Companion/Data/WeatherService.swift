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
import WeatherKit

private let logger = Logger(
    subsystem: "org.davidjensenius.GT3Companion",
    category: "Weather"
)

/// Fetches current weather conditions using Apple WeatherKit.
actor WeatherService {
    static let shared = WeatherService()
    private let service = WeatherService.makeService()

    private static func makeService() -> WeatherKit.WeatherService {
        WeatherKit.WeatherService.shared
    }

    /// Fetch current weather for a location.
    func fetchWeather(at location: CLLocation) async -> WeatherSnapshot? {
        do {
            let weather = try await service.weather(
                for: location,
                including: .current
            )
            let snapshot = WeatherSnapshot(
                temp: weather.temperature.converted(to: .celsius).value,
                feelsLike: weather.apparentTemperature.converted(to: .celsius).value,
                humidity: weather.humidity * 100,
                windSpeed: weather.wind.speed.converted(to: .kilometersPerHour).value,
                windDirection: weather.wind.direction.converted(to: .degrees).value,
                condition: weather.condition.description,
                conditionSymbol: weather.symbolName,
                uvIndex: Double(weather.uvIndex.value),
                pressure: weather.pressure.converted(to: .hectopascals).value
            )
            logger.info("Weather: \(snapshot.condition) \(snapshot.temp)°C")
            return snapshot
        } catch {
            logger.error("WeatherKit error: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
