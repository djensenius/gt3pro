//
//  SettingsView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("pollingFrequency") private var pollingFrequency: Double = 1.0
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("gpsEnabled") private var gpsEnabled = true
    @AppStorage("roughnessEnabled") private var roughnessEnabled = true

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
                    Button("Forget Scooter (coming soon)", role: .destructive) { }
                        .disabled(true)
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
                    Button("Export Rides (CSV) — Coming soon") { }
                        .disabled(true)
                    Button("Export Rides (JSON) — Coming soon") { }
                        .disabled(true)
                    Button("Clear Local Data — Coming soon", role: .destructive) { }
                        .disabled(true)
                }

                Section("About") {
                    InfoRow(
                        label: "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                    )
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
