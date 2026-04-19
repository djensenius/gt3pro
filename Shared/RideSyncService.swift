//
//  RideSyncService.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "RideSync")

/// Syncs ride history from the FluxHaus server into local SwiftData.
///
/// Runs on the main actor so it can safely use `ModelContext.mainContext`.
/// Skips rides already present locally (keyed on server ride ID).
/// Fetches all pages on each sync; local-only rides (uploaded = false) are never overwritten.
/// After syncing ride metadata, hydrates samples for rides missing telemetry data.
@MainActor
final class RideSyncService {
    static let shared = RideSyncService()

    private let baseURL = "https://api.fluxhaus.io"
    private var isSyncing = false

    /// Maximum rides to hydrate with samples per sync (new + backfill).
    private let maxHydrations = 10

    /// Fetch all rides from the server and upsert any that are missing locally.
    func syncRides() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let context = PersistenceController.shared.context

        // Phase 1: Sync ride metadata
        var newRideIds: [String] = []
        do {
            let existingIds = try existingRideIds(in: context)
            var page = 1
            var hasMore = true

            while hasMore {
                let serverRides = try await fetchPage(page: page)
                for serverRide in serverRides where !existingIds.contains(serverRide.id) {
                    insert(serverRide, into: context)
                    newRideIds.append(serverRide.id)
                }
                hasMore = serverRides.count == 20
                page += 1
            }

            if !newRideIds.isEmpty {
                try context.save()
                logger.info("Synced \(newRideIds.count) new ride(s) from server")
            }
        } catch {
            logger.error("Ride sync failed: \(error.localizedDescription)")
        }

        // Phase 2: Hydrate samples for rides that need them
        await hydrateSamples(newRideIds: newRideIds, context: context)
    }

    // MARK: - Sample Hydration

    /// Download and store samples for rides that are missing telemetry.
    /// Prioritizes newest rides, caps at `maxHydrations` per sync.
    private func hydrateSamples(newRideIds: [String], context: ModelContext) async {
        do {
            var toHydrate: [PersistedRide] = []

            // Prioritize newly synced rides that need hydration
            if !newRideIds.isEmpty {
                let allUnhydrated = try context.fetch(
                    FetchDescriptor<PersistedRide>(
                        predicate: #Predicate<PersistedRide> { ride in
                            ride.uploaded && ride.samplesHydrated != true
                        },
                        sortBy: [SortDescriptor(\.startTime, order: .reverse)]
                    )
                )
                let newSet = Set(newRideIds)
                let newRides = allUnhydrated.filter { newSet.contains($0.rideId) }
                let backfill = allUnhydrated.filter { !newSet.contains($0.rideId) }
                toHydrate = Array((newRides + backfill).prefix(maxHydrations))
            } else {
                var descriptor = FetchDescriptor<PersistedRide>(
                    predicate: #Predicate<PersistedRide> { ride in
                        ride.uploaded && ride.samplesHydrated != true
                    },
                    sortBy: [SortDescriptor(\.startTime, order: .reverse)]
                )
                descriptor.fetchLimit = maxHydrations
                toHydrate = try context.fetch(descriptor)
            }

            guard !toHydrate.isEmpty else { return }

            var hydratedCount = 0

            for ride in toHydrate {
                do {
                    let (samples, isAuthFailure) = try await fetchSamples(rideId: ride.rideId)
                    if isAuthFailure {
                        logger.warning("Skipping hydration for ride \(ride.rideId) due to auth failure")
                        continue
                    }
                    if !samples.isEmpty {
                        insertSamples(samples, for: ride)
                        hydratedCount += 1
                    }
                    ride.samplesHydrated = true
                    try context.save()
                } catch {
                    logger.warning(
                        "Failed to hydrate samples for ride \(ride.rideId): \(error.localizedDescription)"
                    )
                }
            }

            if hydratedCount > 0 {
                logger.info("Hydrated samples for \(hydratedCount) ride(s)")
            }
        } catch {
            logger.error("Sample hydration failed: \(error.localizedDescription)")
        }
    }

    /// Returns (samples, isAuthFailure). Auth failures return ([], true) so the caller can skip
    /// without marking the ride as hydrated.
    private func fetchSamples(rideId: String) async throws -> ([ServerSample], Bool) {
        guard let url = URL(string: "\(baseURL)/gt3/rides/\(rideId)/samples") else {
            throw URLError(.badURL)
        }
        _ = await AuthManager.shared.ensureValidToken()
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = AuthManager.shared.authorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                let refreshed = await AuthManager.shared.refreshTokenIfNeeded()
                if refreshed {
                    var retry = request
                    if let auth = AuthManager.shared.authorizationHeader() {
                        retry.setValue(auth, forHTTPHeaderField: "Authorization")
                    }
                    let (retryData, retryResp) = try await URLSession.shared.data(for: retry)
                    let retryStatus = (retryResp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200...299).contains(retryStatus) else {
                        return ([], true)
                    }
                    let decoded = try JSONDecoder().decode(ServerSamplesResponse.self, from: retryData)
                    return (decoded.samples, false)
                }
                logger.warning("Samples fetch for \(rideId): 401, token refresh failed")
                return ([], true)
            }
            guard (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }

        let decoded = try JSONDecoder().decode(ServerSamplesResponse.self, from: data)
        return (decoded.samples, false)
    }

    private func insertSamples(_ serverSamples: [ServerSample], for ride: PersistedRide) {
        var samples: [PersistedSample] = []
        for serverSample in serverSamples {
            let sample = PersistedSample(
                timestamp: serverSample.time, speed: serverSample.speed, battery: serverSample.battery
            )
            sample.bmsVoltage = serverSample.bmsVoltage ?? 0
            sample.bmsCurrent = serverSample.bmsCurrent ?? 0
            sample.bmsSOC = serverSample.bmsSoc ?? 0
            sample.bmsTemp = serverSample.bmsTemp ?? 0
            sample.bodyTemp = serverSample.bodyTemp ?? 0
            sample.gearMode = serverSample.gearMode ?? 0
            sample.tripDistance = serverSample.tripDistance ?? 0
            sample.tripTime = serverSample.tripTime ?? 0
            sample.estimatedRange = serverSample.rangeEstimate ?? 0
            sample.errorCode = serverSample.errorCode ?? 0
            sample.warnCode = serverSample.warnCode ?? 0
            sample.regenLevel = serverSample.regenLevel ?? 0
            sample.speedResponse = serverSample.speedResponse ?? 0
            sample.latitude = serverSample.latitude
            sample.longitude = serverSample.longitude
            sample.altitude = serverSample.altitude
            sample.gpsSpeed = serverSample.gpsSpeed
            sample.gpsCourse = serverSample.gpsCourse
            sample.horizontalAccuracy = serverSample.horizontalAccuracy
            sample.roughnessScore = serverSample.roughnessScore
            sample.maxAcceleration = serverSample.maxAcceleration
            sample.heartRate = serverSample.heartRate
            samples.append(sample)
        }
        ride.samples = samples
    }

    // MARK: - Private

    private func existingRideIds(in context: ModelContext) throws -> Set<String> {
        let rides = try context.fetch(FetchDescriptor<PersistedRide>())
        return Set(rides.map { $0.rideId })
    }

    private func fetchPage(page: Int) async throws -> [ServerRide] {
        guard let url = URL(string: "\(baseURL)/gt3/rides?page=\(page)&limit=20") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let auth = AuthManager.shared.authorizationHeader() {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                logger.warning("Rides sync received 401 — skipping, will retry after token refresh")
                return []
            }
            guard (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ServerRidesResponse.self, from: data).rides
    }

    private func insert(_ serverRide: ServerRide, into context: ModelContext) {
        let ride = PersistedRide(
            rideId: serverRide.id,
            startTime: serverRide.startTime,
            startBattery: serverRide.startBattery
        )
        ride.endTime = serverRide.endTime
        ride.totalDistance = serverRide.distance
        ride.maxSpeed = serverRide.maxSpeed
        ride.avgSpeed = serverRide.avgSpeed
        ride.batteryUsed = serverRide.batteryUsed
        ride.endBattery = serverRide.endBattery
        ride.uploaded = true
        ride.weatherTemp = serverRide.weatherTemp
        ride.weatherFeelsLike = serverRide.weatherFeelsLike
        ride.weatherHumidity = serverRide.weatherHumidity
        ride.weatherWindSpeed = serverRide.weatherWindSpeed
        ride.weatherWindDirection = serverRide.weatherWindDirection
        ride.weatherCondition = serverRide.weatherCondition
        ride.weatherUVIndex = serverRide.weatherUVIndex
        ride.weatherPressure = serverRide.weatherPressure
        if let condition = serverRide.weatherCondition {
            ride.weatherConditionSymbol = weatherSymbol(for: condition)
        }
        context.insert(ride)
    }
}
