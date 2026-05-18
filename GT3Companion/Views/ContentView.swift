//
//  ContentView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI

/// Forces tab-bar-only style in screenshot mode so iPad uses the same tab bar as iPhone.
private struct ScreenshotTabBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.arguments.contains("--screenshot-mode") {
            content.tabViewStyle(.tabBarOnly)
        } else {
            content.tabViewStyle(.sidebarAdaptable)
        }
    }
}

struct ContentView: View {
    #if os(iOS)
    /// SF Symbol "scooter" faces left by default; mirror it so it faces right.
    private static let flippedScooterImage: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
        guard let base = UIImage(systemName: "scooter", withConfiguration: config),
              let cgImage = base.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: base.scale, orientation: .upMirrored)
            .withRenderingMode(.alwaysTemplate)
    }()
    #endif

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
                    #if os(iOS)
                    if let img = Self.flippedScooterImage {
                        Image(uiImage: img)
                    } else {
                        Image(systemName: "scooter")
                    }
                    #else
                    Image(systemName: "scooter")
                    #endif
                    Text("Scooter")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .modifier(ScreenshotTabBarModifier())
        .tint(Theme.Colors.accent)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

#if DEBUG
#Preview {
    #if os(iOS)
    ContentView()
        .environment(AppCoordinator.shared)
        .modelContainer(PreviewData.container)
    #else
    ContentView()
        .modelContainer(PreviewData.container)
    #endif
}
#endif
