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

    @Published var speed: Double = 0
    @Published var battery: Int = 0
    @Published var tripDistance: Double = 0
    @Published var estimatedRange: Double = 0
    @Published var gearMode: Int = 0
    @Published var isRiding: Bool = false
    @Published var isConnected: Bool = false
    @Published var rideActive: Bool = false

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

    /// Send heart rate back to iPhone.
    func sendHeartRate(_ heartRate: Int) {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["heartRate": heartRate],
            replyHandler: nil,
            errorHandler: { error in
                Self.startupLogger.warning("Failed to send heart rate: \(error.localizedDescription, privacy: .public)")
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
    }

    static func logStartup(_ message: String) {
        startupLogger.info("\(message, privacy: .public)")
        forwardStartupLogToPhone(message)
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
