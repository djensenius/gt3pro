//
//  ScooterInfoView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct ScooterInfoView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    InfoRow(label: "Model", value: "GT3 Pro")
                    InfoRow(label: "Serial", value: "—")
                    InfoRow(label: "Odometer", value: "—")
                    InfoRow(label: "Total Ride Time", value: "—")
                }

                Section("Firmware") {
                    InfoRow(label: "Controller", value: "—")
                    InfoRow(label: "MCU", value: "—")
                    InfoRow(label: "BMS 1", value: "—")
                    InfoRow(label: "BMS 2", value: "—")
                    InfoRow(label: "BLE", value: "—")
                }

                Section("Battery 1") {
                    InfoRow(label: "Charge Cycles", value: "—")
                    InfoRow(label: "Remaining Capacity", value: "—")
                    InfoRow(label: "Deep Discharges", value: "—")
                    InfoRow(label: "Serial", value: "—")
                }

                Section("Battery 2") {
                    InfoRow(label: "Charge Cycles", value: "—")
                    InfoRow(label: "Remaining Capacity", value: "—")
                    InfoRow(label: "Deep Discharges", value: "—")
                    InfoRow(label: "Serial", value: "—")
                }

                Section("Charge Status") {
                    InfoRow(label: "Status", value: "Not Connected")
                    InfoRow(label: "Time to Full", value: "—")
                }
            }
            .navigationTitle("Scooter Info")
        }
    }
}
