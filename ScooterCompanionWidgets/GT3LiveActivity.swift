//
//  GT3LiveActivity.swift
//  ScooterCompanionWidgets
//
//  Created by David Jensenius.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct GT3LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GT3RideAttributes.self) { context in
            GT3LiveActivityLockScreen(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { expandedLeading(context) }
                DynamicIslandExpandedRegion(.trailing) { expandedTrailing(context) }
                DynamicIslandExpandedRegion(.bottom) { expandedBottom(context) }
            } compactLeading: {
                compactLeading(context)
            } compactTrailing: {
                compactTrailing(context)
            } minimal: {
                minimal(context)
            }
        }
        .supplementalActivityFamilies([.small])
    }

    // MARK: - Dynamic Island expanded regions

    @ViewBuilder
    private func expandedLeading(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            VStack(alignment: .leading) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.title2)
                Text("Searching").font(.caption)
            }
            .foregroundStyle(.secondary)
        } else if context.state.isAwake {
            VStack(alignment: .leading) {
                Text("\(Int(context.state.speed))").font(.title.bold())
                Text("km/h").font(.caption)
            }
        } else {
            VStack(alignment: .leading) {
                Image(systemName: "moon.zzz.fill").font(.title2)
                Text("Standby").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func expandedTrailing(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            VStack(alignment: .trailing) {
                ProgressView()
                Text("Reconnecting").font(.caption)
            }
            .foregroundStyle(.secondary)
        } else if context.state.isAwake {
            VStack(alignment: .trailing) {
                Text("\(context.state.battery)%").font(.title2.bold())
                Text("battery").font(.caption)
            }
        } else {
            VStack(alignment: .trailing) {
                Image(systemName: "bolt.fill").font(.title2)
                Text("Power on").font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func expandedBottom(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            Text("Scooter out of range — will reconnect automatically")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if context.state.isAwake {
            HStack {
                Label(
                    String(format: "%.1f km", context.state.tripDistance),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                Spacer()
                Label(
                    String(format: "%.0f km", context.state.estimatedRange),
                    systemImage: "fuelpump"
                )
            }
            .font(.subheadline)
        } else {
            Text("Connected — press scooter power button")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Dynamic Island compact / minimal

    @ViewBuilder
    private func compactLeading(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.caption).foregroundStyle(.secondary)
        } else if context.state.isAwake {
            Label("\(Int(context.state.speed))", systemImage: "bolt.fill").font(.caption.bold())
        } else {
            Image(systemName: "moon.zzz.fill").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func compactTrailing(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            Text("…").font(.caption).foregroundStyle(.secondary)
        } else if context.state.isAwake {
            Text("\(context.state.battery)%").font(.caption.bold())
        } else {
            Text("Standby").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func minimal(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        if !context.state.isConnected {
            Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.secondary)
        } else if context.state.isAwake {
            Image(systemName: "scooter").environment(\.layoutDirection, .rightToLeft)
        } else {
            Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
        }
    }

}

private struct GT3LiveActivityLockScreen: View {
    @Environment(\.activityFamily) private var activityFamily

    let context: ActivityViewContext<GT3RideAttributes>

    var body: some View {
        if activityFamily == .small {
            watchLockScreen
        } else if !context.state.isConnected {
            disconnectedLockScreen
        } else if context.state.isAwake {
            awakeLockScreen
        } else {
            standbyLockScreen
        }
    }

    @ViewBuilder
    private var watchLockScreen: some View {
        if !context.state.isConnected {
            VStack(spacing: 2) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title3).foregroundStyle(.secondary)
                Text("Searching…").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        } else if context.state.isAwake {
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(context.state.speed))").font(.title2.bold()).foregroundStyle(.cyan)
                    Text("km/h").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Label(
                        "\(context.state.battery)%",
                        systemImage: batteryIconName(for: context.state.battery)
                    )
                    Label(
                        String(format: "%.1f km", context.state.tripDistance),
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        } else {
            VStack(spacing: 2) {
                Image(systemName: "moon.zzz.fill").font(.title3).foregroundStyle(.cyan.opacity(0.6))
                Text("Standby").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var awakeLockScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.scooterName).font(.headline)
                Spacer()
                Text("\(Int(context.state.speed)) km/h").font(.title2.bold())
            }
            HStack {
                Label(
                    "\(context.state.battery)%",
                    systemImage: batteryIconName(for: context.state.battery)
                )
                Spacer()
                Label(
                    String(format: "%.1f km", context.state.tripDistance),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
            .font(.subheadline)
        }
        .padding()
    }

    private var standbyLockScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.scooterName).font(.headline)
                Spacer()
                Label("Standby", systemImage: "moon.zzz.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Connected — press scooter power button to start")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
    }

    private var disconnectedLockScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.scooterName).font(.headline)
                Spacer()
                Label("Searching", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("Scooter out of range — will reconnect automatically")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
    }

}
