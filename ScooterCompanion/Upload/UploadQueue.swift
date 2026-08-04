#if os(iOS)
import Foundation
import os
import SwiftData

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "UploadQueue")

/// Upload queue. Batches telemetry and flushes to server.
/// Failed batches are persisted to SwiftData for retry on next launch/connect.
actor UploadQueue {
    private let apiClient = GT3APIClient()
    private var pendingSamples: [TelemetrySample] = []
    private let batchSize = 50
    private var isFlushing = false

    /// Add telemetry samples to the pending batch.
    func enqueueSamples(_ samples: [TelemetrySample]) {
        pendingSamples.append(contentsOf: samples)
        if pendingSamples.count >= batchSize {
            Task { await flushSamples() }
        }
    }

    /// Flush pending telemetry samples to the server.
    func flushSamples() async {
        guard !isFlushing, !pendingSamples.isEmpty else { return }
        isFlushing = true
        let totalPending = pendingSamples.count
        debugLog("Flushing \(totalPending) pending samples", level: .info)

        while !pendingSamples.isEmpty {
            let batch = Array(pendingSamples.prefix(batchSize))
            pendingSamples.removeFirst(min(batch.count, pendingSamples.count))
            do {
                try await apiClient.uploadTelemetry(batch)
                logger.info("Flushed \(batch.count) samples")
                debugLog("Flushed \(batch.count) telemetry samples", level: .info)
            } catch {
                persistFailedBatch(batch)
                logger.error("Flush failed, persisted \(batch.count) samples for retry")
                debugLog("Flush failed (\(batch.count) samples): \(error.localizedDescription)", level: .error)
                break
            }
        }
        isFlushing = false
    }

    /// Persist any remaining in-memory samples to SwiftData (e.g. on ride end).
    func persistRemainingsamples() {
        guard !pendingSamples.isEmpty else { return }
        let count = pendingSamples.count
        persistFailedBatch(pendingSamples)
        logger.info("Persisted \(count) remaining samples")
        debugLog("Persisted \(count) remaining samples for retry", level: .warning)
        pendingSamples.removeAll()
    }

    /// Upload a completed ride. Returns the server-assigned ride ID if successful.
    func uploadRide(_ ride: RideLog) async -> String? {
        debugLog("Uploading ride \(ride.rideId) (\(ride.samples.count) samples)", level: .info)
        do {
            let serverId = try await apiClient.uploadRide(ride)
            debugLog("Ride uploaded — server ID: \(serverId ?? "nil")", level: .info)
            return serverId
        } catch {
            logger.error("Failed to upload ride: \(error)")
            debugLog("Ride upload failed: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    /// Upload a ride photo attachment.
    func uploadRidePhoto(rideId: String, payload: RidePhotoUploadPayload) async -> String? {
        do {
            return try await apiClient.uploadRidePhoto(rideId: rideId, payload: payload)
        } catch {
            logger.error("Failed to upload ride photo: \(error)")
            debugLog("Ride photo upload failed: \(error.localizedDescription)", level: .error)
            return nil
        }
    }

    func updateRideHealth(rideId: String, payload: RideHealthUpdatePayload) async {
        do {
            try await apiClient.updateRideHealth(rideId: rideId, payload: payload)
            debugLog("Ride health update uploaded", level: .info)
        } catch {
            logger.error("Failed to update ride health: \(error)")
            debugLog("Ride health update failed: \(error.localizedDescription)", level: .error)
            persistFailedRequest(payload: payload, endpoint: "PATCH /gt3/rides/\(rideId)/health")
        }
    }

    /// Upload a scooter snapshot.
    func uploadSnapshot(_ snapshot: [String: String]) async {
        do {
            try await apiClient.uploadSnapshot(snapshot)
            debugLog("Snapshot uploaded (\(snapshot.count) fields)", level: .info)
        } catch {
            logger.error("Failed to upload snapshot: \(error)")
            debugLog("Snapshot upload failed: \(error.localizedDescription)", level: .error)
        }
    }

    /// Retry a previously failed upload from persisted payload.
    func retryUpload(payload: Data, endpoint: String) async throws -> Data {
        debugLog("Retrying upload: \(endpoint) (\(payload.count) bytes)", level: .info)
        do {
            let data: Data
            if endpoint.hasPrefix("PATCH ") {
                data = try await apiClient.retryPatch(
                    path: String(endpoint.dropFirst("PATCH ".count)),
                    body: payload
                )
            } else {
                data = try await apiClient.retryPost(path: endpoint, body: payload)
            }
            debugLog("Retry succeeded: \(endpoint)", level: .info)
            return data
        } catch {
            debugLog("Retry failed: \(endpoint) — \(error.localizedDescription)", level: .error)
            throw error
        }
    }

    func getPendingCount() -> Int { pendingSamples.count }

    private func persistFailedBatch(_ samples: [TelemetrySample]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(["samples": samples]) else { return }
        persistFailedPayload(payload, endpoint: "/gt3/telemetry")
    }

    private func persistFailedRequest<T: Encodable>(payload: T, endpoint: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        persistFailedPayload(data, endpoint: endpoint)
    }

    private func persistFailedPayload(_ payload: Data, endpoint: String) {
        Task { @MainActor in
            let item = UploadQueueItem(payload: payload, endpoint: endpoint)
            PersistenceController.shared.context.insert(item)
            try? PersistenceController.shared.context.save()
        }
    }

    private func debugLog(_ message: String, level: LogEntry.Level) {
        Task { @MainActor in
            DebugLogStore.shared.log(message, category: "Upload", level: level)
        }
    }
}
#endif
