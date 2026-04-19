//
//  WeatherAttributionView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

/// Required Apple Weather attribution link per WeatherKit license.
struct WeatherAttributionView: View {
    var body: some View {
        Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
            Text("Weather data provided by \(Image(systemName: "apple.logo")) Weather")
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }
}

#if DEBUG
#Preview {
    WeatherAttributionView()
        .padding()
}
#endif
