//
//  MacContentView.swift
//  GT3CompanionMac
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

struct MacContentView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: MacRideHistoryView(rides: rides)) {
                    Label("Rides", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                NavigationLink(destination: AggregateAnalyticsView()) {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
                NavigationLink(destination: ScooterInfoView()) {
                    Label {
                        Text("Scooter")
                    } icon: {
                        Image(systemName: "scooter")
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
            }
            .navigationTitle("GT3 Companion")
        } detail: {
            VStack(spacing: Theme.Spacing.large) {
                Image(systemName: "scooter")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent)
                    .environment(\.layoutDirection, .rightToLeft)

                Text("GT3 Companion")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Select a section to explore your ride data")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MacRideHistoryView: View {
    let rides: [PersistedRide]

    var body: some View {
        List(rides) { ride in
            NavigationLink(destination: MacRideDetailView(ride: ride)) {
                MacRideRowView(ride: ride)
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

struct MacRideRowView: View {
    let ride: PersistedRide

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ride.startTime, style: .date)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(String(
                format: "%.1f km · %@ · %.0f km/h max",
                ride.totalDistance,
                ride.formattedDuration,
                ride.maxSpeed
            ))
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct MacRideDetailView: View {
    let ride: PersistedRide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Text(ride.startTime.formatted(date: .complete, time: .shortened))
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.large,
                     verticalSpacing: Theme.Spacing.medium) {
                    GridRow {
                        statItem(label: "Distance", value: String(format: "%.1f km", ride.totalDistance))
                        statItem(label: "Duration", value: ride.formattedDuration)
                    }
                    GridRow {
                        statItem(label: "Max Speed", value: String(format: "%.0f km/h", ride.maxSpeed))
                        statItem(label: "Avg Speed", value: String(format: "%.0f km/h", ride.avgSpeed))
                    }
                    GridRow {
                        statItem(label: "Start Battery", value: "\(ride.startBattery)%")
                        statItem(label: "End Battery", value: "\(ride.endBattery ?? 0)%")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

#if DEBUG
#Preview {
    MacContentView()
        .modelContainer(PreviewData.container)
}
#endif
