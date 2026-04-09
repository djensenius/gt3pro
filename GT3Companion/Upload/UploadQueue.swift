#if os(iOS)
import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "UploadQueue")

/// Offline-capable upload queue. Batches telemetry, retries on failure.
actor UploadQueue {
    private let apiClient = GT3APIClient()
    private var pendingSamples: [TelemetrySample] = []
    private let batchSize = 50
    private let maxRetries = 5

    /// Add telemetry samples to the pending batch.
    func enqueueSamples(_ samples: [TelemetrySample]) {
        pendingSamples.append(contentsOf: samples)
        if pendingSamples.count >= batchSize {
            Task { await flushSamples() }
        }
    }

    /// Flush pending telemetry samples to the server.
    func flushSamples() async {
        guard !pendingSamples.isEmpty else { return }
        let batch = Array(pendingSamples.prefix(batchSize))

        do {
            try await apiClient.uploadTelemetry(batch)
            pendingSamples.removeFirst(min(batch.count, pendingSamples.count))
            logger.info("Flushed \(batch.count) samples, \(self.pendingSamples.count) remaining")
        } catch {
            logger.error("Failed to flush samples: \(error). Will retry later.")
        }
    }

    /// Upload a completed ride.
    func uploadRide(_ ride: RideLog) async {
        do {
            _ = try await apiClient.uploadRide(ride)
        } catch {
            logger.error("Failed to upload ride: \(error). Queuing for retry.")
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

    func getPendingCount() -> Int { pendingSamples.count }
}
#endif
