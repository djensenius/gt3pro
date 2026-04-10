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
    @StateObject private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            switch auth.authState {
            case .unknown:
                ProgressView().tint(Theme.Colors.accent)
            case .signedOut:
                LoginView()
            case .signedIn:
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
            }
            #else
            ContentView()
            #endif
        }
        .modelContainer(PersistenceController.shared.container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await AuthManager.shared.ensureValidToken() }
        }
    }
}
