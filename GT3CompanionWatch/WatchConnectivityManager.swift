//
//  WatchConnectivityManager.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import Foundation
import WatchConnectivity
import os

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private static let startupLogger = Logger(
        subsystem: "org.davidjensenius.GT3Companion",
        category: "WatchStartup"
    )
    private static let pendingStartupLogsLock = NSLock()
    private static var pendingStartupLogs: [String] = []
    private static let healthFlushInterval: TimeInterval = 10
    private static let maxHeartRateBatchSize = 20

    @Published var speed: Double = 0
    @Published var battery: Int = 0
    @Published var tripDistance: Double = 0
    @Published var estimatedRange: Double = 0
    @Published var gearMode: Int = 0
    @Published var isRiding: Bool = false
    @Published var isConnected: Bool = false
    @Published var rideActive: Bool = false
    @Published var hasRideState: Bool = false
    private var pendingHeartRateSamples: [[String: Any]] = []
    private var latestActiveCalories: Double?
    private var lastHealthFlush = Date.distantPast

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
                Self.startupLogger.warning("Failed to send heart rate: \(error.localizedDescription, privacy: .public)")
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
            self.speed = message["speed"] as? Double ?? self.speed
            self.battery = message["battery"] as? Int ?? self.battery
            self.tripDistance = message["tripDistance"] as? Double ?? self.tripDistance
            self.estimatedRange = message["estimatedRange"] as? Double ?? self.estimatedRange
            self.gearMode = message["gearMode"] as? Int ?? self.gearMode
            self.rideActive = message["rideActive"] as? Bool ?? self.rideActive
            if message["rideActive"] != nil {
                self.hasRideState = true
            }
            self.isConnected = true
            self.clearSpeedWhenRideInactive()
            self.isRiding = self.isMovingDuringActiveRide
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.battery = applicationContext["battery"] as? Int ?? self.battery
            self.isConnected = applicationContext["isConnected"] as? Bool ?? self.isConnected
            self.rideActive = applicationContext["rideActive"] as? Bool ?? self.rideActive
            if applicationContext["rideActive"] != nil {
                self.hasRideState = true
            }
            self.speed = applicationContext["speed"] as? Double ?? self.speed
            self.tripDistance = applicationContext["tripDistance"] as? Double ?? self.tripDistance
            self.estimatedRange = applicationContext["estimatedRange"] as? Double ?? self.estimatedRange
            self.gearMode = applicationContext["gearMode"] as? Int ?? self.gearMode
            self.clearSpeedWhenRideInactive()
            self.isRiding = self.isMovingDuringActiveRide
        }
    }

    private var isMovingDuringActiveRide: Bool {
        rideActive && speed > 0
    }

    private func clearSpeedWhenRideInactive() {
        if !rideActive {
            speed = 0
        }
    }
}
