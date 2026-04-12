//
//  GT3RideAttributes.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

#if os(iOS)
import ActivityKit

struct GT3RideAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let speed: Double
        let battery: Int
        let tripDistance: Double
        let estimatedRange: Double
        let gearMode: Int
        let bmsTemp: Double
        let isCharging: Bool
        /// Whether the scooter VCU is powered on (battery > 0).
        let isAwake: Bool
        /// Whether BLE is currently connected to the scooter.
        let isConnected: Bool

        /// Idle state used for standby and disconnected updates.
        static func idle(isConnected: Bool) -> Self {
            .init(
                speed: 0, battery: 0, tripDistance: 0, estimatedRange: 0,
                gearMode: 0, bmsTemp: 0, isCharging: false,
                isAwake: false, isConnected: isConnected
            )
        }
    }

    let scooterName: String
    let startTime: Date
}
#endif
