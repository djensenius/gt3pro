//
//  GPSTracker.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import CoreLocation
import Foundation
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "GPS")

/// GPS location sample paired with telemetry.
struct GPSSample: Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double       // m/s from GPS
    let course: Double      // degrees
    let horizontalAccuracy: Double
}

/// CoreLocation GPS tracker for ride route recording.
@MainActor
final class GPSTracker: NSObject {
    private let locationManager = CLLocationManager()
    private(set) var latestSample: GPSSample?
    private(set) var isTracking = false

    /// Callback for new GPS samples.
    var onSample: ((GPSSample) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .otherNavigation
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        locationManager.startUpdatingLocation()
        logger.info("GPS tracking started")
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        logger.info("GPS tracking stopped")
    }
}

extension GPSTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let sample = GPSSample(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            speed: max(0, location.speed),
            course: location.course,
            horizontalAccuracy: location.horizontalAccuracy
        )

        latestSample = sample
        onSample?(sample)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("GPS error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        logger.info("Location auth status: \(manager.authorizationStatus.rawValue)")
    }
}
#endif
