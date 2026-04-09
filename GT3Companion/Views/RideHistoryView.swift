//
//  RideHistoryView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct RideHistoryView: View {
    @State private var rides: [RideHistoryItem] = []

    var body: some View {
        NavigationStack {
            List(rides) { ride in
                NavigationLink(destination: RideDetailView(ride: ride)) {
                    RideRowView(ride: ride)
                }
            }
            .navigationTitle("Ride History")
            .overlay {
                if rides.isEmpty {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Your rides will appear here after your first trip.")
                    )
                }
            }
        }
    }
}

struct RideRowView: View {
    let ride: RideHistoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.date, style: .date)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(String(
                    format: "%.1f km · %@ · %d%% battery used",
                    ride.distance,
                    ride.formattedDuration,
                    ride.batteryUsed
                ))
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text(String(format: "%.0f", ride.maxSpeed))
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.accent)
            Text("km/h")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

// swiftlint:disable:next todo
// TODO: Migrate to PersistedRide once Core Data / SwiftData models land.
// RideHistoryItem remains as the view-model layer between persistence and UI.
struct RideHistoryItem: Identifiable {
    let id = UUID()
    let date: Date
    let distance: Double
    let duration: TimeInterval
    let maxSpeed: Double
    let avgSpeed: Double
    let batteryUsed: Int
    let startBattery: Int
    let endBattery: Int

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

}

#if DEBUG
extension RideHistoryItem {
    static let sampleData: [RideHistoryItem] = [
        RideHistoryItem(
            date: Date().addingTimeInterval(-86400),
            distance: 12.4,
            duration: 1455,
            maxSpeed: 78.2,
            avgSpeed: 42.1,
            batteryUsed: 34,
            startBattery: 95,
            endBattery: 61
        ),
        RideHistoryItem(
            date: Date().addingTimeInterval(-172800),
            distance: 8.7,
            duration: 980,
            maxSpeed: 65.0,
            avgSpeed: 38.5,
            batteryUsed: 22,
            startBattery: 88,
            endBattery: 66
        )
    ]
}
#endif
