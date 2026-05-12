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
        Group {
            if shouldRecordWorkout {
                ridingView
            } else if connectivity.isConnected {
                standbyView
            } else {
                idleView
            }
        }
        .onAppear {
            synchronizeWorkout()
        }
        .onChange(of: connectivity.isRiding) { _, riding in
            synchronizeWorkout(isRiding: riding, rideActive: connectivity.rideActive)
        }
        .onChange(of: connectivity.rideActive) { _, active in
            synchronizeWorkout(isRiding: connectivity.isRiding, rideActive: active)
        }
        .onChange(of: workout.heartRate) { _, hr in
            connectivity.sendHeartRate(Int(hr))
        }
    }

    private var shouldRecordWorkout: Bool {
        connectivity.rideActive || connectivity.isRiding
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
            } else if workout.workoutError != nil {
                HStack {
                    Image(systemName: "heart.slash.fill")
                    Text("HR unavailable")
                }
                .font(.caption2)
                .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Label("\(connectivity.battery)%", systemImage: batteryIconName(for: connectivity.battery))
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
    }

    private func synchronizeWorkout(
        isRiding: Bool? = nil,
        rideActive: Bool? = nil
    ) {
        let shouldStart = (rideActive ?? connectivity.rideActive) || (isRiding ?? connectivity.isRiding)
        if shouldStart {
            workout.startWorkout()
        } else {
            workout.endWorkout()
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
                .environment(\.layoutDirection, .rightToLeft)
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
