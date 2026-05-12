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

struct WatchTelemetryContext {
    let battery: Int
    let isConnected: Bool
    let rideActive: Bool
    let speed: Double
    let tripDistance: Double
    let range: Double
    let mode: Int

    func hasKeyChange(from previous: WatchTelemetryContext?) -> Bool {
        guard let previous else { return true }
        return battery != previous.battery
            || isConnected != previous.isConnected
            || rideActive != previous.rideActive
            || mode != previous.mode
    }
}

/// Manages WatchConnectivity from the iPhone side.
/// Sends telemetry to Watch, receives heart rate back.
@MainActor
class PhoneWatchSessionManager: NSObject, ObservableObject {
    static let shared = PhoneWatchSessionManager()

    @Published var latestHeartRate: Int = 0
    @Published var isWatchReachable: Bool = false

    private var wcSession: WCSession?
    private var lastTelemetryContext: WatchTelemetryContext?
    private var lastTelemetryContextUpdate: Date?
    private let telemetryContextUpdateInterval: TimeInterval = 15

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
    func sendTelemetry(_ context: WatchTelemetryContext) {
        updateTelemetryContextIfNeeded(context)

        guard let session = wcSession,
              session.isReachable else { return }

        let message: [String: Any] = [
            "speed": context.speed,
            "battery": context.battery,
            "tripDistance": context.tripDistance,
            "estimatedRange": context.range,
            "gearMode": context.mode,
            "rideActive": context.rideActive
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            logger.warning("Failed to send telemetry to Watch: \(error)")
        }
    }

    private func updateTelemetryContextIfNeeded(_ context: WatchTelemetryContext) {
        let now = Date()
        let hasKeyChange = context.hasKeyChange(from: lastTelemetryContext)
        let shouldRefreshUnreachableContext = !(wcSession?.isReachable ?? false)
            && now.timeIntervalSince(lastTelemetryContextUpdate ?? .distantPast) >= telemetryContextUpdateInterval
        guard hasKeyChange || shouldRefreshUnreachableContext else { return }

        updateContext(
            battery: context.battery,
            isConnected: context.isConnected,
            rideActive: context.rideActive,
            speed: context.speed,
            tripDistance: context.tripDistance,
            range: context.range,
            mode: context.mode
        )
        lastTelemetryContext = context
        lastTelemetryContextUpdate = now
    }

    /// Send battery via application context (survives Watch app not running).
    func updateContext(
        battery: Int,
        isConnected: Bool,
        rideActive: Bool = false,
        speed: Double? = nil,
        tripDistance: Double? = nil,
        range: Double? = nil,
        mode: Int? = nil
    ) {
        guard let session = wcSession,
               session.activationState == .activated else { return }
        var context: [String: Any] = [
            "battery": battery,
            "isConnected": isConnected,
            "rideActive": rideActive
        ]
        if let speed {
            context["speed"] = speed
        }
        if let tripDistance {
            context["tripDistance"] = tripDistance
        }
        if let range {
            context["estimatedRange"] = range
        }
        if let mode {
            context["gearMode"] = mode
        }
        do {
            try session.updateApplicationContext(context)
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
