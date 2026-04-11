//
//  MacContentView.swift
//  GT3CompanionMac
//
//  Created by David Jensenius.
//

import SwiftData
import SwiftUI

struct MacContentView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    private enum SidebarItem: String, Hashable {
        case rides, analytics, scooter
    }

    @State private var selectedItem: SidebarItem?
    @State private var selectedRide: PersistedRide?

    private var screenshotTab: String? {
        guard let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot-tab"),
              idx + 1 < ProcessInfo.processInfo.arguments.count else { return nil }
        return ProcessInfo.processInfo.arguments[idx + 1]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                NavigationLink(value: SidebarItem.rides) {
                    Label("Rides", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                NavigationLink(value: SidebarItem.analytics) {
                    Label("Analytics", systemImage: "chart.xyaxis.line")
                }
                NavigationLink(value: SidebarItem.scooter) {
                    Label {
                        Text("Scooter")
                    } icon: {
                        Image(systemName: "scooter")
                            .environment(\.layoutDirection, .rightToLeft)
                    }
                }
            }
            .navigationTitle("GT3 Companion")
        } detail: {
            switch selectedItem {
            case .rides:
                if let ride = selectedRide {
                    MacRideDetailView(ride: ride)
                } else {
                    MacRideListView(rides: rides, selectedRide: $selectedRide)
                }
            case .analytics:
                AggregateAnalyticsView()
            case .scooter:
                ScooterInfoView()
            case nil:
                VStack(spacing: Theme.Spacing.large) {
                    Image(systemName: "scooter")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Colors.accent)
                        .environment(\.layoutDirection, .rightToLeft)

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
        .task {
            if let tab = screenshotTab {
                switch tab {
                case "rides": selectedItem = .rides
                case "analytics": selectedItem = .analytics
                case "scooter": selectedItem = .scooter
                case "ride-detail":
                    selectedItem = .rides
                    try? await Task.sleep(for: .milliseconds(500))
                    selectedRide = rides.first
                default: break
                }
            }
        }
    }
}

struct MacRideListView: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?

    var body: some View {
        List(rides, selection: $selectedRide) { ride in
            MacRideRowView(ride: ride)
                .tag(ride)
        }
        .navigationTitle("Ride History")
        .overlay {
            if rides.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Your rides will appear here after your first trip.")
                )
            }
        }
    }
}

struct MacRideRowView: View {
    let ride: PersistedRide

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ride.startTime, style: .date)
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(String(
                format: "%.1f km · %@ · %.0f km/h max",
                ride.totalDistance,
                ride.formattedDuration,
                ride.maxSpeed
            ))
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct MacRideDetailView: View {
    let ride: PersistedRide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                Text(ride.startTime.formatted(date: .complete, time: .shortened))
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)

                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.large,
                     verticalSpacing: Theme.Spacing.medium) {
                    GridRow {
                        statItem(label: "Distance", value: String(format: "%.1f km", ride.totalDistance))
                        statItem(label: "Duration", value: ride.formattedDuration)
                    }
                    GridRow {
                        statItem(label: "Max Speed", value: String(format: "%.0f km/h", ride.maxSpeed))
                        statItem(label: "Avg Speed", value: String(format: "%.0f km/h", ride.avgSpeed))
                    }
                    GridRow {
                        statItem(label: "Start Battery", value: "\(ride.startBattery)%")
                        statItem(label: "End Battery", value: "\(ride.endBattery ?? 0)%")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}

#if DEBUG
#Preview {
    MacContentView()
        .modelContainer(PreviewData.container)
}
#endif
