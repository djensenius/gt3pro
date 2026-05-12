//
//  GeoUtils.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftUI

/// Earth's mean radius in kilometres.
public let earthRadiusKm = 6371.0

/// Minimum horizontal accuracy (metres) for a GPS fix to be considered valid.
public let gpsAccuracyThresholdMetres = 50.0

/// Haversine great-circle distance between two coordinates in kilometres.
public func haversineDistanceKm(
    lat1: Double, lon1: Double,
    lat2: Double, lon2: Double
) -> Double {
    let dLat = (lat2 - lat1) * .pi / 180
    let dLon = (lon2 - lon1) * .pi / 180
    let aVal = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
        * sin(dLon / 2) * sin(dLon / 2)
    return earthRadiusKm * 2 * atan2(sqrt(aVal), sqrt(1 - aVal))
}

struct RouteCoordinate: Hashable {
    let latitude: Double
    let longitude: Double
    let speed: Double
}

struct RouteSpeedSegment: Identifiable {
    let id: Int
    let coordinates: [RouteCoordinate]
    let speed: Double
}

func routeColorBucket(speed: Double, maxSpeed: Double) -> Int {
    guard maxSpeed > 0 else { return 0 }
    return min(Int(speed / maxSpeed * 10), 10)
}

func routeSpeedSegments(for coordinates: [RouteCoordinate]) -> [RouteSpeedSegment] {
    guard coordinates.count >= 2 else { return [] }
    let max = coordinates.map(\.speed).max() ?? 1
    var result: [RouteSpeedSegment] = []
    var currentCoordinates: [RouteCoordinate] = []
    var currentBucket = -1
    var currentSpeed = 0.0
    var segmentId = 0

    for coordinate in coordinates {
        let bucket = routeColorBucket(speed: coordinate.speed, maxSpeed: max)
        if bucket != currentBucket && !currentCoordinates.isEmpty {
            result.append(RouteSpeedSegment(id: segmentId, coordinates: currentCoordinates, speed: currentSpeed))
            segmentId += 1
            if let boundary = currentCoordinates.last {
                currentCoordinates = [boundary]
            }
        }
        currentCoordinates.append(coordinate)
        currentBucket = bucket
        currentSpeed = coordinate.speed
    }

    if currentCoordinates.count >= 2 {
        result.append(RouteSpeedSegment(id: segmentId, coordinates: currentCoordinates, speed: currentSpeed))
    }
    return result
}

func routeSpeedColor(speed: Double, maxSpeed: Double) -> Color {
    guard maxSpeed > 0 else { return Theme.Colors.accent }
    let ratio = min(speed / maxSpeed, 1.0)
    if ratio < 0.5 {
        let progress = ratio / 0.5
        return Color(
            red: progress,
            green: 0.8,
            blue: 0.2 * (1 - progress)
        )
    }

    let progress = (ratio - 0.5) / 0.5
    return Color(
        red: 0.9 + 0.1 * progress,
        green: 0.8 * (1 - progress),
        blue: 0
    )
}
