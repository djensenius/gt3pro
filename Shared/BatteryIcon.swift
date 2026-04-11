//
//  BatteryIcon.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

/// Returns the appropriate SF Symbol name for a given battery percentage.
func batteryIconName(for percentage: Int) -> String {
    switch percentage {
    case ..<13:
        return "battery.0percent"
    case 13..<38:
        return "battery.25percent"
    case 38..<63:
        return "battery.50percent"
    case 63..<88:
        return "battery.75percent"
    default:
        return "battery.100percent"
    }
}
