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
    }

    let scooterName: String
    let startTime: Date
}
#endif
