//
//  PreviewHelpers.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if DEBUG
import SwiftData
import SwiftUI

/// Shared mock data and helpers for SwiftUI previews.
@MainActor
enum PreviewData {
    /// An in-memory model container pre-populated with sample rides.
    static let container: ModelContainer = {
        let schema = Schema([
            PersistedRide.self,
            PersistedSample.self,
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
