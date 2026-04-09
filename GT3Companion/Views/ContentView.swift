//
//  ContentView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.large) {
                Image(systemName: "scooter")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.accent)

                Text("GT3 Companion")
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Text("Connect to your Segway GT3 Pro")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
        }
    }
}

#Preview {
    ContentView()
}
