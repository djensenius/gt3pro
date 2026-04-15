//
//  GeoUtils.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

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
