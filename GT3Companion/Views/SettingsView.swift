//
//  SettingsView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct SettingsView: View {
    @State private var pollingFrequency: Double = 1.0
    @State private var liveActivityEnabled = true
    @State private var gpsEnabled = true
    @State private var roughnessEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    NavigationLink("Login") {
                        Text("OIDC Login (coming soon)")
                    }
                }

                Section("Scooter") {
                    NavigationLink("Pair Scooter") { PairingView() }
                    Button("Forget Scooter", role: .destructive) { }
                }

                Section("Ride Tracking") {
                    HStack {
                        Text("Polling Frequency")
                        Spacer()
                        Text(String(format: "%.1f Hz", pollingFrequency))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Slider(
                        value: $pollingFrequency,
                        in: 0.5...2.0,
                        step: 0.5
                    )
                    .tint(Theme.Colors.accent)
                    Toggle("GPS Recording", isOn: $gpsEnabled)
                    Toggle("Surface Roughness", isOn: $roughnessEnabled)
                }

                Section("Live Activity") {
                    Toggle(
                        "Show on Dynamic Island",
                        isOn: $liveActivityEnabled
                    )
                }

                Section("Data") {
                    Button("Export Rides (CSV)") { }
                    Button("Export Rides (JSON)") { }
                    Button("Clear Local Data", role: .destructive) { }
                }

                Section("About") {
                    InfoRow(label: "Version", value: "1.0.0")
                    NavigationLink("Privacy Policy") {
                        Text("Privacy details")
                    }
                    NavigationLink("Licenses") {
                        Text("Open source licenses")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
