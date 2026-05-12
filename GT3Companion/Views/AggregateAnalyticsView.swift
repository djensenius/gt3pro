import Charts
import SwiftData
import SwiftUI

struct AggregateAnalyticsView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    private var totalDistance: Double { rides.reduce(0) { $0 + $1.totalDistance } }
    private var totalRides: Int { rides.count }
    private var totalHours: Double { rides.reduce(0) { $0 + $1.duration } / 3600 }
    private var avgDistance: Double { rides.isEmpty ? 0 : totalDistance / Double(rides.count) }
    private var topSpeed: Double { rides.map(\.maxSpeed).max() ?? 0 }
    private var longestRide: Double { rides.map(\.totalDistance).max() ?? 0 }
    private var averageBatteryEfficiency: Double {
        let values = rides.compactMap { ride -> Double? in
            guard ride.batteryUsed > 0 else { return nil }
            return ride.totalDistance / Double(ride.batteryUsed)
        }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var averageRoughness: Double? {
        let values = rides.compactMap { $0.ridePresentation.averageRoughness }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var recentRides: [PersistedRide] {
        Array(rides.prefix(20).reversed())
    }

    private var weatherCounts: [(condition: String, count: Int)] {
        let grouped = Dictionary(grouping: rides.compactMap(\.weatherCondition)) { $0.capitalized }
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 160))],
                            spacing: Theme.Spacing.medium
                        ) {
                            LifetimeStatCard(
                                title: "Total Distance",
                                value: String(format: "%.0f", totalDistance),
                                unit: "km",
                                icon: "point.topleft.down.to.point.bottomright.curvepath"
                            )
                            LifetimeStatCard(
                                title: "Total Rides",
                                value: "\(totalRides)",
                                unit: "",
                                icon: "number"
                            )
                            LifetimeStatCard(
                                title: "Ride Time",
                                value: String(format: "%.1f", totalHours),
                                unit: "hrs",
                                icon: "clock"
                            )
                            LifetimeStatCard(
                                title: "Avg Distance",
                                value: String(format: "%.1f", avgDistance),
                                unit: "km",
                                icon: "chart.bar"
                            )
                            LifetimeStatCard(
                                title: "Battery Efficiency",
                                value: String(format: "%.2f", averageBatteryEfficiency),
                                unit: "km/%",
                                icon: "bolt.batteryblock"
                            )
                            if let averageRoughness {
                                LifetimeStatCard(
                                    title: "Avg Roughness",
                                    value: String(format: "%.2f", averageRoughness),
                                    unit: "",
                                    icon: "waveform.path.ecg"
                                )
                            }
                        }

                        if !rides.isEmpty {
                            SectionHeader(title: "Distance Trend")
                            analyticsCard(distanceChart)

                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 320))],
                                spacing: Theme.Spacing.medium
                            ) {
                                analyticsCard(speedTrendChart)
                                analyticsCard(batteryEfficiencyChart)
                                analyticsCard(weatherChart)
                                analyticsCard(roughnessChart)
                            }

                            SectionHeader(title: "Personal Records")
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 180))],
                                spacing: Theme.Spacing.medium
                            ) {
                                LifetimeStatCard(
                                    title: "Top Speed",
                                    value: String(format: "%.0f", topSpeed),
                                    unit: "km/h",
                                    icon: "speedometer"
                                )
                                LifetimeStatCard(
                                    title: "Longest Ride",
                                    value: String(format: "%.1f", longestRide),
                                    unit: "km",
                                    icon: "trophy"
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Analytics")
        }
    }

    private var distanceChart: some View {
        Chart {
            ForEach(recentRides, id: \.rideId) { ride in
                BarMark(
                    x: .value("Date", ride.startTime, unit: .day),
                    y: .value("Distance", ride.totalDistance)
                )
                .foregroundStyle(Theme.Colors.accent)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
            }
        }
        .chartYAxisLabel("km")
        .frame(height: 180)
    }

    private var speedTrendChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Top Speed Trend")
                .font(Theme.Fonts.headerLarge())
            Chart {
                ForEach(recentRides, id: \.rideId) { ride in
                    LineMark(
                        x: .value("Date", ride.startTime, unit: .day),
                        y: .value("Top Speed", ride.maxSpeed)
                    )
                    .foregroundStyle(Theme.Colors.error)
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxisLabel("km/h")
            .frame(height: 180)
        }
    }

    private var batteryEfficiencyChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Battery Efficiency")
                .font(Theme.Fonts.headerLarge())
            let values = recentRides.compactMap { ride -> (Date, Double)? in
                guard ride.batteryUsed > 0 else { return nil }
                return (ride.startTime, ride.totalDistance / Double(ride.batteryUsed))
            }
            if values.isEmpty {
                emptyChart("No battery efficiency data")
            } else {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, sample in
                        LineMark(
                            x: .value("Date", sample.0, unit: .day),
                            y: .value("Efficiency", sample.1)
                        )
                        .foregroundStyle(Theme.Colors.success)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("km/%")
                .frame(height: 180)
            }
        }
    }

    private var weatherChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Weather Mix")
                .font(Theme.Fonts.headerLarge())
            if weatherCounts.isEmpty {
                emptyChart("No weather data")
            } else {
                Chart {
                    ForEach(Array(weatherCounts.prefix(6).enumerated()), id: \.offset) { _, entry in
                        BarMark(
                            x: .value("Rides", entry.count),
                            y: .value("Condition", entry.condition)
                        )
                        .foregroundStyle(Theme.Colors.secondary)
                    }
                }
                .frame(height: 180)
            }
        }
    }

    private var roughnessChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Roughness by Ride")
                .font(Theme.Fonts.headerLarge())
            let values = recentRides.compactMap { ride -> (Date, Double)? in
                guard let roughness = ride.ridePresentation.averageRoughness else { return nil }
                return (ride.startTime, roughness)
            }
            if values.isEmpty {
                emptyChart("Hydrate rides to see roughness")
            } else {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, sample in
                        BarMark(
                            x: .value("Date", sample.0, unit: .day),
                            y: .value("Roughness", sample.1)
                        )
                        .foregroundStyle(Theme.Colors.primary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 180)
            }
        }
    }

    private func analyticsCard<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    private func emptyChart(_ label: String) -> some View {
        Text(label)
            .frame(maxWidth: .infinity, minHeight: 180)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

struct LifetimeStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.Colors.accent)
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            if !unit.isEmpty {
                Text(unit)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(title)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .glassCard()
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
        }
    }
}

#if DEBUG
#Preview {
    AggregateAnalyticsView()
        .modelContainer(PreviewData.container)
}

#Preview("Lifetime Stat Card") {
    LifetimeStatCard(
        title: "Total Distance",
        value: "432",
        unit: "km",
        icon: "point.topleft.down.to.point.bottomright.curvepath"
    )
    .frame(width: 180)
}

#Preview("Section Header") {
    SectionHeader(title: "Distance per Ride")
        .padding()
}
#endif
