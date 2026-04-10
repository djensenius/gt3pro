//
//  GT3CompanionVisionApp.swift
//  GT3CompanionVision
//
//  Created by David Jensenius.
//

import SwiftUI

@main
struct GT3CompanionVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VisionContentView()
                .onAppear {
                    Task { await RideSyncService.shared.syncRides() }
                }
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
