#if os(iOS)
import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "LiveActivity")

/// Manages the GT3 ride Live Activity lifecycle.
@MainActor
class GT3LiveActivityManager {
    static let shared = GT3LiveActivityManager()

    private var currentActivity: Activity<GT3RideAttributes>?
    private var pushToStartTokenTask: Task<Void, Never>?
    private var lastRegisteredToken: String?

    private init() {}

    /// Start observing push-to-start token updates and register with server.
    func observePushToStartToken(apiClient: GT3APIClient) {
        guard pushToStartTokenTask == nil else { return }
        pushToStartTokenTask = Task.detached {
            for await tokenData in Activity<GT3RideAttributes>.pushToStartTokenUpdates {
                let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                logger.info("Received push-to-start token")

                let alreadyRegistered = await MainActor.run { self.lastRegisteredToken == tokenHex }
                if alreadyRegistered { continue }

                // Retry with back-off — token may arrive before auth is ready
                var registered = false
                for attempt in 0..<3 {
                    if attempt > 0 {
                        try? await Task.sleep(for: .seconds(Double(attempt) * 3))
                    }
                    do {
                        try await apiClient.registerPushToStartToken(tokenHex)
                        await MainActor.run { self.lastRegisteredToken = tokenHex }
                        registered = true
                        break
                    } catch {
                        logger.warning("Push-to-start token registration attempt \(attempt + 1) failed: \(error)")
                    }
                }
                if !registered {
                    logger.error("Failed to register push-to-start token after 3 attempts")
                }
            }
        }
    }

    /// Start a new Live Activity for a ride.
    func startRideActivity(scooterName: String = "GT3 Pro") async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities disabled")
            return
        }

        // Adopt any push-started activity instead of creating a new one
        adoptPushStartedActivityIfNeeded()
        if currentActivity?.activityState == .active {
            logger.info("Adopted existing Live Activity — skipping creation")
            return
        }

        // End stale/ended activities before creating a new one
        await endAllActivities()

        let attributes = GT3RideAttributes(scooterName: scooterName, startTime: Date())
        let initialState = GT3RideAttributes.ContentState.idle(isConnected: true)
        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(300))

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            logger.info("Started ride Live Activity")
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    /// Update the Live Activity with new telemetry.
    func updateActivity(state: GT3RideAttributes.ContentState) async {
        adoptPushStartedActivityIfNeeded()
        guard let activity = currentActivity,
              activity.activityState == .active else { return }

        let staleInterval: TimeInterval = state.isConnected ? 300 : 3600
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleInterval))
        nonisolated(unsafe) let sendableActivity = activity
        await sendableActivity.update(content)
    }

    /// End the current Live Activity.
    func endRideActivity() async {
        await endAllActivities()
    }

    /// End ALL Live Activities for this app, including orphans from prior launches.
    private func endAllActivities() async {
        for activity in Activity<GT3RideAttributes>.activities {
            nonisolated(unsafe) let sendableActivity = activity
            await sendableActivity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        logger.info("Ended all ride Live Activities")
    }

    /// Check if a Live Activity is currently active.
    var isActive: Bool {
        if currentActivity?.activityState == .active { return true }
        return Activity<GT3RideAttributes>.activities.contains { $0.activityState == .active }
    }

    /// Adopt a push-started activity so we can update it with telemetry.
    private func adoptPushStartedActivityIfNeeded() {
        guard currentActivity == nil || currentActivity?.activityState != .active else { return }
        currentActivity = Activity<GT3RideAttributes>.activities.first { $0.activityState == .active }
    }
}
#endif
