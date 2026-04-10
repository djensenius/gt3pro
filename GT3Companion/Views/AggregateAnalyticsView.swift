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

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Theme.Spacing.large) {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
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
                    }

                    if !rides.isEmpty {
                        SectionHeader(title: "Distance per Ride")
                        distanceChart

                        SectionHeader(title: "Personal Records")
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: Theme.Spacing.medium
                        ) {
                            LifetimeStatCard(
                                title: "Top Speed",
                                value: String(format: "%.0f", topSpeed),
                                unit: "km/h",
                                icon: "gauge.open.with.lines.needle.84percent"
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
            ForEach(rides.prefix(20).reversed(), id: \.rideId) { ride in
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
        .padding(.horizontal)
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
        .frame(maxWidth: .infinity)
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
