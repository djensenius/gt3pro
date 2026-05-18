//
//  GT3CompanionVisionApp.swift
//  GT3CompanionVision
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

@main
struct GT3CompanionVisionApp: App {
    @State private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
                VisionContentView()
                    #if DEBUG
                    .task { await populateScreenshotRides() }
                    #endif
            } else {
            switch auth.authState {
            case .unknown:
                ProgressView()
            case .signedOut:
                if auth.isDemoMode {
                    VisionContentView()
                } else {
                    LoginView()
                }
            case .signedIn:
                VisionContentView()
                    .onAppear {
                        Task { await RideSyncService.shared.syncRides() }
                    }
            }
            }
        }
        .modelContainer(PersistenceController.shared.container)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await AuthManager.shared.ensureValidToken() }
        }

        ImmersiveSpace(id: "RideRouteSpace") {
            VisionRouteImmersiveConceptView()
        }
    }

    #if DEBUG
    @MainActor private func populateScreenshotRides() async {
        let context = PersistenceController.shared.container.mainContext
        let existing = (try? context.fetchCount(FetchDescriptor<PersistedRide>())) ?? 0
        guard existing == 0 else { return }
        for ride in PreviewData.sampleRides {
            context.insert(ride)
        }
        try? context.save()
    }
    #endif
}
