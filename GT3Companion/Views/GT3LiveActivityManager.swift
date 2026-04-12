#if os(iOS)
import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "LiveActivity")

extension ActivityState {
    var debugDescription: String {
        switch self {
        case .active: return "active"
        case .ended: return "ended"
        case .dismissed: return "dismissed"
        case .stale: return "stale"
        case .pending: return "pending"
        @unknown default: return "unknown(\(self))"
        }
    }
}

/// Manages the GT3 ride Live Activity lifecycle.
@MainActor
class GT3LiveActivityManager {
    static let shared = GT3LiveActivityManager()

    private var currentActivity: Activity<GT3RideAttributes>?
    private var pushToStartTokenTask: Task<Void, Never>?
    private var lastRegisteredToken: String?
    private let debugLog = DebugLogStore.shared

    private init() {}

    private func laLog(_ message: String, level: LogEntry.Level = .info) {
        let osLevel: OSLogType
        switch level {
        case .debug: osLevel = .debug
        case .info: osLevel = .info
        case .warning: osLevel = .default
        case .error: osLevel = .error
        }
        logger.log(level: osLevel, "[LA] \(message)")
        debugLog.log(message, category: "LiveActivity", level: level)
    }

    /// Start observing push-to-start token updates and register with server.
    func observePushToStartToken(apiClient: GT3APIClient) {
        guard pushToStartTokenTask == nil else { return }
        pushToStartTokenTask = Task.detached { [weak self] in
            let weakManager = self
            for await tokenData in Activity<GT3RideAttributes>.pushToStartTokenUpdates {
                let tokenHex = tokenData.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    DebugLogStore.shared.log("Received push-to-start token", category: "LiveActivity")
                }

                let alreadyRegistered = await MainActor.run {
                    weakManager?.lastRegisteredToken == tokenHex
                }
                if alreadyRegistered { continue }

                var registered = false
                for attempt in 0..<3 {
                    if attempt > 0 {
                        do {
                            try await Task.sleep(for: .seconds(Double(attempt) * 3))
                        } catch is CancellationError {
                            return
                        } catch {
                            continue
                        }
                    }
                    do {
                        try await apiClient.registerPushToStartToken(tokenHex)
                        await MainActor.run {
                            weakManager?.lastRegisteredToken = tokenHex
                        }
                        await MainActor.run {
                            DebugLogStore.shared.log(
                                "Registered push-to-start token", category: "LiveActivity"
                            )
                        }
                        registered = true
                        break
                    } catch {
                        await MainActor.run {
                            DebugLogStore.shared.log(
                                "Token registration attempt \(attempt + 1) failed: \(error)",
                                category: "LiveActivity", level: .warning
                            )
                        }
                    }
                }
                if !registered {
                    await MainActor.run {
                        DebugLogStore.shared.log(
                            "Failed to register push-to-start token after 3 attempts",
                            category: "LiveActivity", level: .error
                        )
                    }
                }
            }
        }
    }

    /// Start a new Live Activity for a ride.
    func startRideActivity(scooterName: String = "GT3 Pro") async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            laLog("Live Activities disabled by user", level: .warning)
            return
        }

        laLog("startRideActivity called — checking for existing activities")
        let allActivities = Activity<GT3RideAttributes>.activities
        let summary = allActivities.map {
            "\($0.id)=\($0.activityState.debugDescription)"
        }.joined(separator: ", ")
        laLog("Found \(allActivities.count) activity instance(s): \(summary)")

        adoptPushStartedActivityIfNeeded()
        if currentActivity?.activityState == .active {
            laLog("Adopted existing active Live Activity \(self.currentActivity?.id ?? "?")")
            return
        }

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
            laLog("Created new Live Activity: \(self.currentActivity?.id ?? "?")")
        } catch {
            laLog("Failed to create Live Activity: \(error)", level: .error)
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
        let activities = Activity<GT3RideAttributes>.activities
        laLog("endAllActivities — ending \(activities.count) activity instance(s)")
        for activity in activities {
            laLog("Ending activity \(activity.id) state=\(activity.activityState.debugDescription)")
            nonisolated(unsafe) let sendableActivity = activity
            await sendableActivity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
    }

    var isActive: Bool {
        if currentActivity?.activityState == .active { return true }
        let anyActive = Activity<GT3RideAttributes>.activities.contains { $0.activityState == .active }
        return anyActive
    }

    private func adoptPushStartedActivityIfNeeded() {
        guard currentActivity == nil || currentActivity?.activityState != .active else { return }
        let allActive = Activity<GT3RideAttributes>.activities.filter { $0.activityState == .active }
        if let candidate = allActive.first {
            laLog("Adopting activity: \(candidate.id)")
            currentActivity = candidate
            // End any extra active activities to avoid duplicates
            for extra in allActive.dropFirst() {
                laLog("Ending duplicate activity: \(extra.id)")
                nonisolated(unsafe) let sendable = extra
                Task { await sendable.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
}
#endif
