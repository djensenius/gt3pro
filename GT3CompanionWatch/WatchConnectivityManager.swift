//
//  WatchConnectivityManager.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    @Published var speed: Double = 0
    @Published var battery: Int = 0
    @Published var tripDistance: Double = 0
    @Published var isRiding: Bool = false
    @Published var heartRate: Int = 0

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) { }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            self.speed = message["speed"] as? Double ?? 0
            self.battery = message["battery"] as? Int ?? 0
            self.tripDistance = message["tripDistance"] as? Double ?? 0
            self.isRiding = message["isRiding"] as? Bool ?? false
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.battery = applicationContext["battery"] as? Int ?? self.battery
        }
    }
}
