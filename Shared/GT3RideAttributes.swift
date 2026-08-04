//
//  GT3RideAttributes.swift
//  ScooterCompanion
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

        /// Custom decoding with backward compatibility for `isConnected`.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speed = try container.decode(Double.self, forKey: .speed)
            battery = try container.decode(Int.self, forKey: .battery)
            tripDistance = try container.decode(Double.self, forKey: .tripDistance)
            estimatedRange = try container.decode(Double.self, forKey: .estimatedRange)
            gearMode = try container.decode(Int.self, forKey: .gearMode)
            bmsTemp = try container.decode(Double.self, forKey: .bmsTemp)
            isCharging = try container.decode(Bool.self, forKey: .isCharging)
            isAwake = try container.decode(Bool.self, forKey: .isAwake)
            isConnected = try container.decodeIfPresent(Bool.self, forKey: .isConnected) ?? true
        }

        init(
            speed: Double, battery: Int, tripDistance: Double,
            estimatedRange: Double, gearMode: Int, bmsTemp: Double,
            isCharging: Bool, isAwake: Bool, isConnected: Bool
        ) {
            self.speed = speed
            self.battery = battery
            self.tripDistance = tripDistance
            self.estimatedRange = estimatedRange
            self.gearMode = gearMode
            self.bmsTemp = bmsTemp
            self.isCharging = isCharging
            self.isAwake = isAwake
            self.isConnected = isConnected
        }

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
