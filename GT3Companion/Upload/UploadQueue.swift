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

        while !pendingSamples.isEmpty {
            let batch = Array(pendingSamples.prefix(batchSize))
            pendingSamples.removeFirst(min(batch.count, pendingSamples.count))
            do {
                try await apiClient.uploadTelemetry(batch)
                logger.info("Flushed \(batch.count) samples")
            } catch {
                persistFailedBatch(batch)
                logger.error("Flush failed, persisted \(batch.count) samples for retry")
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
        pendingSamples.removeAll()
    }

    /// Upload a completed ride. Returns the server-assigned ride ID if successful.
    func uploadRide(_ ride: RideLog) async -> String? {
        do {
            return try await apiClient.uploadRide(ride)
        } catch {
            logger.error("Failed to upload ride: \(error)")
            return nil
        }
    }

    /// Upload a scooter snapshot.
    func uploadSnapshot(_ snapshot: [String: String]) async {
        do {
            try await apiClient.uploadSnapshot(snapshot)
        } catch {
            logger.error("Failed to upload snapshot: \(error)")
        }
    }

    /// Retry a previously failed upload from persisted payload.
    func retryUpload(payload: Data, endpoint: String) async throws -> Data {
        try await apiClient.retryPost(path: endpoint, body: payload)
    }

    func getPendingCount() -> Int { pendingSamples.count }

    private func persistFailedBatch(_ samples: [TelemetrySample]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(["samples": samples]) else { return }
        Task { @MainActor in
            let item = UploadQueueItem(payload: payload, endpoint: "/gt3/telemetry")
            PersistenceController.shared.context.insert(item)
            try? PersistenceController.shared.context.save()
        }
    }
}
#endif
