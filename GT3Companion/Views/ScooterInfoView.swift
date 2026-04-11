//
//  ScooterInfoView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct ScooterInfoView: View {
    #if os(iOS)
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject private var auth = AuthManager.shared
    private var isDemo: Bool { auth.isDemoMode }
    private var serial: String { isDemo ? "N2GWD1234567890" : (coordinator.serialNumber ?? "—") }
    private var odometer: String {
        if isDemo { return "2,450 km" }
        return coordinator.odometer > 0 ? String(format: "%.0f km", coordinator.odometer) : "—"
    }
    private var totalRideTime: String {
        if isDemo { return "86h 12m" }
        let hours = coordinator.totalRideTime / 3600
        let mins = (coordinator.totalRideTime % 3600) / 60
        return coordinator.totalRideTime > 0 ? "\(hours)h \(mins)m" : "—"
    }
    private var isConnected: Bool { isDemo || coordinator.connectionState == .connected }
    private var chargeStatusText: String {
        if isDemo { return "Not Charging" }
        // BMS register 0x92: 0=idle, 1=discharging, 2=charging, 3=full
        switch coordinator.chargeStatus {
        case 0: return "Idle"
        case 1: return "Not Charging"
        case 2: return "Charging"
        case 3: return "Fully Charged"
        default: return "Unknown (\(coordinator.chargeStatus))"
        }
    }
    private var timeToFullText: String {
        if isDemo { return "—" }
        let mins = coordinator.timeToFull
        guard mins > 0 else { return "—" }
        return "\(mins / 60)h \(mins % 60)m"
    }
    #else
    @ObservedObject private var auth = AuthManager.shared
    private var isDemo: Bool { auth.isDemoMode }
    private var serial: String { isDemo ? "N2GWD1234567890" : "—" }
    private var odometer: String { isDemo ? "2,450 km" : "—" }
    private var totalRideTime: String { isDemo ? "86h 12m" : "—" }
    private var isConnected: Bool { isDemo }
    private var chargeStatusText: String { isDemo ? "Not Charging" : "—" }
    private var timeToFullText: String { "—" }
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    InfoRow(label: "Model", value: "GT3 Pro")
                    InfoRow(label: "Serial", value: serial)
                    InfoRow(label: "Odometer", value: odometer)
                    InfoRow(label: "Total Ride Time", value: totalRideTime)
                }

                Section("Firmware") {
                    #if os(iOS)
                    InfoRow(label: "Controller", value: isDemo ? "1.2.3" : coordinator.controllerFirmware)
                    InfoRow(label: "MCU", value: isDemo ? "2.0.1" : coordinator.mcuFirmware)
                    InfoRow(label: "BMS 1", value: isDemo ? "1.1.0" : coordinator.bms1Firmware)
                    InfoRow(label: "BMS 2", value: isDemo ? "1.1.0" : coordinator.bms2Firmware)
                    InfoRow(label: "BLE", value: isDemo ? "3.0.2" : coordinator.bleFirmware)
                    #else
                    InfoRow(label: "Controller", value: isDemo ? "1.2.3" : "—")
                    InfoRow(label: "MCU", value: isDemo ? "2.0.1" : "—")
                    InfoRow(label: "BMS 1", value: isDemo ? "1.1.0" : "—")
                    InfoRow(label: "BMS 2", value: isDemo ? "1.1.0" : "—")
                    InfoRow(label: "BLE", value: isDemo ? "3.0.2" : "—")
                    #endif
                }

                Section("Battery") {
                    InfoRow(label: "Charge Status", value: chargeStatusText)
                    InfoRow(label: "Time to Full", value: timeToFullText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Scooter Info")
        }
    }
}

#if DEBUG
#Preview {
    #if os(iOS)
    ScooterInfoView()
        .environmentObject(AppCoordinator.shared)
    #else
    ScooterInfoView()
    #endif
}
#endif
