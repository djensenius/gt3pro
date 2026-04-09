//
//  VisionContentView.swift
//  GT3CompanionVision
//
//  Created by David Jensenius.
//

import SwiftUI

struct VisionContentView: View {
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
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.accent)

                Text("GT3 Companion")
                    .font(Theme.Fonts.headerXL())

                Text("Explore your ride data in space")
                    .font(Theme.Fonts.bodyMedium)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    VisionContentView()
}
