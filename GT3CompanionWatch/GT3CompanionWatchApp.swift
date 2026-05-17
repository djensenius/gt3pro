//
//  GT3CompanionWatchApp.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI
import WatchKit
import HealthKit
import Combine

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    let workoutManager = RideWorkoutManager()
    let connectivity = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching() {
        WatchConnectivityManager.logStartup("applicationDidFinishLaunching")
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
        connectivity.$shouldRecordWorkout
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldRecordWorkout in
                self?.synchronizeWorkout(shouldRecordWorkout: shouldRecordWorkout)
            }
            .store(in: &cancellables)
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

@main
struct GT3CompanionWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var connectivity = WatchConnectivityManager.shared

    init() {
        WatchConnectivityManager.logStartup("GT3CompanionWatchApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(connectivity)
                .environmentObject(appDelegate.workoutManager)
        }
    }
}
