//
//  GT3LiveActivity.swift
//  GT3CompanionWidgets
//
//  Created by David Jensenius.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct GT3LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GT3RideAttributes.self) { context in
            // Lock Screen banner
            if context.state.isAwake {
                awakeLockScreen(context)
            } else {
                standbyLockScreen(context)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.isAwake {
                        VStack(alignment: .leading) {
                            Text("\(Int(context.state.speed))")
                                .font(.title.bold())
                            Text("km/h")
                                .font(.caption)
                        }
                    } else {
                        VStack(alignment: .leading) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.title2)
                            Text("Standby")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isAwake {
                        VStack(alignment: .trailing) {
                            Text("\(context.state.battery)%")
                                .font(.title2.bold())
                            Text("battery")
                                .font(.caption)
                        }
                    } else {
                        VStack(alignment: .trailing) {
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                            Text("Power on")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isAwake {
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                if context.state.isAwake {
                    Label("\(Int(context.state.speed))", systemImage: "bolt.fill")
                        .font(.caption.bold())
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactTrailing: {
                if context.state.isAwake {
                    Text("\(context.state.battery)%")
                        .font(.caption.bold())
                } else {
                    Text("Standby")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                if context.state.isAwake {
                    Image(systemName: "scooter")
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func awakeLockScreen(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.scooterName)
                    .font(.headline)
                Spacer()
                Text("\(Int(context.state.speed)) km/h")
                    .font(.title2.bold())
            }
            HStack {
                Label("\(context.state.battery)%", systemImage: "battery.75percent")
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

    @ViewBuilder
    private func standbyLockScreen(_ context: ActivityViewContext<GT3RideAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(context.attributes.scooterName)
                    .font(.headline)
                Spacer()
                Label("Standby", systemImage: "moon.zzz.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Connected — press scooter power button to start")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
