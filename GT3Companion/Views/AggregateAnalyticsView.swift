import SwiftUI

struct AggregateAnalyticsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    // Lifetime stats cards
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Theme.Spacing.medium
                    ) {
                        LifetimeStatCard(
                            title: "Total Distance", value: "—", unit: "km",
                            icon: "point.topleft.down.to.point.bottomright.curvepath"
                        )
                        LifetimeStatCard(title: "Total Rides", value: "—", unit: "", icon: "number")
                        LifetimeStatCard(title: "Ride Time", value: "—", unit: "hrs", icon: "clock")
                        LifetimeStatCard(title: "Avg Distance", value: "—", unit: "km", icon: "chart.bar")
                    }

                    SectionHeader(title: "Trends")
                    TrendPlaceholder(title: "Distance per Ride")
                    TrendPlaceholder(title: "Range per Charge")
                    TrendPlaceholder(title: "Efficiency (Wh/km)")

                    SectionHeader(title: "Battery Health")
                    TrendPlaceholder(title: "Cycle Count")
                    TrendPlaceholder(title: "Cell Voltage Spread")

                    SectionHeader(title: "Personal Records")
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: Theme.Spacing.medium
                    ) {
                        LifetimeStatCard(
                            title: "Top Speed", value: "—", unit: "km/h",
                            icon: "gauge.open.with.lines.needle.84percent"
                        )
                        LifetimeStatCard(title: "Longest Ride", value: "—", unit: "km", icon: "trophy")
                        LifetimeStatCard(title: "Most Efficient", value: "—", unit: "Wh/km", icon: "leaf")
                        LifetimeStatCard(title: "Biggest Climb", value: "—", unit: "m", icon: "mountain.2")
                    }
                }
                .padding()
            }
            .background(Theme.Colors.background)
            .navigationTitle("Analytics")
        }
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

struct TrendPlaceholder: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 120)
                .overlay {
                    Text("Chart coming soon")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
    }
}
