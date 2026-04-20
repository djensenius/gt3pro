//
//  PhoneWatchSessionManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import WatchConnectivity
import os

private let logger = Logger(
    subsystem: "org.davidjensenius.GT3Companion",
    category: "WatchSession"
)

/// Manages WatchConnectivity from the iPhone side.
/// Sends telemetry to Watch, receives heart rate back.
@MainActor
class PhoneWatchSessionManager: NSObject, ObservableObject {
    static let shared = PhoneWatchSessionManager()

    @Published var latestHeartRate: Int = 0
    @Published var isWatchReachable: Bool = false

    private var wcSession: WCSession?

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            logger.info("WCSession not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    /// Send live telemetry to the Watch (interactive message — Watch must be reachable).
    func sendTelemetry(
        speed: Double,
        battery: Int,
        tripDistance: Double,
        range: Double,
        mode: Int
    ) {
        guard let session = wcSession,
              session.isReachable else { return }

        let message: [String: Any] = [
            "speed": speed,
            "battery": battery,
            "tripDistance": tripDistance,
            "estimatedRange": range,
            "gearMode": mode
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            logger.warning("Failed to send telemetry to Watch: \(error)")
        }
    }

    /// Send battery via application context (survives Watch app not running).
    func updateContext(battery: Int, isConnected: Bool, rideActive: Bool = false) {
        guard let session = wcSession,
              session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([
                "battery": battery,
                "isConnected": isConnected,
                "rideActive": rideActive
            ])
        } catch {
            logger.warning("Failed to update Watch context: \(error)")
        }
    }
}

extension PhoneWatchSessionManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            logger.error("WCSession activation error: \(error)")
        }
        logger.info("WCSession activated: \(activationState.rawValue)")
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        logger.info("WCSession became inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        logger.info("WCSession deactivated — reactivating")
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isWatchReachable = reachable
        }
        logger.info("Watch reachable: \(reachable)")
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard let heartRate = message["heartRate"] as? Int else { return }
        Task { @MainActor in
            self.latestHeartRate = heartRate
        }
    }
}
#endif
