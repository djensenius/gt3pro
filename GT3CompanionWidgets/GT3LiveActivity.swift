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
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading) {
                        Text("\(Int(context.state.speed))")
                            .font(.title.bold())
                        Text("km/h")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text("\(context.state.battery)%")
                            .font(.title2.bold())
                        Text("battery")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
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
                }
            } compactLeading: {
                Label("\(Int(context.state.speed))", systemImage: "bolt.fill")
                    .font(.caption.bold())
            } compactTrailing: {
                Text("\(context.state.battery)%")
                    .font(.caption.bold())
            } minimal: {
                Image(systemName: "scooter")
            }
        }
    }
}
