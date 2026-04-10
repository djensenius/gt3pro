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
    static var container: ModelContainer = {
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
        try? context.save()
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

        return [ride1, ride2, ride3]
    }

    // MARK: - Sample Route Coordinates

    #if os(iOS)
    static var sampleRouteCoordinates: [RouteCoordinate] {
        (0..<20).map { i in
            RouteCoordinate(
                latitude: 43.6532 + Double(i) * 0.001,
                longitude: -79.3832 + Double(i) * 0.0005,
                speed: Double.random(in: 20...60)
            )
        }
    }
    #endif

    // MARK: - Helpers

    private static func sampleSamples(start: Date, count: Int) -> [PersistedSample] {
        (0..<count).map { i in
            let sample = PersistedSample(
                timestamp: start.addingTimeInterval(Double(i) * 60),
                speed: Double.random(in: 15...70),
                battery: max(60, 95 - i)
            )
            sample.bms1Voltage = 58.8
            sample.bms1Current = Double.random(in: 5...25)
            sample.bms1SOC = max(60, 95 - i)
            sample.bms1Temp = Double.random(in: 30...45)
            sample.bms2Voltage = 58.6
            sample.bms2Current = Double.random(in: 5...25)
            sample.bms2SOC = max(58, 93 - i)
            sample.bms2Temp = Double.random(in: 28...42)
            sample.tripDistance = Double(i) * 0.4
            sample.bodyTemp = Double.random(in: 35...50)
            sample.gearMode = 3
            sample.estimatedRange = Double(max(20, 60 - i))
            sample.latitude = 43.6532 + Double(i) * 0.001
            sample.longitude = -79.3832 + Double(i) * 0.0005
            sample.altitude = 76.0 + Double.random(in: -5...5)
            sample.gpsSpeed = Double.random(in: 15...70)
            sample.roughnessScore = Double.random(in: 0.1...0.8)
            return sample
        }
    }
}
#endif
