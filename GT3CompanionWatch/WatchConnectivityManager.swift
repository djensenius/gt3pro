//
//  WatchConnectivityManager.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import Foundation
import Observation
import WatchConnectivity
import os

@Observable
class WatchConnectivityManager: NSObject, WCSessionDelegate {
    nonisolated(unsafe) static let shared = WatchConnectivityManager()
    private static let startupLogger = Logger(
        subsystem: "org.davidjensenius.GT3Companion",
        category: "WatchStartup"
    )
    private static let pendingStartupLogsLock = NSLock()
    nonisolated(unsafe) private static var pendingStartupLogs: [String] = []
    private static let healthFlushInterval: TimeInterval = 10
    private static let maxHeartRateBatchSize = 20

    var speed: Double = 0
    var battery: Int = 0
    var tripDistance: Double = 0
    var estimatedRange: Double = 0
    var gearMode: Int = 0
    var isRiding: Bool = false
    var isConnected: Bool = false
    var rideActive: Bool = false
    var hasRideState: Bool = false
    var shouldRecordWorkout: Bool = false {
        didSet {
            guard oldValue != shouldRecordWorkout else { return }
            onShouldRecordWorkoutChanged?(shouldRecordWorkout)
        }
    }
    @ObservationIgnored
    var onShouldRecordWorkoutChanged: ((Bool) -> Void)?
    @ObservationIgnored
    private var pendingHeartRateSamples: [[String: Any]] = []
    @ObservationIgnored
    private var latestActiveCalories: Double?
    @ObservationIgnored
    private var lastHealthFlush = Date.distantPast
    @ObservationIgnored
    private var autoWorkoutStartedAt: Date?
    @ObservationIgnored
    private var receivedActiveRideStateAfterAutoStart = false
    @ObservationIgnored
    private var activeRideSessionId: String?

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            Self.logStartup("WCSession activation requested")
        } else {
            Self.logStartup("WCSession not supported on this device")
        }
    }

    func enqueueHeartRateSample(bpm: Int, timestamp: Date, activeCalories: Double?) {
        guard bpm > 0 else { return }
        pendingHeartRateSamples.append([
            "bpm": bpm,
            "timestamp": timestamp.timeIntervalSince1970
        ])
        updateActiveCalories(activeCalories)
        if pendingHeartRateSamples.count >= Self.maxHeartRateBatchSize
            || Date().timeIntervalSince(lastHealthFlush) >= Self.healthFlushInterval {
            flushHealthData()
        }
    }

    func updateActiveCalories(_ activeCalories: Double?) {
        guard let activeCalories, activeCalories >= 0 else { return }
        latestActiveCalories = activeCalories
    }

    func markAutoWorkoutStarted() {
        DispatchQueue.main.async {
            self.autoWorkoutStartedAt = Date()
            self.receivedActiveRideStateAfterAutoStart = false
            self.rideActive = true
            self.hasRideState = true
            self.shouldRecordWorkout = true
            self.isConnected = true
            Self.logStartup("Auto workout start marked ride active")
        }
    }

    func flushHealthData() {
        guard !pendingHeartRateSamples.isEmpty || latestActiveCalories != nil else { return }
        var payload: [String: Any] = [
            "heartRateSamples": pendingHeartRateSamples,
            "healthDataDate": Date().timeIntervalSince1970
        ]
        if let latestActiveCalories {
            payload["activeCalories"] = latestActiveCalories
        }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        pendingHeartRateSamples.removeAll()
        lastHealthFlush = Date()

        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }

        session.sendMessage(
            payload,
            replyHandler: nil,
            errorHandler: { error in
                Self.startupLogger.warning(
                    "Failed to send health data: \(error.localizedDescription, privacy: .public)"
                )
                session.transferUserInfo(payload)
            }
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            Self.logStartup("WCSession activation failed: \(error.localizedDescription)")
        } else {
            Self.logStartup("WCSession activated with state: \(activationState.rawValue)")
        }
        if activationState == .activated {
            Self.flushPendingStartupLogs()
        }
    }

    static func logStartup(_ message: String) {
        startupLogger.info("\(message, privacy: .public)")
        if canForwardStartupLogsNow {
            forwardStartupLogToPhone(message)
        } else {
            enqueuePendingStartupLog(message)
        }
    }

    private static var canForwardStartupLogsNow: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.activationState == .activated
    }

    private static func enqueuePendingStartupLog(_ message: String) {
        pendingStartupLogsLock.lock()
        pendingStartupLogs.append(message)
        pendingStartupLogsLock.unlock()
    }

    private static func takePendingStartupLogs() -> [String] {
        pendingStartupLogsLock.lock()
        let logs = pendingStartupLogs
        pendingStartupLogs.removeAll()
        pendingStartupLogsLock.unlock()
        return logs
    }

    private static func flushPendingStartupLogs() {
        let logs = takePendingStartupLogs()
        guard !logs.isEmpty else { return }
        logs.forEach { forwardStartupLogToPhone($0) }
    }

    private static func forwardStartupLogToPhone(_ message: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(
                ["watchLog": message],
                replyHandler: nil,
                errorHandler: { error in
                    startupLogger.warning("Failed to forward watch log: \(error.localizedDescription, privacy: .public)")
                }
            )
        } else {
            _ = session.transferUserInfo([
                "watchLog": message,
                "watchLogDate": Date().timeIntervalSince1970
            ])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.applyWatchPayload(message)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            self.applyWatchPayload(userInfo)
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.applyWatchPayload(applicationContext)
        }
    }

    private var isMovingDuringActiveRide: Bool {
        rideActive && speed > 0
    }

    private func applyWatchPayload(_ payload: [String: Any]) {
        battery = payload["battery"] as? Int ?? battery
        isConnected = payload["isConnected"] as? Bool ?? isConnected
        speed = payload["speed"] as? Double ?? speed
        tripDistance = payload["tripDistance"] as? Double ?? tripDistance
        estimatedRange = payload["estimatedRange"] as? Double ?? estimatedRange
        gearMode = payload["gearMode"] as? Int ?? gearMode

        if let event = payload["rideEvent"] as? String,
           let rideSessionId = payload["rideSessionId"] as? String {
            applyRideEvent(event, rideSessionId: rideSessionId)
        } else if let rideActive = payload["rideActive"] as? Bool,
                  shouldApplyRideActive(rideActive, timestamp: payload.contextDate) {
            applyRideActive(rideActive, rideSessionId: payload["rideSessionId"] as? String)
        }

        clearSpeedWhenRideInactive()
        isRiding = isMovingDuringActiveRide
    }

    private func applyRideEvent(_ event: String, rideSessionId: String) {
        switch event {
        case "start":
            activeRideSessionId = rideSessionId
            shouldRecordWorkout = true
            applyRideActive(true, rideSessionId: rideSessionId)
            Self.logStartup("Applied ride start event: \(rideSessionId)")
        case "end":
            if let activeRideSessionId {
                guard activeRideSessionId == rideSessionId else {
                    Self.logStartup("Ignored ride end for non-active ride: \(rideSessionId)")
                    return
                }
            } else if shouldRecordWorkout {
                Self.logStartup("Ignored ride end before active ride ID was established: \(rideSessionId)")
                return
            }
            activeRideSessionId = nil
            shouldRecordWorkout = false
            applyRideActive(false, rideSessionId: rideSessionId)
            Self.logStartup("Applied ride end event: \(rideSessionId)")
        default:
            break
        }
    }

    private func applyRideActive(_ newValue: Bool, rideSessionId: String?) {
        if newValue {
            receivedActiveRideStateAfterAutoStart = true
            activeRideSessionId = rideSessionId ?? activeRideSessionId
        } else {
            autoWorkoutStartedAt = nil
            receivedActiveRideStateAfterAutoStart = false
        }
        rideActive = newValue
        hasRideState = true
    }

    private func shouldApplyRideActive(_ newValue: Bool, timestamp: Date?) -> Bool {
        if !newValue && shouldRecordWorkout {
            Self.logStartup("Ignored inactive ride state while workout awaits explicit end event")
            return false
        }
        guard !newValue,
              let autoWorkoutStartedAt,
              !receivedActiveRideStateAfterAutoStart else { return true }

        if let timestamp {
            let predatesAutoStart = timestamp < autoWorkoutStartedAt.addingTimeInterval(-2)
            if predatesAutoStart {
                Self.logStartup("Ignored stale inactive ride state after auto workout start")
                return false
            }
        } else if Date().timeIntervalSince(autoWorkoutStartedAt) < 30 {
            Self.logStartup("Ignored undated inactive ride state after auto workout start")
            return false
        }
        return true
    }

    private func clearSpeedWhenRideInactive() {
        if !rideActive {
            speed = 0
        }
    }
}

private extension Dictionary where Key == String, Value == Any {
    var contextDate: Date? {
        (self["contextDate"] as? Double).map(Date.init(timeIntervalSince1970:))
    }
}
