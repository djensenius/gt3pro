//
//  PreviewHelpers.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftData

#if DEBUG
import SwiftUI

/// Shared mock data and helpers for SwiftUI previews.
@MainActor
enum PreviewData {
    /// An in-memory model container pre-populated with sample rides.
    static let container: ModelContainer = {
        let schema = Schema([
            PersistedRide.self,
            PersistedSample.self,
            PersistedRidePhoto.self,
            UploadQueueItem.self,
            StoredCredential.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        for ride in sampleRides {
            context.insert(ride)
        }
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save preview SwiftData context: \(error)")
        }
        return container
    }()

    // MARK: - Sample Rides

    static var sampleRide: PersistedRide {
        let ride = PersistedRide(
            rideId: "preview-ride-1",
            startTime: Date().addingTimeInterval(-3600),
            startBattery: 95
        )
        ride.endTime = Date()
        ride.totalDistance = 12.5
        ride.maxSpeed = 72
        ride.avgSpeed = 38
        ride.batteryUsed = 15
        ride.endBattery = 80
        ride.uploaded = true
        ride.samples = sampleSamples(start: ride.startTime, count: 30)
        ride.weatherTemp = 22
        ride.weatherFeelsLike = 20
        ride.weatherHumidity = 55
        ride.weatherWindSpeed = 12
        ride.weatherWindDirection = 225
        ride.weatherCondition = "Partly Cloudy"
        ride.weatherConditionSymbol = "cloud.sun.fill"
        ride.weatherUVIndex = 4
        ride.weatherPressure = 1013
        return ride
    }

    static var sampleRides: [PersistedRide] {
        let ride1 = sampleRide

        let ride2 = PersistedRide(
            rideId: "preview-ride-2",
            startTime: Date().addingTimeInterval(-86400),
            startBattery: 100
        )
        ride2.endTime = Date().addingTimeInterval(-82800)
        ride2.totalDistance = 8.3
        ride2.maxSpeed = 65
        ride2.avgSpeed = 32
        ride2.batteryUsed = 10
        ride2.endBattery = 90
        ride2.uploaded = true
        ride2.samples = sampleSamples(start: ride2.startTime, count: 30)
        ride2.weatherTemp = 28
        ride2.weatherFeelsLike = 30
        ride2.weatherHumidity = 40
        ride2.weatherWindSpeed = 8
        ride2.weatherWindDirection = 180
        ride2.weatherCondition = "Clear"
        ride2.weatherConditionSymbol = "sun.max.fill"
        ride2.weatherUVIndex = 7
        ride2.weatherPressure = 1018

        let ride3 = PersistedRide(
            rideId: "preview-ride-3",
            startTime: Date().addingTimeInterval(-172800),
            startBattery: 88
        )
        ride3.endTime = Date().addingTimeInterval(-169200)
        ride3.totalDistance = 22.1
        ride3.maxSpeed = 78
        ride3.avgSpeed = 42
        ride3.batteryUsed = 28
        ride3.endBattery = 60
        ride3.uploaded = false
        ride3.samples = sampleSamples(start: ride3.startTime, count: 30)
        ride3.weatherTemp = 14
        ride3.weatherFeelsLike = 11
        ride3.weatherHumidity = 78
        ride3.weatherWindSpeed = 22
        ride3.weatherWindDirection = 315
        ride3.weatherCondition = "Rain"
        ride3.weatherConditionSymbol = "cloud.rain.fill"
        ride3.weatherUVIndex = 1
        ride3.weatherPressure = 1005

        return [ride1, ride2, ride3]
    }

    // MARK: - Sample Route Coordinates

    struct PreviewCoordinate {
        let latitude: Double
        let longitude: Double
        let speed: Double
    }

    static var sampleRouteCoordinates: [PreviewCoordinate] {
        (0..<20).map { index in
            PreviewCoordinate(
                latitude: 43.6532 + Double(index) * 0.001,
                longitude: -79.3832 + Double(index) * 0.0005,
                speed: 20.0 + Double(index) * 2.0
            )
        }
    }

    // MARK: - Helpers

    private static func sampleSamples(start: Date, count: Int) -> [PersistedSample] {
        (0..<count).map { index in
            let sample = PersistedSample(
                timestamp: start.addingTimeInterval(Double(index) * 60),
                // Deterministic preview data
                speed: 15.0 + Double(index) * 1.8,
                battery: max(60, 95 - index)
            )
            sample.bmsVoltage = 58.8
            sample.bmsCurrent = 5.0 + Double(index) * 0.7
            sample.bmsSOC = max(60, 95 - index)
            sample.bmsTemp = 30.0 + Double(index) * 0.5
            sample.tripDistance = Double(index) * 0.4
            sample.bodyTemp = 35.0 + Double(index) * 0.5
            sample.gearMode = 3
            sample.estimatedRange = Double(max(20, 60 - index))
            sample.latitude = 43.6532 + Double(index) * 0.001
            sample.longitude = -79.3832 + Double(index) * 0.0005
            sample.altitude = 76.0 + Double(index) * 0.3
            sample.gpsSpeed = 15.0 + Double(index) * 1.8
            sample.roughnessScore = Double.random(in: 0.1...0.8)
            return sample
        }
    }
}
#endif

/// Seed data used when the app is running in Demo Mode.
///
/// These rides are intentionally richer than lightweight SwiftUI preview fixtures so
/// the real Ride History and Ride Detail screens have routes, charts, weather, and
/// health summaries to explore on devices such as iPhone Duo.
@MainActor
enum DemoRideData {
    private static let rideIdPrefix = "demo-ride-"

    static func seedIfNeeded(in context: ModelContext) {
        let rides = (try? context.fetch(FetchDescriptor<PersistedRide>())) ?? []
        let demoRides = rides.filter { $0.rideId.hasPrefix(rideIdPrefix) }
        let needsRefresh = demoRides.count < 4 || demoRides.contains { ride in
            (ride.photos ?? []).contains { $0.imageData.count < 100 }
        }
        guard demoRides.isEmpty || needsRefresh else { return }

        for ride in demoRides {
            context.delete(ride)
        }
        for ride in sampleRides(referenceDate: Date()) {
            context.insert(ride)
        }
        try? context.save()
    }

    static func removeDemoRides(in context: ModelContext) {
        let rides = (try? context.fetch(FetchDescriptor<PersistedRide>())) ?? []
        for ride in rides where ride.rideId.hasPrefix(rideIdPrefix) {
            context.delete(ride)
        }
        try? context.save()
    }

    private static func sampleRides(referenceDate now: Date) -> [PersistedRide] {
        [
            makeRide(
                id: "commute-waterfront",
                start: now.addingTimeInterval(-2 * 60 * 60),
                durationMinutes: 42,
                distance: 18.6,
                startBattery: 96,
                endBattery: 79,
                maxSpeed: 63,
                avgSpeed: 31,
                uploaded: true,
                baseLatitude: 43.6407,
                baseLongitude: -79.3817,
                latitudeStep: 0.00042,
                longitudeStep: -0.00058,
                weather: DemoWeather(
                    temp: 21, feelsLike: 20, humidity: 58, wind: 14,
                    condition: "Partly Cloudy", symbol: "cloud.sun.fill", uv: 4, pressure: 1014
                ),
                heartRateBase: 118,
                activeCalories: 286
            ),
            makeRide(
                id: "park-loop",
                start: now.addingTimeInterval(-26 * 60 * 60),
                durationMinutes: 58,
                distance: 24.2,
                startBattery: 91,
                endBattery: 64,
                maxSpeed: 72,
                avgSpeed: 36,
                uploaded: true,
                baseLatitude: 43.6694,
                baseLongitude: -79.3926,
                latitudeStep: 0.00028,
                longitudeStep: 0.00046,
                weather: DemoWeather(
                    temp: 27, feelsLike: 29, humidity: 44, wind: 8,
                    condition: "Clear", symbol: "sun.max.fill", uv: 7, pressure: 1019
                ),
                heartRateBase: 126,
                activeCalories: 402
            ),
            makeRide(
                id: "rainy-errands",
                start: now.addingTimeInterval(-3 * 24 * 60 * 60),
                durationMinutes: 31,
                distance: 9.8,
                startBattery: 83,
                endBattery: 70,
                maxSpeed: 48,
                avgSpeed: 24,
                uploaded: false,
                baseLatitude: 43.6532,
                baseLongitude: -79.3832,
                latitudeStep: -0.00036,
                longitudeStep: 0.00031,
                weather: DemoWeather(
                    temp: 13, feelsLike: 10, humidity: 82, wind: 24,
                    condition: "Rain", symbol: "cloud.rain.fill", uv: 1, pressure: 1004
                ),
                heartRateBase: 104,
                activeCalories: 168
            ),
            makeRide(
                id: "night-cruise",
                start: now.addingTimeInterval(-6 * 24 * 60 * 60 - 3 * 60 * 60),
                durationMinutes: 49,
                distance: 16.4,
                startBattery: 88,
                endBattery: 66,
                maxSpeed: 68,
                avgSpeed: 29,
                uploaded: true,
                baseLatitude: 43.6450,
                baseLongitude: -79.4100,
                latitudeStep: 0.00022,
                longitudeStep: 0.00062,
                weather: DemoWeather(
                    temp: 18, feelsLike: 17, humidity: 63, wind: 11,
                    condition: "Cloudy", symbol: "cloud.fill", uv: 0, pressure: 1011
                ),
                heartRateBase: 112,
                activeCalories: 247
            )
        ]
    }

    private static func makeRide(
        id: String,
        start: Date,
        durationMinutes: Int,
        distance: Double,
        startBattery: Int,
        endBattery: Int,
        maxSpeed: Double,
        avgSpeed: Double,
        uploaded: Bool,
        baseLatitude: Double,
        baseLongitude: Double,
        latitudeStep: Double,
        longitudeStep: Double,
        weather: DemoWeather,
        heartRateBase: Int,
        activeCalories: Double
    ) -> PersistedRide {
        let ride = PersistedRide(rideId: rideIdPrefix + id, startTime: start, startBattery: startBattery)
        ride.endTime = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        ride.totalDistance = distance
        ride.maxSpeed = maxSpeed
        ride.avgSpeed = avgSpeed
        ride.batteryUsed = startBattery - endBattery
        ride.endBattery = endBattery
        ride.uploaded = uploaded
        ride.primaryGearMode = 3
        ride.samplesHydrated = true
        ride.weatherTemp = weather.temp
        ride.weatherFeelsLike = weather.feelsLike
        ride.weatherHumidity = weather.humidity
        ride.weatherWindSpeed = weather.wind
        ride.weatherWindDirection = 225
        ride.weatherCondition = weather.condition
        ride.weatherConditionSymbol = weather.symbol
        ride.weatherUVIndex = weather.uv
        ride.weatherPressure = weather.pressure
        ride.healthDataJSON = healthSummaryData(
            averageHeartRate: heartRateBase + 8,
            maxHeartRate: heartRateBase + 34,
            activeCalories: activeCalories
        )
        ride.samples = sampleSamples(
            start: start,
            count: max(24, durationMinutes),
            durationMinutes: durationMinutes,
            distance: distance,
            startBattery: startBattery,
            endBattery: endBattery,
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed,
            baseLatitude: baseLatitude,
            baseLongitude: baseLongitude,
            latitudeStep: latitudeStep,
            longitudeStep: longitudeStep,
            heartRateBase: heartRateBase
        )
        ride.photos = samplePhotos(for: ride, baseLatitude: baseLatitude, baseLongitude: baseLongitude)
        return ride
    }

    private static func sampleSamples(
        start: Date,
        count: Int,
        durationMinutes: Int,
        distance: Double,
        startBattery: Int,
        endBattery: Int,
        maxSpeed: Double,
        avgSpeed: Double,
        baseLatitude: Double,
        baseLongitude: Double,
        latitudeStep: Double,
        longitudeStep: Double,
        heartRateBase: Int
    ) -> [PersistedSample] {
        (0..<count).map { index in
            let progress = Double(index) / Double(max(count - 1, 1))
            let wave = sin(progress * .pi * 3)
            let sprint = max(0, sin(progress * .pi * 6))
            let speed = min(maxSpeed, max(0, avgSpeed * 0.55 + sprint * maxSpeed * 0.48 + wave * 4))
            let battery = Int((Double(startBattery) + (Double(endBattery - startBattery) * progress)).rounded())
            let sample = PersistedSample(
                timestamp: start.addingTimeInterval(progress * Double(durationMinutes * 60)),
                speed: speed,
                battery: battery
            )
            sample.bmsVoltage = 58.8 - progress * 5.2
            sample.bmsCurrent = 4.0 + sprint * 11.0
            sample.bmsSOC = battery
            sample.bmsTemp = 27.0 + progress * 9.0 + sprint * 2.5
            sample.tripDistance = distance * progress
            sample.bodyTemp = 24.0 + progress * 7.0
            sample.gearMode = progress < 0.08 ? 2 : 3
            sample.estimatedRange = max(8, Double(battery) * 0.62)
            sample.latitude = baseLatitude + latitudeStep * Double(index) + sin(progress * .pi * 2) * 0.0012
            sample.longitude = baseLongitude + longitudeStep * Double(index) + cos(progress * .pi * 2) * 0.0010
            sample.altitude = 76 + sin(progress * .pi * 4) * 8
            sample.gpsSpeed = speed
            sample.gpsCourse = 45 + progress * 120
            sample.horizontalAccuracy = 6 + (index % 5 == 0 ? 3 : 0)
            sample.roughnessScore = 0.18 + abs(wave) * 0.55
            sample.maxAcceleration = 0.2 + sprint * 1.6
            sample.heartRate = heartRateBase + Int((sprint * 30 + progress * 12).rounded())
            sample.tripTime = Int(progress * Double(durationMinutes * 60))
            sample.regenLevel = index % 3
            sample.speedResponse = Int(speed.rounded())
            return sample
        }
    }

    private static func samplePhotos(
        for ride: PersistedRide,
        baseLatitude: Double,
        baseLongitude: Double
    ) -> [PersistedRidePhoto] {
        let offsets = [(0.004, 0.003), (0.009, -0.002)]
        return offsets.enumerated().map { index, offset in
            let photo = PersistedRidePhoto(
                imageData: placeholderPNGData(index: index),
                mimeType: "image/png",
                createdAt: ride.startTime.addingTimeInterval(TimeInterval((index + 1) * 11 * 60)),
                latitude: baseLatitude + offset.0,
                longitude: baseLongitude + offset.1,
                ride: ride
            )
            photo.uploaded = ride.uploaded
            return photo
        }
    }

    private static func healthSummaryData(
        averageHeartRate: Int,
        maxHeartRate: Int,
        activeCalories: Double
    ) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "averageHeartRate": averageHeartRate,
            "maxHeartRate": maxHeartRate,
            "activeCalories": activeCalories
        ])
    }

    private static func placeholderPNGData(index: Int) -> Data {
        let swatches = [
            // 64×64 opaque teal and indigo placeholder images. These are
            // intentionally visible in Demo Mode so the photo strip doesn't
            // look like empty whitespace before real photos are attached.
            "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAZklEQVR42u3QQREAAAQAMAX0f+ukDzmcPVZgkdXzWQgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAH3LWRbElndQHwZAAAAAElFTkSuQmCC",
            "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAZUlEQVR42u3QQREAAAQAMCmd5OqQw9ljBRaVPZ+FAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQIECAAAECBAgQcN8CQOIyWa+UqCoAAAAASUVORK5CYII="
        ]
        return Data(base64Encoded: swatches[index % swatches.count]) ?? Data()
    }
}

private struct DemoWeather {
    let temp: Double
    let feelsLike: Double
    let humidity: Double
    let wind: Double
    let condition: String
    let symbol: String
    let uv: Double
    let pressure: Double
}
