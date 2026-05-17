#if os(iOS)
import Foundation
import SwiftData
import os

private let healthLogger = Logger(
    subsystem: "org.davidjensenius.GT3Companion",
    category: "Health"
)

extension AppCoordinator {
    func backfillPersistedHealthData(
        heartRateSamples: [WatchHeartRateSample],
        activeCalories: Double?,
        activeCaloriesDate: Date?
    ) {
        guard !heartRateSamples.isEmpty || activeCalories != nil else { return }
        let context = PersistenceController.shared.context
        let descriptor = FetchDescriptor<PersistedRide>(
            predicate: #Predicate { $0.endTime != nil }
        )
        let rides = (try? context.fetch(descriptor)) ?? []
        var pendingUploads: [(rideId: String, payload: RideHealthUpdatePayload)] = []
        var hasChanges = false

        for ride in rides {
            let caloriesForRide = activeCaloriesForRide(
                ride,
                activeCalories: activeCalories,
                activeCaloriesDate: activeCaloriesDate,
                heartRateSamples: heartRateSamples
            )
            let updates = applyHealthData(
                heartRateSamples: heartRateSamples,
                activeCalories: caloriesForRide,
                to: ride
            )
            guard !updates.isEmpty || caloriesForRide != nil else { continue }
            hasChanges = true

            if ride.uploaded {
                pendingUploads.append((
                    rideId: ride.rideId,
                    payload: RideHealthUpdatePayload(
                        healthData: decodeRideHealthData(from: ride.healthDataJSON),
                        heartRateSamples: updates
                    )
                ))
            }
        }

        guard hasChanges else { return }
        do {
            try context.save()
        } catch {
            healthLogger.error("Failed saving ride health data: \(error.localizedDescription)")
            return
        }

        for upload in pendingUploads {
            Task {
                await uploadQueue.updateRideHealth(rideId: upload.rideId, payload: upload.payload)
            }
        }
    }

    func uploadPersistedRideHealth(_ ride: PersistedRide) async {
        let heartRateSamples: [RideHealthUpdatePayload.HeartRateSample] = (ride.samples ?? []).compactMap { sample in
            guard let heartRate = sample.heartRate, heartRate > 0 else { return nil }
            return RideHealthUpdatePayload.HeartRateSample(
                timestamp: sample.timestamp,
                heartRate: heartRate
            )
        }
        let healthData = decodeRideHealthData(from: ride.healthDataJSON)
        guard healthData != nil || !heartRateSamples.isEmpty else { return }
        let payload = RideHealthUpdatePayload(
            healthData: healthData,
            heartRateSamples: heartRateSamples
        )
        await uploadQueue.updateRideHealth(rideId: ride.rideId, payload: payload)
    }

    private func applyHealthData(
        heartRateSamples: [WatchHeartRateSample],
        activeCalories: Double?,
        to ride: PersistedRide
    ) -> [RideHealthUpdatePayload.HeartRateSample] {
        let samples = ride.samples ?? []
        guard !samples.isEmpty else { return [] }

        var updates: [RideHealthUpdatePayload.HeartRateSample] = []
        for sample in samples where sample.heartRate == nil {
            guard let bpm = heartRate(for: sample.timestamp, from: heartRateSamples) else { continue }
            sample.heartRate = bpm
            updates.append(.init(timestamp: sample.timestamp, heartRate: bpm))
        }

        let healthData = buildRideHealthData(for: ride, activeCalories: activeCalories)
        if let healthData {
            ride.healthDataJSON = try? JSONEncoder().encode(healthData)
        }
        return updates
    }

    private func buildRideHealthData(for ride: PersistedRide, activeCalories: Double?) -> RideHealthData? {
        let heartRates = (ride.samples ?? []).compactMap(\.heartRate).filter { $0 > 0 }
        let averageHeartRate = heartRates.isEmpty
            ? nil
            : Int((Double(heartRates.reduce(0, +)) / Double(heartRates.count)).rounded())
        let maxHeartRate = heartRates.max()
        let existingCalories = decodeRideHealthData(from: ride.healthDataJSON)?.activeCalories
        let calories = activeCalories ?? existingCalories
        guard averageHeartRate != nil || maxHeartRate != nil || calories != nil else { return nil }
        return RideHealthData(
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeCalories: calories
        )
    }

    private func activeCaloriesForRide(
        _ ride: PersistedRide,
        activeCalories: Double?,
        activeCaloriesDate: Date?,
        heartRateSamples: [WatchHeartRateSample]
    ) -> Double? {
        guard let activeCalories,
              let endTime = ride.endTime else { return nil }
        let start = ride.startTime.addingTimeInterval(-15)
        let end = endTime.addingTimeInterval(15)
        if let activeCaloriesDate {
            return activeCaloriesDate >= start && activeCaloriesDate <= end ? activeCalories : nil
        }
        let hasMatchingHeartRate = heartRateSamples.contains {
            $0.timestamp >= start && $0.timestamp <= end
        }
        return hasMatchingHeartRate ? activeCalories : nil
    }

    private func decodeRideHealthData(from data: Data?) -> RideHealthData? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(RideHealthData.self, from: data)
    }

    private func heartRate(for timestamp: Date, from heartRateSamples: [WatchHeartRateSample]) -> Int? {
        let maxAge: TimeInterval = 15
        let minTimestamp = timestamp.addingTimeInterval(-maxAge)
        return heartRateSamples
            .filter { $0.timestamp <= timestamp && $0.timestamp >= minTimestamp }
            .max { $0.timestamp < $1.timestamp }?
            .bpm
    }
}
#endif
