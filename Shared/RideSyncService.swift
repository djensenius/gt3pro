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
@MainActor
final class RideSyncService {
    static let shared = RideSyncService()

    private let baseURL = "https://api.fluxhaus.io"
    private var isSyncing = false

    /// Fetch all rides from the server and upsert any that are missing locally.
    func syncRides() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let context = PersistenceController.shared.context

        do {
            let existingIds = try existingRideIds(in: context)
            var newCount = 0
            var page = 1
            var hasMore = true

            while hasMore {
                let serverRides = try await fetchPage(page: page)
                for serverRide in serverRides where !existingIds.contains(serverRide.id) {
                    insert(serverRide, into: context)
                    newCount += 1
                }
                hasMore = serverRides.count == 20
                page += 1
            }

            if newCount > 0 {
                try context.save()
                logger.info("Synced \(newCount) new ride(s) from server")
            }
        } catch {
            logger.error("Ride sync failed: \(error.localizedDescription)")
        }
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
