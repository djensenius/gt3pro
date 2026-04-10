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

    private struct TempSample {
        let timestamp: Date
        let bms1: Double
        let bms2: Double
    }

    private var batterySamples: [(Date, Int)] {
        (ride.samples ?? []).map { ($0.timestamp, $0.battery) }
    }

    private var tempSamples: [TempSample] {
        (ride.samples ?? []).map { TempSample(timestamp: $0.timestamp, bms1: $0.bms1Temp, bms2: $0.bms2Temp) }
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
                batteryChartSection
                tempChartSection
            }
            .padding()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
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

    private var batteryChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Battery")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            if batterySamples.isEmpty {
                noDataPlaceholder(label: "No battery data")
            } else {
                Chart {
                    ForEach(batterySamples, id: \.0) { timestamp, battery in
                        LineMark(
                            x: .value("Time", timestamp),
                            y: .value("Battery", battery)
                        )
                        .foregroundStyle(Theme.Colors.success)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("%")
                .chartYScale(domain: 0...100)
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private var tempChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("BMS Temperature")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            let hasTempData = tempSamples.contains { $0.bms1 > 0 || $0.bms2 > 0 }
            if !hasTempData {
                noDataPlaceholder(label: "No temperature data")
            } else {
                Chart {
                    ForEach(tempSamples, id: \.timestamp) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BMS 1", sample.bms1),
                            series: .value("Series", "BMS 1")
                        )
                        .foregroundStyle(Theme.Colors.warning)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BMS 2", sample.bms2),
                            series: .value("Series", "BMS 2")
                        )
                        .foregroundStyle(Theme.Colors.error)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(position: .topTrailing)
                .chartXAxis(.hidden)
                .chartYAxisLabel("°C")
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private func noDataPlaceholder(label: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .fill(Theme.Colors.secondaryBackground)
            .frame(height: 150)
            .overlay { Text(label).foregroundStyle(Theme.Colors.textSecondary) }
            .padding(.horizontal)
    }
}
