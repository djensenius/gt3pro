//
//  GT3CompanionApp.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

@main
struct GT3CompanionApp: App {
    #if os(iOS)
    @StateObject private var coordinator = AppCoordinator.shared
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            if onboardingComplete {
                ContentView()
                    .environmentObject(coordinator)
                    .onAppear {
                        coordinator.start()
                        Task { await RideSyncService.shared.syncRides() }
                    }
            } else {
                OnboardingView(isComplete: $onboardingComplete)
            }
            #else
            ContentView()
            #endif
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
