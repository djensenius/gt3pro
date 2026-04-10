//
//  ContentView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label(
                        "Dashboard",
                        systemImage: "gauge.open.with.lines.needle.33percent.and.arrowtriangle"
                    )
                }
            RideHistoryView()
                .tabItem {
                    Label(
                        "Rides",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                }
            ScooterInfoView()
                .tabItem {
                    Label("Scooter", systemImage: "scooter")
                        .environment(\.layoutDirection, .rightToLeft)
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(Theme.Colors.accent)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    #if os(iOS)
    ContentView()
        .environmentObject(AppCoordinator.shared)
        .modelContainer(PreviewData.container)
    #else
    ContentView()
        .modelContainer(PreviewData.container)
    #endif
}
#endif
