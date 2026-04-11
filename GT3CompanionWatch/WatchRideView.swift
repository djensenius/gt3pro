//
//  WatchRideView.swift
//  GT3CompanionWatch
//
//  Created by David Jensenius.
//

import SwiftUI

struct WatchRideView: View {
    @EnvironmentObject private var connectivity: WatchConnectivityManager
    @EnvironmentObject private var workout: RideWorkoutManager

    var body: some View {
        if connectivity.isRiding {
            ridingView
        } else if connectivity.isConnected {
            standbyView
        } else {
            idleView
        }
    }

    private var ridingView: some View {
        VStack(spacing: 4) {
            Text("\(Int(connectivity.speed))")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.cyan)
            Text("km/h")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if workout.heartRate > 0 {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("\(Int(workout.heartRate))")
                        .font(.headline)
                }
            }

            HStack(spacing: 12) {
                Label("\(connectivity.battery)%", systemImage: "battery.75percent")
                    .font(.caption)
                Label(
                    String(format: "%.1f km", connectivity.tripDistance),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.caption)
            }
            .foregroundStyle(.secondary)

            Text(gearModeName)
                .font(.caption2)
                .foregroundStyle(.cyan.opacity(0.7))
        }
        .onAppear {
            workout.requestAuthorization()
            workout.startWorkout()
        }
        .onDisappear {
            workout.endWorkout()
        }
        .onChange(of: connectivity.isRiding) { _, riding in
            if !riding { workout.endWorkout() }
        }
        .onChange(of: workout.heartRate) { _, hr in
            connectivity.sendHeartRate(Int(hr))
        }
    }

    private var standbyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(.cyan.opacity(0.5))
            Text("Connected")
                .font(.headline)
            Text("\(connectivity.battery)%")
                .font(.title3.bold())
                .foregroundStyle(.cyan)
            Text("Waiting for ride")
                .font(.caption)
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
            Text("Open app on iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gearModeName: String {
        switch connectivity.gearMode {
        case 1: return "Walk"
        case 2: return "Eco"
        case 3: return "Sport"
        case 4: return "Race"
        default: return ""
        }
    }
}
