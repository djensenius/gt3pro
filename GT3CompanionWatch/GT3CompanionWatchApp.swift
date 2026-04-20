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
    let workoutManager = RideWorkoutManager()

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        print("[Watch] Received workout configuration from iPhone: \(workoutConfiguration.activityType.rawValue)")
        workoutManager.requestAuthorization()
        workoutManager.startWorkout(with: workoutConfiguration)
    }
}

@main
struct GT3CompanionWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(connectivity)
                .environmentObject(appDelegate.workoutManager)
        }
    }
}
