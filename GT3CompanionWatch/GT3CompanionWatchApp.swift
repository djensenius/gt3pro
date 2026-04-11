//
//  GT3CompanionWatchApp.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI

@main
struct GT3CompanionWatchApp: App {
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var workoutManager = RideWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(connectivity)
                .environmentObject(workoutManager)
        }
    }
}
