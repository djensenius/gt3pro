//
//  AppCoordinator+Rides.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import HealthKit
import os
import SwiftData

private let rideLogger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Rides")

// MARK: - Ride Completion & Upload Retry
// Internal access required — Swift disallows private in extensions across files.

extension AppCoordinator {
    func handleRideComplete(_ rideLog: RideLog) async {
        rideLogger.info("Ride complete: \(rideLog.totalDistance) km")
        let context = PersistenceController.shared.context
        let persisted = PersistedRide(
            rideId: rideLog.rideId,
            startTime: rideLog.startTime,
            startBattery: rideLog.startBattery
        )
        persisted.endTime = rideLog.endTime
        persisted.totalDistance = rideLog.totalDistance
        persisted.maxSpeed = rideLog.maxSpeed
        persisted.avgSpeed = rideLog.avgSpeed
        persisted.batteryUsed = rideLog.batteryUsed
        persisted.endBattery = rideLog.endBattery
        persisted.primaryGearMode = rideLog.primaryGearMode

        if let weather = rideLog.weather {
            persisted.weatherTemp = weather.temp
            persisted.weatherFeelsLike = weather.feelsLike
            persisted.weatherHumidity = weather.humidity
            persisted.weatherWindSpeed = weather.windSpeed
            persisted.weatherWindDirection = weather.windDirection
            persisted.weatherCondition = weather.condition
            persisted.weatherConditionSymbol = weather.conditionSymbol
            persisted.weatherUVIndex = weather.uvIndex
            persisted.weatherPressure = weather.pressure
        }

        context.insert(persisted)
        try? context.save()
        await uploadQueue.flushSamples()

        // Upload enriched snapshot with ride-end inferred values
        let rideDuration = rideLog.endTime.timeIntervalSince(rideLog.startTime)
        let snapshot = await registerReader.getEnrichedSnapshot(
            tripDistance: rideLog.totalDistance,
            rideDuration: rideDuration
        )
        if !snapshot.isEmpty {
            rideLogger.info("Uploading ride-end snapshot (\(snapshot.count) fields)")
            await uploadQueue.uploadSnapshot(snapshot)
        }

        if let serverId = await uploadQueue.uploadRide(rideLog) {
            persisted.rideId = serverId
            persisted.uploaded = true
            try? context.save()
        } else {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let payload = try? encoder.encode(rideLog) {
                let queueItem = UploadQueueItem(payload: payload, endpoint: "/gt3/ride")
                context.insert(queueItem)
                try? context.save()
                rideLogger.info("Queued ride \(rideLog.rideId) for retry")
            }
        }
    }

    func retryPendingUploads() async {
        let context = PersistenceController.shared.context
        guard let items = try? context.fetch(FetchDescriptor<UploadQueueItem>()),
              !items.isEmpty else { return }
        rideLogger.info("Found \(items.count) pending upload(s) to retry")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for item in items {
            do {
                let data = try await uploadQueue.retryUpload(
                    payload: item.payload, endpoint: item.endpoint
                )
                if item.endpoint == "/gt3/ride",
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let serverId = json["id"] as? String,
                   let ride = try? decoder.decode(RideLog.self, from: item.payload) {
                    let pred = #Predicate<PersistedRide> { $0.rideId == ride.rideId }
                    if let match = try? context.fetch(FetchDescriptor(predicate: pred)).first {
                        match.rideId = serverId
                        match.uploaded = true
                    }
                }
                context.delete(item)
                try? context.save()
                rideLogger.info("Retry succeeded: \(item.endpoint)")
            } catch {
                item.retryCount += 1
                item.lastAttempt = Date()
                try? context.save()
                rideLogger.warning("Retry \(item.endpoint) failed (#\(item.retryCount)): \(error)")
            }
        }
    }

    /// Auto-launch the Watch companion app to start a workout session.
    func launchWatchApp() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        HKHealthStore().startWatchApp(with: config) { success, error in
            if let error {
                rideLogger.warning("Watch app launch failed: \(error.localizedDescription)")
            } else if success {
                rideLogger.info("Watch app launched for workout")
            }
        }
    }
}
#endif
