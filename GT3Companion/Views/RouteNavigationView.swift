//
//  RouteNavigationView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import MapKit
import SwiftUI

struct RouteNavigationView: View {
    @StateObject private var navManager = NavigationManager()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if navManager.state.isNavigating {
                    navigationActiveView
                } else {
                    searchView
                }
            }
            .navigationTitle("Navigate")
        }
    }

    private var searchView: some View {
        VStack(spacing: Theme.Spacing.medium) {
            TextField("Search destination", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .onSubmit {
                    Task { await navManager.search(query: searchText) }
                }

            List(navManager.searchResults, id: \.self) { item in
                Button {
                    Task { await navManager.calculateRoute(to: item) }
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.name ?? "Unknown")
                            .font(Theme.Fonts.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let address = item.placemark.title {
                            Text(address)
                                .font(Theme.Fonts.bodySmall)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var navigationActiveView: some View {
        VStack(spacing: Theme.Spacing.medium) {
            if let instruction = navManager.state.nextInstruction {
                HStack {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.title)
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading) {
                        Text(instruction)
                            .font(Theme.Fonts.bodyLarge)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let dist = navManager.state.nextDistance {
                            Text(String(format: "%.0f m", dist))
                                .font(Theme.Fonts.bodySmall)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Spacer()
                }
                .glassCard()
                .padding(.horizontal)
            }

            Map {
                MapPolyline(coordinates: navManager.state.routeCoordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                    .stroke(Theme.Colors.accent, lineWidth: 4)
                UserAnnotation()
            }
            .mapControlVisibility(.visible)

            HStack {
                if let eta = navManager.state.eta {
                    VStack {
                        Text("ETA")
                            .font(Theme.Fonts.caption)
                        Text(eta, style: .time)
                            .font(Theme.Fonts.bodyMedium)
                    }
                }
                Spacer()
                if let remaining = navManager.state.remainingDistance {
                    VStack {
                        Text("Distance")
                            .font(Theme.Fonts.caption)
                        Text(String(format: "%.1f km", remaining / 1000))
                            .font(Theme.Fonts.bodyMedium)
                    }
                }
                Spacer()
                Button("Stop") {
                    navManager.stopNavigation()
                }
                .foregroundStyle(Theme.Colors.error)
            }
            .padding()
            .glassCard()
        }
    }
}

#if DEBUG
#Preview {
    RouteNavigationView()
}
#endif
#endif
