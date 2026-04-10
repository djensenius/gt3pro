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
    private var serial: String { coordinator.serialNumber ?? "—" }
    private var odometer: String {
        coordinator.odometer > 0 ? String(format: "%.0f km", coordinator.odometer) : "—"
    }
    private var totalRideTime: String {
        let hours = coordinator.totalRideTime / 3600
        let mins = (coordinator.totalRideTime % 3600) / 60
        return coordinator.totalRideTime > 0 ? "\(hours)h \(mins)m" : "—"
    }
    private var isConnected: Bool { coordinator.connectionState == .connected }
    #else
    private let serial = "—"
    private let odometer = "—"
    private let totalRideTime = "—"
    private let isConnected = false
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
                    InfoRow(label: "Controller", value: coordinator.controllerFirmware)
                    InfoRow(label: "MCU", value: coordinator.mcuFirmware)
                    InfoRow(label: "BMS 1", value: coordinator.bms1Firmware)
                    InfoRow(label: "BMS 2", value: coordinator.bms2Firmware)
                    InfoRow(label: "BLE", value: coordinator.bleFirmware)
                    #else
                    InfoRow(label: "Controller", value: "—")
                    InfoRow(label: "MCU", value: "—")
                    InfoRow(label: "BMS 1", value: "—")
                    InfoRow(label: "BMS 2", value: "—")
                    InfoRow(label: "BLE", value: "—")
                    #endif
                }

                Section("Charge Status") {
                    InfoRow(label: "Status", value: isConnected ? "Connected" : "Not Connected")
                    InfoRow(label: "Time to Full", value: "—")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Scooter Info")
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
