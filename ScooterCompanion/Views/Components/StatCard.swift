//
//  StatCard.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Charts
import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct RideHealthStatCards: View {
    let healthSummary: PersistedRideHealthSummary

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150))],
            spacing: Theme.Spacing.medium
        ) {
            if let averageHeartRate = healthSummary.averageHeartRate {
                StatCard(
                    title: "Avg HR",
                    value: "\(averageHeartRate) bpm",
                    icon: "heart.fill",
                    color: Theme.Colors.error
                )
            }
            if let maxHeartRate = healthSummary.maxHeartRate {
                StatCard(
                    title: "Max HR",
                    value: "\(maxHeartRate) bpm",
                    icon: "heart.text.square.fill",
                    color: Theme.Colors.error
                )
            }
            if let activeCalories = healthSummary.activeCalories {
                StatCard(
                    title: "Active Calories",
                    value: "\(Int(activeCalories.rounded())) cal",
                    icon: "flame.fill",
                    color: Theme.Colors.warning
                )
            }
        }
    }
}

struct RideHeartRateChartSample: Identifiable {
    let timestamp: Date
    let value: Int

    var id: Date { timestamp }
}

struct RideHeartRateChart: View {
    let samples: [RideHeartRateChartSample]

    var body: some View {
        if hasEnoughSamples {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Heart Rate")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal)

                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("Heart Rate", sample.value)
                        )
                        .foregroundStyle(Theme.Colors.error)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("bpm")
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private var hasEnoughSamples: Bool {
        samples.count >= 2 && Set(samples.map(\.timestamp)).count >= 2
    }
}

#if DEBUG
#Preview {
    HStack {
        StatCard(title: "Battery", value: "85%", icon: "battery.75percent", color: Theme.Colors.success)
        StatCard(
            title: "Speed",
            value: "42 km/h",
            icon: "gauge.open.with.lines.needle.33percent",
            color: Theme.Colors.accent
        )
    }
    .padding()
}
#endif
