//
//  GT3CompanionWatchApp.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI
import WatchKit
import HealthKit

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    var onWorkoutConfiguration: ((HKWorkoutConfiguration) -> Void)?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        print("[Watch] Received workout configuration from iPhone: \(workoutConfiguration.activityType.rawValue)")
        onWorkoutConfiguration?(workoutConfiguration)
    }
}

@main
struct GT3CompanionWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var workoutManager = RideWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(connectivity)
                .environmentObject(workoutManager)
                .onAppear {
                    appDelegate.onWorkoutConfiguration = { [workoutManager] _ in
                        workoutManager.requestAuthorization()
                        workoutManager.startWorkout()
                    }
                }
        }
    }
}
