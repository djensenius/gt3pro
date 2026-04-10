//
//  PermissionsManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

@preconcurrency import CoreBluetooth
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import os
import UserNotifications

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "Permissions")

/// Permissions that each onboarding step can request.
enum PermissionRequest {
    case bluetooth
    case locationWhenInUse
    case locationAlways
    case health
    case motion
    case notifications
    case none
    case pair
}

/// Requests system permissions on behalf of the onboarding flow.
///
/// Each `request(_:)` call triggers the appropriate system authorization dialog
/// and returns after the dialog has been dismissed (or skipped when unavailable).
@MainActor
final class PermissionsManager: NSObject, ObservableObject {
    private var centralManager: CBCentralManager?
    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()

    func request(_ permission: PermissionRequest) async {
        switch permission {
        case .bluetooth:           await requestBluetooth()
        case .locationWhenInUse:   await requestLocationWhenInUse()
        case .locationAlways:      await requestLocationAlways()
        case .health:              await requestHealth()
        case .motion:              await requestMotion()
        case .notifications:       await requestNotifications()
        case .none:                break
        case .pair:                break
        }
    }

    // MARK: - Individual Requests

    private func requestBluetooth() async {
        // Initialising CBCentralManager triggers the system Bluetooth permission dialog.
        // Poll the authorization status (updated synchronously after the dialog is dismissed).
        centralManager = CBCentralManager(delegate: nil, queue: .main)
        for _ in 0..<20 {
            let status = CBCentralManager.authorization
            if status != .notDetermined {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func requestLocationWhenInUse() async {
        locationManager.requestWhenInUseAuthorization()
        for _ in 0..<20 {
            let status = locationManager.authorizationStatus
            if status != .notDetermined {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func requestLocationAlways() async {
        locationManager.requestAlwaysAuthorization()
        for _ in 0..<20 {
            let status = locationManager.authorizationStatus
            if status != .notDetermined && status != .authorizedWhenInUse {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func requestHealth() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            logger.info("HealthKit not available on this device")
            return
        }
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let readTypes: Set<HKObjectType> = [heartRateType, HKObjectType.workoutType()]
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await HKHealthStore().requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            logger.error("Health auth failed: \(error.localizedDescription)")
        }
    }

    private func requestMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let queue = OperationQueue()
        motionActivityManager.startActivityUpdates(to: queue) { _ in }
        try? await Task.sleep(for: .milliseconds(800))
        motionActivityManager.stopActivityUpdates()
    }

    private func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            logger.error("Notification auth failed: \(error.localizedDescription)")
        }
    }
}
