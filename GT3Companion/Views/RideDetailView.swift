//
//  RideDetailView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct RideDetailView: View {
    let ride: RideHistoryItem

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                HStack(spacing: Theme.Spacing.medium) {
                    StatCard(
                        title: "Distance",
                        value: String(format: "%.1f km", ride.distance),
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        color: Theme.Colors.accent
                    )
                    StatCard(
                        title: "Duration",
                        value: ride.formattedDuration,
                        icon: "clock",
                        color: Theme.Colors.secondary
                    )
                }

                HStack(spacing: Theme.Spacing.medium) {
                    StatCard(
                        title: "Max Speed",
                        value: String(format: "%.0f km/h", ride.maxSpeed),
                        icon: "gauge.open.with.lines.needle.84percent",
                        color: Theme.Colors.error
                    )
                    StatCard(
                        title: "Avg Speed",
                        value: String(format: "%.0f km/h", ride.avgSpeed),
                        icon: "gauge.open.with.lines.needle.33percent",
                        color: Theme.Colors.info
                    )
                }

                HStack(spacing: Theme.Spacing.medium) {
                    StatCard(
                        title: "Start",
                        value: "\(ride.startBattery)%",
                        icon: "battery.100percent",
                        color: Theme.Colors.success
                    )
                    StatCard(
                        title: "End",
                        value: "\(ride.endBattery)%",
                        icon: "battery.25percent",
                        color: Theme.Colors.warning
                    )
                }

                routePlaceholder
                speedChartPlaceholder
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle(ride.date.formatted(date: .abbreviated, time: .omitted))
    }

    private var routePlaceholder: some View {
        VStack(alignment: .leading) {
            Text("Route")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 200)
                .overlay {
                    Text("GPS Route Map")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
        .padding(.horizontal)
    }

    private var speedChartPlaceholder: some View {
        VStack(alignment: .leading) {
            Text("Speed")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 150)
                .overlay {
                    Text("Speed over time chart")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
        .padding(.horizontal)
    }
}
