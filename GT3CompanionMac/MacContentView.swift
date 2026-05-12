//
//  MacContentView.swift
//  GT3CompanionMac
//
//  Created by David Jensenius.
//
// swiftlint:disable file_length

import Charts
import MapKit
import SwiftData
import SwiftUI

struct MacContentView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    enum SidebarItem: String, Hashable {
        case dashboard, rides, analytics, scooter
    }

    @State private var selectedItem: SidebarItem? = .dashboard
    @State private var selectedRide: PersistedRide?

    private var screenshotTab: String? {
        guard let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot-tab"),
              idx + 1 < ProcessInfo.processInfo.arguments.count else { return nil }
        return ProcessInfo.processInfo.arguments[idx + 1]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                NavigationLink(value: SidebarItem.dashboard) {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                }
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
            case .dashboard, nil:
                MacDashboardView(rides: rides, selectedRide: $selectedRide, selectedItem: $selectedItem)
            case .rides:
                MacRideExplorerView(rides: rides, selectedRide: $selectedRide)
            case .analytics:
                AggregateAnalyticsView()
            case .scooter:
                ScooterInfoView()
            }
        }
        .task {
            if selectedRide == nil {
                selectedRide = rides.first
            }
            if let tab = screenshotTab {
                switch tab {
                case "dashboard": selectedItem = .dashboard
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

private struct MacDashboardView: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?
    @Binding var selectedItem: MacContentView.SidebarItem?

    private var totalDistance: Double { rides.reduce(0) { $0 + $1.totalDistance } }
    private var topSpeed: Double { rides.map(\.maxSpeed).max() ?? 0 }
    private var totalHours: Double { rides.reduce(0) { $0 + $1.duration } / 3600 }
    private var latestRide: PersistedRide? { rides.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: Theme.Spacing.medium) {
                    MacMetricCard(title: "Total Distance", value: String(format: "%.0f km", totalDistance),
                                  icon: "point.topleft.down.to.point.bottomright.curvepath",
                                  color: Theme.Colors.accent)
                    MacMetricCard(title: "Rides", value: "\(rides.count)", icon: "number", color: Theme.Colors.info)
                    MacMetricCard(title: "Ride Time", value: String(format: "%.1f hr", totalHours),
                                  icon: "clock", color: Theme.Colors.secondary)
                    MacMetricCard(title: "Top Speed", value: String(format: "%.0f km/h", topSpeed),
                                  icon: "speedometer", color: Theme.Colors.error)
                }

                if let latestRide {
                    MacLatestRideCard(ride: latestRide) {
                        selectedRide = latestRide
                        selectedItem = .rides
                    }
                } else {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                        description: Text("Sign in and sync to explore ride routes, weather, and telemetry.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .glassCard()
                }
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ride Explorer")
                .font(Theme.Fonts.headerXL())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Routes, weather, battery, roughness, and performance from every synced GT3 Pro ride.")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

private struct MacLatestRideCard: View {
    let ride: PersistedRide
    let openRide: () -> Void

    private var presentation: RidePresentation { ride.ridePresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest Ride")
                        .font(Theme.Fonts.headerLarge())
                    Text(ride.startTime.formatted(date: .complete, time: .shortened))
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button("Open Ride", action: openRide)
                    .buttonStyle(.borderedProminent)
            }

            MacRouteMapView(coordinates: presentation.routeCoordinates)
                .frame(height: 260)

            HStack(spacing: Theme.Spacing.medium) {
                MacMetricCard(title: "Distance", value: String(format: "%.1f km", ride.totalDistance),
                              icon: "road.lanes", color: Theme.Colors.accent)
                MacMetricCard(title: "Battery Used", value: "\(ride.batteryUsed)%",
                              icon: batteryIconName(for: ride.endBattery ?? ride.startBattery),
                              color: Theme.Colors.warning)
                MacMetricCard(title: "Weather", value: ride.weatherCondition ?? "Unknown",
                              icon: ride.weatherConditionSymbol ?? weatherSymbol(for: ride.weatherCondition ?? ""),
                              color: Theme.Colors.secondary)
            }
        }
        .glassCard()
    }
}

private struct MacRideExplorerView: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?

    var body: some View {
        HSplitView {
            MacRideListView(rides: rides, selectedRide: $selectedRide)
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            if let selectedRide {
                MacRideDetailView(ride: selectedRide)
                    .frame(minWidth: 620)
            } else {
                ContentUnavailableView(
                    "Select a Ride",
                    systemImage: "map",
                    description: Text("Choose a ride to see route, weather, and telemetry.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Rides")
    }
}

private struct MacRideListView: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?

    var body: some View {
        List(rides, selection: $selectedRide) { ride in
            MacRideRowView(ride: ride)
                .tag(ride)
        }
        .overlay {
            if rides.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Your synced rides will appear here.")
                )
            }
        }
    }
}

private struct MacRideRowView: View {
    let ride: PersistedRide

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ride.startTime, style: .date)
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let condition = ride.weatherCondition {
                    Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            Text(String(format: "%.1f km · %@ · %.0f km/h max",
                        ride.totalDistance, ride.formattedDuration, ride.maxSpeed))
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 4) {
                Image(systemName: batteryIconName(for: ride.endBattery ?? ride.startBattery))
                Text("\(ride.batteryUsed)% battery")
                if ride.samplesHydrated != true {
                    Text("• telemetry pending")
                }
            }
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 6)
    }
}

private struct MacRideDetailView: View {
    let ride: PersistedRide

    @State private var isHydrating = false
    @State private var hydrationFailed = false
    @State private var showShareSheet = false

    private var presentation: RidePresentation { ride.ridePresentation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                detailHeader
                telemetryStatus
                MacRouteMapView(coordinates: presentation.routeCoordinates)
                    .frame(height: 360)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: Theme.Spacing.medium) {
                    MacMetricCard(title: "Distance", value: String(format: "%.1f km", ride.totalDistance),
                                  icon: "road.lanes", color: Theme.Colors.accent)
                    MacMetricCard(title: "Duration", value: ride.formattedDuration,
                                  icon: "clock", color: Theme.Colors.secondary)
                    MacMetricCard(title: "Max Speed", value: String(format: "%.0f km/h", ride.maxSpeed),
                                  icon: "speedometer", color: Theme.Colors.error)
                    MacMetricCard(title: "Avg Speed", value: String(format: "%.0f km/h", ride.avgSpeed),
                                  icon: "gauge.open.with.lines.needle.33percent", color: Theme.Colors.info)
                    MacMetricCard(title: "Battery Used", value: "\(ride.batteryUsed)%",
                                  icon: batteryIconName(for: ride.endBattery ?? ride.startBattery),
                                  color: Theme.Colors.warning)
                    if let averageRoughness = presentation.averageRoughness {
                        MacMetricCard(title: "Avg Roughness", value: String(format: "%.2f", averageRoughness),
                                      icon: "waveform.path.ecg", color: Theme.Colors.primary)
                    }
                    if let averageHeartRate = presentation.averageHeartRate {
                        MacMetricCard(title: "Avg HR", value: "\(averageHeartRate) bpm",
                                      icon: "heart.fill", color: Theme.Colors.error)
                    }
                }

                MacWeatherPanel(ride: ride)
                MacTelemetryCharts(presentation: presentation)
            }
            .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
        .sheet(isPresented: $showShareSheet) {
            RideShareLinkSheet(rideId: ride.rideId)
        }
        .task(id: ride.rideId) {
            await hydrateIfNeeded()
        }
    }

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.startTime.formatted(date: .complete, time: .shortened))
                    .font(Theme.Fonts.headerXL())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Performance, weather, route, and comfort data for this ride.")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if ride.uploaded {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private var telemetryStatus: some View {
        if isHydrating {
            Label("Loading detailed telemetry…", systemImage: "arrow.triangle.2.circlepath")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if hydrationFailed && !presentation.hasTelemetry {
            Label("Detailed telemetry could not be loaded. Ride summary data is still available.",
                  systemImage: "exclamationmark.triangle")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.warning)
        } else if !presentation.hasTelemetry {
            Label("No detailed telemetry is available for this ride yet.", systemImage: "waveform.path")
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func hydrateIfNeeded() async {
        guard ride.samplesHydrated != true, !isHydrating else { return }
        isHydrating = true
        hydrationFailed = false
        let success = await RideSyncService.shared.hydrateRideSamples(for: ride)
        hydrationFailed = !success
        isHydrating = false
    }
}

private struct MacRouteMapView: View {
    let coordinates: [RouteCoordinate]

    private var maxSpeed: Double { coordinates.map(\.speed).max() ?? 1 }

    var body: some View {
        if coordinates.count < 2 {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .overlay {
                    VStack(spacing: Theme.Spacing.small) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                        Text("No route data")
                        Text("GPS samples are missing or below the accuracy threshold.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
        } else {
            Map {
                if let first = coordinates.first {
                    Marker("Start", systemImage: "flag.circle.fill",
                           coordinate: CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude))
                    .tint(Theme.Colors.success)
                }
                if let last = coordinates.last {
                    Marker("End", systemImage: "flag.checkered.circle.fill",
                           coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude))
                    .tint(Theme.Colors.error)
                }
                ForEach(routeSpeedSegments(for: coordinates)) { segment in
                    MapPolyline(coordinates: segment.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(routeSpeedColor(speed: segment.speed, maxSpeed: maxSpeed), lineWidth: 5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}

private struct MacWeatherPanel: View {
    let ride: PersistedRide

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text("Ride Conditions")
                .font(Theme.Fonts.headerLarge())
            if let condition = ride.weatherCondition {
                HStack(spacing: Theme.Spacing.large) {
                    Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                        .font(.system(size: 42))
                        .foregroundStyle(Theme.Colors.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(condition.capitalized)
                            .font(Theme.Fonts.headerLarge())
                        if let temp = ride.weatherTemp {
                            Text(String(format: "%.0f°C", temp))
                                .font(Theme.Fonts.headerXL())
                        }
                    }
                    Spacer()
                    weatherDetail("Humidity", value: ride.weatherHumidity.map { String(format: "%.0f%%", $0) })
                    weatherDetail("Wind", value: ride.weatherWindSpeed.map { String(format: "%.0f km/h", $0) })
                    weatherDetail("UV", value: ride.weatherUVIndex.map { String(format: "%.0f", $0) })
                }
            } else {
                Text("No weather snapshot was saved for this ride.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private func weatherDetail(_ label: String, value: String?) -> some View {
        VStack(alignment: .leading) {
            Text(value ?? "—")
                .font(Theme.Fonts.headerLarge())
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

private struct MacTelemetryCharts: View {
    let presentation: RidePresentation

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320))], spacing: Theme.Spacing.medium) {
            chartCard(title: "Speed", unit: "km/h", samples: presentation.speedSamples,
                      color: Theme.Colors.accent)
            chartCard(title: "Battery", unit: "%", samples: presentation.batterySamples.map {
                ($0.timestamp, Double($0.value))
            }, color: Theme.Colors.success)
            chartCard(title: "BMS Temperature", unit: "°C", samples: presentation.bmsTempSamples,
                      color: Theme.Colors.warning)
            chartCard(title: "Roughness", unit: "", samples: presentation.roughnessSamples,
                      color: Theme.Colors.primary)
        }
    }

    private func chartCard(
        title: String,
        unit: String,
        samples: [(timestamp: Date, value: Double)],
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(title)
                .font(Theme.Fonts.headerLarge())
            if samples.isEmpty {
                Text("No \(title.lowercased()) data")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Chart {
                    ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value(title, sample.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel(unit)
                .frame(height: 180)
            }
        }
        .glassCard()
    }
}

private struct MacMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(title)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .glassCard()
    }
}

#if DEBUG
#Preview {
    MacContentView()
        .modelContainer(PreviewData.container)
}
#endif
