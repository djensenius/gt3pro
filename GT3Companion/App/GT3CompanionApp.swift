//
//  GT3CompanionApp.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

@main
struct GT3CompanionApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var coordinator = AppCoordinator.shared
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    #endif
    @StateObject private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
                ContentView()
                    .environmentObject(coordinator)
                    .onAppear {
                        coordinator.start()
                    }
                    #if DEBUG
                    .task { await populateScreenshotRides() }
                    #endif
            } else {
            switch auth.authState {
            case .unknown:
                ProgressView().tint(Theme.Colors.accent)
            case .signedOut:
                if auth.isDemoMode {
                    ContentView()
                        .environmentObject(coordinator)
                } else {
                    LoginView()
                }
            case .signedIn:
                if onboardingComplete {
                    ContentView()
                        .environmentObject(coordinator)
                        .onAppear {
                            coordinator.start(storedPassword: ScooterKeychain.loadPassword())
                            Task { await RideSyncService.shared.syncRides() }
                        }
                        .task { await finalizeOrphanedRides() }
                } else {
                    OnboardingView(isComplete: $onboardingComplete)
                }
            }
            }
            #else
            ContentView()
            #endif
        }
        .modelContainer(PersistenceController.shared.container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await AuthManager.shared.ensureValidToken() }
            #if os(iOS)
            coordinator.resumeFromBackground()
            #endif
        }
    }

    /// Finds rides that were never closed (app was killed mid-ride) and finalises them
    /// using the timestamp of the last recorded sample as the end time.
    @MainActor private func finalizeOrphanedRides() async {
        let context = PersistenceController.shared.container.mainContext
        let descriptor = FetchDescriptor<PersistedRide>(
            predicate: #Predicate { $0.endTime == nil }
        )
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        for ride in orphans {
            let lastSample = (ride.samples ?? []).map(\.timestamp).max()
            ride.endTime = lastSample ?? ride.startTime.addingTimeInterval(60)
            ride.uploaded = false
        }
        try? context.save()
        DebugLogStore.shared.log(
            "Finalized \(orphans.count) orphaned ride(s) on launch",
            category: "Launch",
            level: .warning
        )
    }

    /// Populate sample rides for screenshot mode.
    #if DEBUG
    @MainActor private func populateScreenshotRides() async {
        let context = PersistenceController.shared.container.mainContext
        // Only populate if empty
        let existing = (try? context.fetchCount(FetchDescriptor<PersistedRide>())) ?? 0
        guard existing == 0 else { return }
        for ride in PreviewData.sampleRides {
            context.insert(ride)
        }
        try? context.save()
    }
    #endif
}
