//
//  ScooterCompanionWatchApp.swift
//  ScooterCompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI
import WatchKit
import HealthKit

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let workoutManager = RideWorkoutManager()
    let connectivity = WatchConnectivityManager.shared

    func applicationDidFinishLaunching() {
        WatchConnectivityManager.logStartup("applicationDidFinishLaunching")
        workoutManager.delegate = self
        workoutManager.requestAuthorization { granted in
            WatchConnectivityManager.logStartup("HealthKit workout authorization at launch: \(granted)")
        }
        observeRideState()
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchConnectivityManager.logStartup(
            "Received workout configuration from iPhone: \(workoutConfiguration.activityType.rawValue)"
        )
        connectivity.markAutoWorkoutStarted()
        workoutManager.startWorkout(with: workoutConfiguration)
    }

    func handleActiveWorkoutRecovery() {
        WatchConnectivityManager.logStartup("handleActiveWorkoutRecovery")
        workoutManager.recoverWorkout()
    }

    private func observeRideState() {
        connectivity.onShouldRecordWorkoutChanged = { [weak self] shouldRecordWorkout in
            self?.synchronizeWorkout(shouldRecordWorkout: shouldRecordWorkout)
        }
        synchronizeWorkout(shouldRecordWorkout: connectivity.shouldRecordWorkout)
    }

    private func synchronizeWorkout(shouldRecordWorkout: Bool) {
        if shouldRecordWorkout {
            workoutManager.startWorkout()
        } else {
            connectivity.flushHealthData()
            workoutManager.endWorkout()
        }
    }
}

extension WatchAppDelegate: RideWorkoutManagerDelegate {
    func rideWorkoutManager(
        _ manager: RideWorkoutManager,
        didCollectHeartRateSample sample: WatchHeartRateSample,
        activeCalories: Double
    ) {
        connectivity.enqueueHeartRateSample(
            bpm: sample.bpm,
            timestamp: sample.timestamp,
            activeCalories: activeCalories
        )
    }

    func rideWorkoutManager(_ manager: RideWorkoutManager, didUpdateActiveCalories activeCalories: Double) {
        connectivity.updateActiveCalories(activeCalories)
    }
}

@main
struct ScooterCompanionWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @State private var connectivity = WatchConnectivityManager.shared

    init() {
        WatchConnectivityManager.logStartup("ScooterCompanionWatchApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environment(connectivity)
                .environment(appDelegate.workoutManager)
        }
    }
}
