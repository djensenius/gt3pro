//
//  SettingsView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage("pollingFrequency") private var pollingFrequency: Double = 1.0
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("gpsEnabled") private var gpsEnabled = true
    @AppStorage("roughnessEnabled") private var roughnessEnabled = true

    @Environment(\.modelContext) private var modelContext
    @Query private var rides: [PersistedRide]
    @StateObject private var logStore = DebugLogStore.shared
    @ObservedObject private var auth = AuthManager.shared

    @State private var showForgetScooterAlert = false
    @State private var showClearDataAlert = false
    @State private var showSignOutAlert = false
    @State private var scooterForgotten = false
    @State private var showLogFileExporter = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                scooterSection
                rideTrackingSection
                liveActivitySection
                dataSection
                debugSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("Settings")
        }
        .fileExporter(
            isPresented: $showLogFileExporter,
            document: logStore.makeFileDocument(),
            contentType: .plainText,
            defaultFilename: logStore.exportFilename
        ) { _ in }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section("Account") {
            if auth.isDemoMode {
                HStack {
                    Label("Demo Mode", systemImage: "play.circle")
                        .foregroundStyle(Theme.Colors.accent)
                    Spacer()
                    Button("Exit Demo") { auth.exitDemoMode() }
                        .foregroundStyle(Theme.Colors.error)
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
            } else {
                HStack {
                    Label("Signed In", systemImage: "person.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Spacer()
                    Button("Sign Out") { showSignOutAlert = true }
                        .foregroundStyle(Theme.Colors.error)
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
            }
        }
        .confirmationDialog("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) { AuthManager.shared.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll need to sign in again to sync rides.")
        }
    }

    private var scooterSection: some View {
        Section("Scooter") {
            NavigationLink("Pair Scooter") { PairingView() }
                .listRowBackground(Theme.Colors.elevatedBackground)

            if ScooterKeychain.hasPassword() && !scooterForgotten {
                Button("Forget Scooter", role: .destructive) { showForgetScooterAlert = true }
                    .listRowBackground(Theme.Colors.elevatedBackground)
            }
        }
        .confirmationDialog("Forget Scooter?", isPresented: $showForgetScooterAlert) {
            Button("Forget", role: .destructive) {
                ScooterKeychain.deletePassword()
                scooterForgotten = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The app will no longer auto-connect. You can re-pair at any time.")
        }
    }

    private var rideTrackingSection: some View {
        Section("Ride Tracking") {
            HStack {
                Text("Polling Frequency")
                Spacer()
                Text(String(format: "%.1f Hz", pollingFrequency))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.elevatedBackground)
            Slider(value: $pollingFrequency, in: 0.5...2.0, step: 0.5)
                .tint(Theme.Colors.accent)
                .listRowBackground(Theme.Colors.elevatedBackground)
            Toggle("GPS Recording", isOn: $gpsEnabled)
                .listRowBackground(Theme.Colors.elevatedBackground)
            Toggle("Surface Roughness", isOn: $roughnessEnabled)
                .listRowBackground(Theme.Colors.elevatedBackground)
        }
    }

    private var liveActivitySection: some View {
        Section("Live Activity") {
            Toggle("Show on Dynamic Island", isOn: $liveActivityEnabled)
                .listRowBackground(Theme.Colors.elevatedBackground)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            if !rides.isEmpty {
                ShareLink(item: exportCSV(), preview: SharePreview("Rides.csv")) {
                    Label("Export Rides (CSV)", systemImage: "tablecells")
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
                ShareLink(item: exportJSON(), preview: SharePreview("Rides.json")) {
                    Label("Export Rides (JSON)", systemImage: "curlybraces")
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
            }
            Button("Clear Local Data", role: .destructive) { showClearDataAlert = true }
                .listRowBackground(Theme.Colors.elevatedBackground)
        }
        .confirmationDialog("Clear Local Data?", isPresented: $showClearDataAlert) {
            Button("Clear", role: .destructive) { clearLocalData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All locally cached rides will be removed. Your data on the server is unaffected.")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle("Verbose Logging", isOn: $logStore.verboseLoggingEnabled)
                .listRowBackground(Theme.Colors.elevatedBackground)
            if !logStore.entries.isEmpty {
                NavigationLink("View Logs (\(logStore.entries.count))") {
                    DebugLogView()
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
                Button {
                    showLogFileExporter = true
                } label: {
                    Label("Save to Files…", systemImage: "folder")
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
                ShareLink(
                    item: logStore.export(),
                    preview: SharePreview("gt3-debug.log")
                ) {
                    Label("Share Logs", systemImage: "square.and.arrow.up")
                }
                .listRowBackground(Theme.Colors.elevatedBackground)
                Button("Clear Logs", role: .destructive) { logStore.clear() }
                    .listRowBackground(Theme.Colors.elevatedBackground)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Verbose logging captures BLE, auth, and upload events. Save to Files to sync via iCloud.")
                .font(Theme.Fonts.caption)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            InfoRow(
                label: "Version",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
            )
            NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                .listRowBackground(Theme.Colors.elevatedBackground)
            NavigationLink("Licenses") { LicensesView() }
                .listRowBackground(Theme.Colors.elevatedBackground)
        }
    }

    // MARK: - Data helpers

    private func clearLocalData() {
        rides.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    private func exportCSV() -> String {
        var csv = "Date,Distance (km),Duration,Max Speed (km/h),Avg Speed (km/h),Battery Used (%)\n"
        for ride in rides {
            csv += "\(ride.startTime.formatted(.iso8601)),"
            csv += "\(String(format: "%.2f", ride.totalDistance)),"
            csv += "\(ride.formattedDuration),"
            csv += "\(String(format: "%.1f", ride.maxSpeed)),"
            csv += "\(String(format: "%.1f", ride.avgSpeed)),"
            csv += "\(ride.batteryUsed)\n"
        }
        return csv
    }

    private func exportJSON() -> String {
        let dicts: [[String: Any]] = rides.map { ride in
            [
                "rideId": ride.rideId,
                "startTime": ride.startTime.formatted(.iso8601),
                "endTime": ride.endTime?.formatted(.iso8601) ?? "",
                "totalDistance": ride.totalDistance,
                "maxSpeed": ride.maxSpeed,
                "avgSpeed": ride.avgSpeed,
                "batteryUsed": ride.batteryUsed,
                "startBattery": ride.startBattery,
                "endBattery": ride.endBattery ?? 0
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: dicts, options: .prettyPrinted),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "[]"
    }
}

// MARK: - Sub-views

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Text("Privacy Policy")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("""
GT3 Companion collects ride telemetry (speed, battery, GPS route) and uploads \
it to your personal FluxHaus server instance at api.fluxhaus.io.

Your data is associated with your FluxHaus account and is never shared with \
third parties. GPS data is only recorded during active rides.

Heart rate data from your Apple Watch is stored locally and in Apple Health. \
It is uploaded to your server only with your consent.

You can delete all local data at any time from Settings → Data → Clear Local Data.
""")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding()
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicensesView: View {
    private let licenses: [(String, String)] = [
        ("Swift", "Apple Inc. — Apache 2.0"),
        ("SwiftUI", "Apple Inc. — Proprietary"),
        ("SwiftData", "Apple Inc. — Proprietary"),
        ("CoreBluetooth", "Apple Inc. — Proprietary"),
        ("CoreLocation", "Apple Inc. — Proprietary"),
        ("HealthKit", "Apple Inc. — Proprietary"),
        ("Charts", "Apple Inc. — Proprietary"),
        ("GT3 Companion", "David Jensenius — Apache 2.0")
    ]

    var body: some View {
        List(licenses, id: \.0) { name, license in
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(license)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, Theme.Spacing.small)
            .listRowBackground(Theme.Colors.elevatedBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Licenses")
    }
}

struct DebugLogView: View {
    @StateObject private var logStore = DebugLogStore.shared
    @State private var showFileExporter = false

    var body: some View {
        List(logStore.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.level.symbol)
                    Text(entry.category)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(levelColor(entry.level))
                    Spacer()
                    Text(entry.timestamp, style: .time)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(entry.message)
                    .font(Theme.Fonts.bodySmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.vertical, 2)
            .listRowBackground(Theme.Colors.elevatedBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("Debug Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showFileExporter = true
                } label: {
                    Image(systemName: "folder")
                }
                ShareLink(
                    item: logStore.export(),
                    preview: SharePreview(logStore.exportFilename)
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: logStore.makeFileDocument(),
            contentType: .plainText,
            defaultFilename: logStore.exportFilename
        ) { _ in }
        .overlay {
            if logStore.entries.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("Enable Verbose Logging to capture events.")
                )
            }
        }
    }

    private func levelColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .debug:   return Theme.Colors.textSecondary
        case .info:    return Theme.Colors.info
        case .warning: return Theme.Colors.warning
        case .error:   return Theme.Colors.error
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Settings") {
    SettingsView()
        .modelContainer(PreviewData.container)
}

#Preview("Privacy Policy") {
    NavigationStack {
        PrivacyPolicyView()
    }
}

#Preview("Licenses") {
    NavigationStack {
        LicensesView()
    }
}

#Preview("Debug Logs") {
    NavigationStack {
        DebugLogView()
    }
}
#endif
