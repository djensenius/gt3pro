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

    func applicationDidFinishLaunching() {
        WatchConnectivityManager.logStartup("applicationDidFinishLaunching")
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchConnectivityManager.logStartup(
            "Received workout configuration from iPhone: \(workoutConfiguration.activityType.rawValue)"
        )
        workoutManager.startWorkout(with: workoutConfiguration)
    }
}

@main
struct GT3CompanionWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var connectivity = WatchConnectivityManager()

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
