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

    private var sortedSamples: [PersistedSample] {
        (ride.samples ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var routeCoordinates: [RouteCoordinate] {
        sortedSamples
            .filter { $0.latitude != nil && $0.longitude != nil }
            .map { RouteCoordinate(latitude: $0.latitude!, longitude: $0.longitude!, speed: $0.speed) }
    }

    private var speedSamples: [(Date, Double)] {
        sortedSamples.map { ($0.timestamp, $0.speed) }
    }

    private struct TempSample {
        let timestamp: Date
        let bms: Double
    }

    private var batterySamples: [(Date, Int)] {
        sortedSamples.map { ($0.timestamp, $0.battery) }
    }

    private var tempSamples: [TempSample] {
        sortedSamples.map { TempSample(timestamp: $0.timestamp, bms: $0.bmsTemp) }
    }

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
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
                            icon: batteryIconName(for: ride.startBattery),
                            color: Theme.Colors.success
                        )
                        StatCard(
                            title: "End",
                            value: "\(ride.endBattery ?? 0)%",
                            icon: batteryIconName(for: ride.endBattery ?? 0),
                            color: Theme.Colors.warning
                        )
                    }

                    weatherSection
                    routeSection
                    speedChartSection
                    batteryChartSection
                    tempChartSection
                }
                .padding()
            }
        }
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
    }

    @ViewBuilder
    private var weatherSection: some View {
        if let condition = ride.weatherCondition {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Weather")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal)

                VStack(spacing: Theme.Spacing.medium) {
                    HStack(spacing: Theme.Spacing.large) {
                        Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(condition.capitalized)
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if let temp = ride.weatherTemp {
                                Text(String(format: "%.0f°C", temp))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            if let feelsLike = ride.weatherFeelsLike {
                                Text(String(format: "Feels like %.0f°C", feelsLike))
                                    .font(Theme.Fonts.bodySmall)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: Theme.Spacing.medium) {
                        if let humidity = ride.weatherHumidity {
                            let formatted = String(format: "%.0f%%", humidity)
                            weatherDetail(icon: "humidity.fill", label: "Humidity", value: formatted)
                        }
                        if let windSpeed = ride.weatherWindSpeed {
                            weatherDetail(icon: "wind", label: "Wind", value: String(format: "%.0f km/h", windSpeed))
                        }
                        if let uvIndex = ride.weatherUVIndex {
                            weatherDetail(icon: "sun.max.fill", label: "UV", value: String(format: "%.0f", uvIndex))
                        }
                    }
                }
                .padding()
                .background(Theme.Colors.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .padding(.horizontal)
            }
        }
    }

    private func weatherDetail(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
            Text(value)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
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

            let hasTempData = tempSamples.contains { $0.bms > 0 }
            if !hasTempData {
                noDataPlaceholder(label: "No temperature data")
            } else {
                Chart {
                    ForEach(tempSamples, id: \.timestamp) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BMS", sample.bms),
                            series: .value("Series", "BMS")
                        )
                        .foregroundStyle(Theme.Colors.warning)
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

#if DEBUG
#Preview {
    NavigationStack {
        RideDetailView(ride: PreviewData.sampleRide)
    }
}
#endif
