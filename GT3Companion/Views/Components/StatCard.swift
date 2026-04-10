//
//  StatCard.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

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
