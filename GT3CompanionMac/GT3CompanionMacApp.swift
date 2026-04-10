//
//  GT3CompanionMacApp.swift
//  GT3CompanionMac
//
//  Created by David Jensenius.
//

import SwiftUI

@main
struct GT3CompanionMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
                .onAppear {
                    Task { await RideSyncService.shared.syncRides() }
                }
        }
        .modelContainer(PersistenceController.shared.container)
    }
}
