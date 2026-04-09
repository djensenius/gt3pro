#if os(iOS)
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "UploadQueue")

/// Upload queue. Batches telemetry and flushes to server.
/// Note: SwiftData persistence for true offline support will be wired in a future PR.
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
        let batch = Array(pendingSamples.prefix(batchSize))
        pendingSamples.removeFirst(min(batch.count, pendingSamples.count))

        do {
            try await apiClient.uploadTelemetry(batch)
            logger.info("Flushed \(batch.count) samples")
        } catch {
            pendingSamples.insert(contentsOf: batch, at: 0)
            logger.error("Flush failed, re-queued \(batch.count) samples: \(error)")
        }
        isFlushing = false
    }

    /// Upload a completed ride.
    func uploadRide(_ ride: RideLog) async {
        do {
            _ = try await apiClient.uploadRide(ride)
        } catch {
            logger.error("Failed to upload ride: \(error). Failed, data lost (persistence not yet implemented).")
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
