//
//  RideDetailView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Charts
import SwiftUI

struct RideDetailView: View {
    let ride: PersistedRide

    private var routeCoordinates: [RouteCoordinate] {
        (ride.samples ?? [])
            .filter { $0.latitude != nil && $0.longitude != nil }
            .map { RouteCoordinate(latitude: $0.latitude!, longitude: $0.longitude!, speed: $0.speed) }
    }

    private var speedSamples: [(Date, Double)] {
        (ride.samples ?? []).map { ($0.timestamp, $0.speed) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                HStack(spacing: Theme.Spacing.medium) {
                    StatCard(
                        title: "Distance",
                        value: String(format: "%.1f km", ride.totalDistance),
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
                        value: "\(ride.endBattery ?? 0)%",
                        icon: "battery.25percent",
                        color: Theme.Colors.warning
                    )
                }

                routeSection
                speedChartSection
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Route")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)
            #if os(iOS)
            MapRouteView(coordinates: routeCoordinates)
                .padding(.horizontal)
            #endif
        }
    }

    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Speed")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            if speedSamples.isEmpty {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 150)
                    .overlay {
                        Text("No speed data")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal)
            } else {
                Chart {
                    ForEach(speedSamples, id: \.0) { timestamp, speed in
                        LineMark(
                            x: .value("Time", timestamp),
                            y: .value("Speed", speed)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("km/h")
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }
}
