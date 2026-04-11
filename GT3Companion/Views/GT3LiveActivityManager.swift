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

    private init() {}

    /// Start a new Live Activity for a ride.
    func startRideActivity(scooterName: String = "GT3 Pro") async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.warning("Live Activities disabled")
            return
        }

        // End ALL existing activities (including orphans from prior launches)
        await endAllActivities()

        let attributes = GT3RideAttributes(scooterName: scooterName, startTime: Date())
        let initialState = GT3RideAttributes.ContentState(
            speed: 0,
            battery: 0,
            tripDistance: 0,
            estimatedRange: 0,
            gearMode: 0,
            bmsTemp: 0,
            isCharging: false,
            isAwake: false
        )

        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(300))

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            logger.info("Started ride Live Activity")
        } catch {
            logger.error("Failed to start Live Activity: \(error)")
        }
    }

    /// Update the Live Activity with new telemetry.
    func updateActivity(state: GT3RideAttributes.ContentState) async {
        guard let activity = currentActivity,
              activity.activityState == .active else { return }

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
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
            await sendableActivity.end(nil, dismissalPolicy: .default)
        }
        currentActivity = nil
        logger.info("Ended all ride Live Activities")
    }

    /// Check if a Live Activity is currently active.
    var isActive: Bool {
        currentActivity?.activityState == .active
    }
}
#endif
