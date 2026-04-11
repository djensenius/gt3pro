//
//  RideHistoryView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

struct RideHistoryView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    var body: some View {
        NavigationStack {
            List(rides) { ride in
                NavigationLink(destination: RideDetailView(ride: ride)) {
                    RideRowView(ride: ride)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
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
    let ride: PersistedRide

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ride.startTime, style: .date)
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    if let condition = ride.weatherCondition {
                        Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                            .font(Theme.Fonts.bodySmall)
                            .foregroundStyle(Theme.Colors.accent)
                        if let temp = ride.weatherTemp {
                            Text(String(format: "%.0f°", temp))
                                .font(Theme.Fonts.bodySmall)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: batteryIconName(for: ride.startBattery))
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(String(
                        format: "%.1f km · %@ · %d%% used",
                        ride.totalDistance,
                        ride.formattedDuration,
                        ride.batteryUsed
                    ))
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
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
        .listRowBackground(Theme.Colors.elevatedBackground)
    }
}

#if DEBUG
#Preview {
    RideHistoryView()
        .modelContainer(PreviewData.container)
}

#Preview("Ride Row") {
    List {
        RideRowView(ride: PreviewData.sampleRide)
    }
}
#endif
