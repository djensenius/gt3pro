//
//  WeatherAttributionView.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import SwiftUI

/// Required Apple Weather attribution link per WeatherKit license.
struct WeatherAttributionView: View {
    private static let attributionURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")

    var body: some View {
        Group {
            if let url = Self.attributionURL {
                Link(destination: url) {
                    attributionLabel
                }
            } else {
                attributionLabel
            }
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private var attributionLabel: some View {
        Text("Weather data provided by \(Image(systemName: "apple.logo")) Weather")
    }
}

#if DEBUG
#Preview {
    WeatherAttributionView()
        .padding()
}
#endif
