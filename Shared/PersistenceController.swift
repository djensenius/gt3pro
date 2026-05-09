//
//  PersistenceController.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation
import SwiftData

/// Shared SwiftData stack used by all GT3 Companion targets.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer

    init() {
        let schema = Schema([
            PersistedRide.self,
            PersistedSample.self,
            PersistedRidePhoto.self,
            UploadQueueItem.self,
            StoredCredential.self
        ])
        do {
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var context: ModelContext {
        container.mainContext
    }
}
