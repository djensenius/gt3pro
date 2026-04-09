//
//  WatchRideView.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI

struct WatchRideView: View {
    @State private var speed: Double = 0
    @State private var battery: Int = 0
    @State private var heartRate: Int = 0
    @State private var tripDistance: Double = 0
    @State private var isRiding = false

    var body: some View {
        if isRiding {
            ridingView
        } else {
            idleView
        }
    }

    private var ridingView: some View {
        VStack(spacing: 4) {
            Text("\(Int(speed))")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
            Text("km/h")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("\(heartRate)")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                Label("\(battery)%", systemImage: "battery.75percent")
                    .font(.caption)
                Label(
                    String(format: "%.1f km", tripDistance),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Image(systemName: "scooter")
                .font(.system(size: 40))
                .foregroundStyle(.cyan)
            Text("GT3 Companion")
                .font(.headline)
            Text("Waiting for ride")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
