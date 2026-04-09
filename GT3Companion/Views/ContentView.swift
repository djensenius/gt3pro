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
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(Theme.Colors.accent)
    }
}

#Preview {
    ContentView()
}
