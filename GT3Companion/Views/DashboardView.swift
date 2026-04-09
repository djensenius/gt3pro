//
//  DashboardView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct DashboardView: View {
    // swiftlint:disable:next todo
    // TODO: Will be driven by ScooterConnectionManager once BLE layer lands.
    @State private var isConnected = false
    @State private var speed: Double = 0
    @State private var battery: Int = 0
    @State private var tripDistance: Double = 0
    @State private var estimatedRange: Double = 0
    @State private var gearMode: Int = 2
    @State private var bms1Temp: Double = 0
    @State private var bms2Temp: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                if isConnected {
                    connectedView
                } else {
                    disconnectedView
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("GT3 Companion")
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Connected", isOn: $isConnected)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
            #endif
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer().frame(height: 60)
            Image(systemName: "scooter")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Waiting for GT3 Pro")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Power on your scooter to connect automatically")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Scan for Scooter (Coming soon)") { }
                .buttonStyle(.gt3Primary)
                .padding(.horizontal, 40)
                .disabled(true)
            Spacer()
        }
        .padding()
    }

    private var connectedView: some View {
        VStack(spacing: Theme.Spacing.large) {
            VStack(spacing: 4) {
                Text("\(Int(speed))")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.accent)
                Text("km/h")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .glassCard()

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "Battery",
                    value: "\(battery)%",
                    icon: "battery.75percent",
                    color: batteryColor
                )
                StatCard(
                    title: "Range",
                    value: String(format: "%.0f km", estimatedRange),
                    icon: "fuelpump",
                    color: Theme.Colors.info
                )
            }

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "Trip",
                    value: String(format: "%.1f km", tripDistance),
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    color: Theme.Colors.secondary
                )
                StatCard(
                    title: "Mode",
                    value: gearModeName,
                    icon: "gauge.with.dots.needle.33percent",
                    color: Theme.Colors.primary
                )
            }

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "BMS 1",
                    value: String(format: "%.0f°C", bms1Temp),
                    icon: "thermometer.medium",
                    color: tempColor(bms1Temp)
                )
                StatCard(
                    title: "BMS 2",
                    value: String(format: "%.0f°C", bms2Temp),
                    icon: "thermometer.medium",
                    color: tempColor(bms2Temp)
                )
            }
        }
        .padding()
    }

    private var batteryColor: Color {
        if battery > 60 { return Theme.Colors.success }
        if battery > 20 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 45 { return Theme.Colors.success }
        if temp < 60 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    private var gearModeName: String {
        switch gearMode {
        case 1: return "Eco"
        case 2: return "Standard"
        case 3: return "Sport"
        default: return "Mode \(gearMode)"
        }
    }
}
