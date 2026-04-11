//
//  DashboardView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct DashboardView: View {
    #if os(iOS)
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var auth = AuthManager.shared

    private var isDemo: Bool { auth.isDemoMode }
    private var isConnected: Bool { isDemo || coordinator.connectionState == .connected }
    private var speed: Double { isDemo ? 32.5 : coordinator.currentSpeed }
    private var battery: Int { isDemo ? 78 : coordinator.currentBattery }
    private var tripDistance: Double { isDemo ? 12.4 : coordinator.tripDistance }
    private var estimatedRange: Double { isDemo ? 45 : coordinator.estimatedRange }
    private var gearMode: Int { isDemo ? 2 : coordinator.gearMode }
    private var bms1Temp: Double { isDemo ? 28 : coordinator.bms1Temp }
    private var bms2Temp: Double { isDemo ? 30 : coordinator.bms2Temp }
    #else
    @ObservedObject private var auth = AuthManager.shared
    private var isDemo: Bool { auth.isDemoMode }
    private var isConnected: Bool { isDemo }
    private var speed: Double { isDemo ? 32.5 : 0 }
    private var battery: Int { isDemo ? 78 : 0 }
    private var tripDistance: Double { isDemo ? 12.4 : 0 }
    private var estimatedRange: Double { isDemo ? 45 : 0 }
    private var gearMode: Int { isDemo ? 2 : 0 }
    private var bms1Temp: Double { isDemo ? 28 : 0 }
    private var bms2Temp: Double { isDemo ? 30 : 0 }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView {
                    if isDemo {
                        demoBanner
                    }
                    if isConnected {
                        connectedView
                    } else {
                        disconnectedView
                    }
                }
            }
            .navigationTitle("GT3 Companion")
        }
    }

    private var demoBanner: some View {
        Label("Demo Mode", systemImage: "play.circle")
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.vertical, Theme.Spacing.small)
            .padding(.horizontal, Theme.Spacing.medium)
            .background(Theme.Colors.accent.opacity(0.15))
            .clipShape(Capsule())
            .padding(.top, Theme.Spacing.small)
    }

    private var disconnectedView: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer().frame(height: 60)
            Image(systemName: "scooter")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.textSecondary)
                .environment(\.layoutDirection, .rightToLeft)
            Text("Waiting for GT3 Pro")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Power on your scooter to connect automatically")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            #if os(iOS)
            Button {
                coordinator.retryScan()
            } label: {
                Label("Retry Connection", systemImage: "arrow.clockwise")
                    .font(Theme.Fonts.bodyMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity)
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

            #if os(iOS)
            Toggle(isOn: powerOnBinding) {
                Label("Power", systemImage: "power")
                    .font(Theme.Fonts.bodyMedium)
            }
            .tint(Theme.Colors.accent)
            .padding(.horizontal)
            #endif
        }
        .padding()
    }

    #if os(iOS)
    private var powerOnBinding: Binding<Bool> {
        Binding(
            get: { battery > 0 },
            set: { newValue in
                if newValue {
                    coordinator.sendPowerOn()
                }
            }
        )
    }
    #endif

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

#if DEBUG
#Preview {
    #if os(iOS)
    DashboardView()
        .environmentObject(AppCoordinator.shared)
    #else
    DashboardView()
    #endif
}
#endif
