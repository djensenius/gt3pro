//
//  GT3CompanionVisionApp.swift
//  GT3CompanionVision
//
//  Created by David Jensenius.
//

import SwiftUI

@main
struct GT3CompanionVisionApp: App {
    @StateObject private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch auth.authState {
            case .unknown:
                ProgressView()
            case .signedOut:
                LoginView()
            case .signedIn:
                VisionContentView()
                    .onAppear {
                        Task { await RideSyncService.shared.syncRides() }
                    }
            }
        }
        .modelContainer(PersistenceController.shared.container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await AuthManager.shared.ensureValidToken() }
        }
    }
}
