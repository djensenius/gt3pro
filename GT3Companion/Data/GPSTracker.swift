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

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "GPS")

/// Maximum horizontal accuracy (meters) to accept a GPS reading.
private let maxAccuracyMeters: Double = 50

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
///
/// Uses continuous location updates when the app is active and falls back to
/// significant-location-change monitoring to wake the app when iOS suspends it
/// (e.g. Live Activity failed to start from the background).
@MainActor
final class GPSTracker: NSObject {
    private let locationManager = CLLocationManager()
    private(set) var latestSample: GPSSample?
    private(set) var isTracking = false
    private var usingSignificantLocation = false

    /// Callback for new GPS samples.
    var onSample: ((GPSSample) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .otherNavigation
        locationManager.distanceFilter = 5 // metres — reduces noise while stationary
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
        // Also start significant-location monitoring as a background safety net.
        // If iOS suspends the app, these events will wake it so continuous updates
        // can be restarted in the delegate callback.
        locationManager.startMonitoringSignificantLocationChanges()
        usingSignificantLocation = true
        logger.info("GPS tracking started (continuous + significant-change fallback)")
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        if usingSignificantLocation {
            locationManager.stopMonitoringSignificantLocationChanges()
            usingSignificantLocation = false
        }
        logger.info("GPS tracking stopped")
    }
}

extension GPSTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter out inaccurate readings (cold start, tunnels, indoors)
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maxAccuracyMeters else {
            logger.debug("GPS skipped — accuracy \(location.horizontalAccuracy)m exceeds \(maxAccuracyMeters)m")
            return
        }

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
        let status = manager.authorizationStatus
        logger.info("Location auth status: \(status.rawValue)")
        // If tracking was requested but paused due to auth, restart
        if isTracking && (status == .authorizedAlways || status == .authorizedWhenInUse) {
            manager.startUpdatingLocation()
        }
    }
}
#endif
