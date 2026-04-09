//
//  MacContentView.swift
//  GT3CompanionMac
//
//  Created by David Jensenius.
//

import SwiftUI

struct MacContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: Text("Ride History")) {
                    Label("Rides", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                NavigationLink(destination: Text("Analytics")) {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
                NavigationLink(destination: Text("Scooter Info")) {
                    Label("Scooter", systemImage: "scooter")
                }
            }
            .navigationTitle("GT3 Companion")
        } detail: {
            VStack(spacing: Theme.Spacing.large) {
                Image(systemName: "scooter")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent)

                Text("GT3 Companion")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Select a section to explore your ride data")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    MacContentView()
}
