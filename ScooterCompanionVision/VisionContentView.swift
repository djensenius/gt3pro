//
//  VisionContentView.swift
//  ScooterCompanionVision
//
//  Created by David Jensenius.
//
// swiftlint:disable file_length

import Charts
import MapKit
import RealityKit
import SwiftData
import SwiftUI

struct VisionContentView: View {
    @Query(sort: \PersistedRide.startTime, order: .reverse) private var rides: [PersistedRide]

    enum SidebarItem: String, Hashable {
        case gallery, rides, analytics, scooter
    }

    @State private var selectedItem: SidebarItem? = .gallery
    @State private var selectedRide: PersistedRide?

    private var screenshotTab: String? {
        guard let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "--screenshot-tab"),
              idx + 1 < ProcessInfo.processInfo.arguments.count else { return nil }
        return ProcessInfo.processInfo.arguments[idx + 1]
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                NavigationLink(value: SidebarItem.gallery) {
                    Label("Gallery", systemImage: "sparkles.rectangle.stack")
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
            .navigationTitle("Scooter Companion")
        } detail: {
            switch selectedItem {
            case .gallery, nil:
                VisionRideGalleryView(rides: rides, selectedRide: $selectedRide, selectedItem: $selectedItem)
            case .rides:
                VisionRideDetailScene(rides: rides, selectedRide: $selectedRide)
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
                case "gallery": selectedItem = .gallery
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

private struct VisionRideGalleryView: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?
    @Binding var selectedItem: VisionContentView.SidebarItem?

    private var latestRide: PersistedRide? { rides.first }
    private var totalDistance: Double { rides.reduce(0) { $0 + $1.totalDistance } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.extraLarge) {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Explore your rides in space")
                        .font(Theme.Fonts.headerXL())
                    Text("Routes, weather, telemetry, and comfort signals presented as a spatial ride gallery.")
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                if let latestRide {
                    VisionHeroRideCard(ride: latestRide) {
                        selectedRide = latestRide
                        selectedItem = .rides
                    }
                } else {
                    ContentUnavailableView(
                        "No Rides Yet",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text("Sign in and sync rides to fill the spatial gallery.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .glassCard()
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: Theme.Spacing.medium) {
                    VisionMetricCard(title: "Rides", value: "\(rides.count)", icon: "number", color: Theme.Colors.info)
                    VisionMetricCard(title: "Distance", value: String(format: "%.0f km", totalDistance),
                                     icon: "point.topleft.down.to.point.bottomright.curvepath",
                                     color: Theme.Colors.accent)
                    VisionMetricCard(title: "Top Speed",
                                     value: String(format: "%.0f km/h", rides.map(\.maxSpeed).max() ?? 0),
                                     icon: "speedometer",
                                     color: Theme.Colors.error)
                }
            }
            .padding(32)
        }
        .navigationTitle("Ride Gallery")
    }
}

private struct VisionHeroRideCard: View {
    let ride: PersistedRide
    let openRide: () -> Void

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var isOpeningSpace = false

    var body: some View {
        let presentation = ride.ridePresentation

        VStack(alignment: .leading, spacing: Theme.Spacing.large) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Featured Ride")
                        .font(Theme.Fonts.headerLarge())
                    Text(ride.startTime.formatted(date: .complete, time: .shortened))
                        .font(Theme.Fonts.bodyMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                Button("Open Detail", action: openRide)
                    .buttonStyle(.gt3Primary)
                    .frame(width: 180)
                Button {
                    Task {
                        isOpeningSpace = true
                        _ = await openImmersiveSpace(id: "RideRouteSpace")
                        isOpeningSpace = false
                    }
                } label: {
                    Label(isOpeningSpace ? "Opening…" : "Route Space", systemImage: "visionpro")
                }
                .buttonStyle(.gt3Primary)
                .frame(width: 190)
            }

            VisionRouteMapView(coordinates: presentation.routeCoordinates)
                .frame(height: 360)

            HStack(spacing: Theme.Spacing.medium) {
                VisionMetricCard(title: "Distance", value: String(format: "%.1f km", ride.totalDistance),
                                 icon: "road.lanes", color: Theme.Colors.accent)
                VisionMetricCard(title: "Weather", value: ride.weatherCondition ?? "Unknown",
                                 icon: ride.weatherConditionSymbol ?? weatherSymbol(for: ride.weatherCondition ?? ""),
                                 color: Theme.Colors.secondary)
                VisionMetricCard(title: "Battery", value: "\(ride.batteryUsed)% used",
                                 icon: batteryIconName(for: ride.endBattery ?? ride.startBattery),
                                 color: Theme.Colors.warning)
            }
        }
        .glassCard()
        .hoverEffect()
    }
}

private struct VisionRideDetailScene: View {
    let rides: [PersistedRide]
    @Binding var selectedRide: PersistedRide?

    var body: some View {
        HStack(spacing: Theme.Spacing.extraLarge) {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.medium) {
                    ForEach(rides) { ride in
                        VisionRideTile(ride: ride, isSelected: ride == selectedRide)
                            .onTapGesture {
                                selectedRide = ride
                            }
                    }
                }
                .padding()
            }
            .frame(width: 320)

            if let selectedRide {
                VisionRideDetailView(ride: selectedRide)
            } else {
                ContentUnavailableView(
                    "Select a Ride",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("Choose a ride card to expand its route, weather, and telemetry.")
                )
            }
        }
        .padding()
        .navigationTitle("Rides")
    }
}

private struct VisionRideTile: View {
    let ride: PersistedRide
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(ride.startTime, style: .date)
                .font(Theme.Fonts.bodyMedium)
            Text(String(format: "%.1f km", ride.totalDistance))
                .font(Theme.Fonts.headerLarge())
            Text(String(format: "%.0f km/h max", ride.maxSpeed))
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
            if let condition = ride.weatherCondition {
                Label(condition.capitalized, systemImage: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .frame(width: 220, alignment: .leading)
        .padding()
        .background(isSelected ? Theme.Colors.elevatedBackground : Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .hoverEffect()
    }
}

private struct VisionRideDetailView: View {
    let ride: PersistedRide

    @State private var isHydrating = false
    @State private var hydrationFailed = false
    @State private var showShareSheet = false

    var body: some View {
        let presentation = ride.ridePresentation

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride.startTime.formatted(date: .complete, time: .shortened))
                            .font(Theme.Fonts.headerXL())
                        Text("A spatial ride story with route, weather, telemetry, and comfort signals.")
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
                        .buttonStyle(.gt3Primary)
                        .frame(width: 160)
                    }
                    telemetryStatus(presentation: presentation)
                }

                VisionRouteMapView(coordinates: presentation.routeCoordinates)
                    .frame(height: 420)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: Theme.Spacing.medium) {
                    VisionMetricCard(title: "Distance", value: String(format: "%.1f km", ride.totalDistance),
                                     icon: "road.lanes", color: Theme.Colors.accent)
                    VisionMetricCard(title: "Duration", value: ride.formattedDuration,
                                     icon: "clock", color: Theme.Colors.secondary)
                    VisionMetricCard(title: "Max Speed", value: String(format: "%.0f km/h", ride.maxSpeed),
                                     icon: "speedometer", color: Theme.Colors.error)
                    VisionMetricCard(title: "Battery Used", value: "\(ride.batteryUsed)%",
                                     icon: batteryIconName(for: ride.endBattery ?? ride.startBattery),
                                     color: Theme.Colors.warning)
                    if let roughness = presentation.averageRoughness {
                        VisionMetricCard(title: "Roughness", value: String(format: "%.2f avg", roughness),
                                         icon: "waveform.path.ecg", color: Theme.Colors.primary)
                    }
                    if let heartRate = presentation.averageHeartRate {
                        VisionMetricCard(title: "Heart Rate", value: "\(heartRate) bpm avg",
                                         icon: "heart.fill", color: Theme.Colors.error)
                    }
                }

                VisionWeatherPanel(ride: ride)
                VisionTelemetryCharts(presentation: presentation)
            }
            .padding(24)
        }
        .task(id: ride.rideId) {
            await hydrateIfNeeded()
        }
        .sheet(isPresented: $showShareSheet) {
            RideShareLinkSheet(rideId: ride.rideId)
        }
    }

    @ViewBuilder
    private func telemetryStatus(presentation: RidePresentation) -> some View {
        if isHydrating {
            Label("Loading telemetry", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if hydrationFailed && !presentation.hasTelemetry {
            Label("Telemetry unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(Theme.Colors.warning)
        } else if !presentation.hasTelemetry {
            Label("Summary only", systemImage: "waveform.path")
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

private struct VisionRouteMapView: View {
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
                    .stroke(routeSpeedColor(speed: segment.speed, maxSpeed: maxSpeed), lineWidth: 7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
    }
}

private struct VisionWeatherPanel: View {
    let ride: PersistedRide

    var body: some View {
        HStack(spacing: Theme.Spacing.large) {
            if let condition = ride.weatherCondition {
                Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.Colors.accent)
                VStack(alignment: .leading) {
                    Text(condition.capitalized)
                        .font(Theme.Fonts.headerLarge())
                    if let temp = ride.weatherTemp {
                        Text(String(format: "%.0f°C", temp))
                            .font(Theme.Fonts.headerXL())
                    }
                }
                Spacer()
                VisionWeatherDetail(label: "Wind", value: ride.weatherWindSpeed.map { String(format: "%.0f km/h", $0) })
                VisionWeatherDetail(label: "Humidity", value: ride.weatherHumidity.map { String(format: "%.0f%%", $0) })
                VisionWeatherDetail(label: "UV", value: ride.weatherUVIndex.map { String(format: "%.0f", $0) })
            } else {
                Text("No weather snapshot saved for this ride.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .glassCard()
    }
}

private struct VisionWeatherDetail: View {
    let label: String
    let value: String?

    var body: some View {
        VStack {
            Text(value ?? "—")
                .font(Theme.Fonts.headerLarge())
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

private struct VisionTelemetryCharts: View {
    let presentation: RidePresentation

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320))], spacing: Theme.Spacing.medium) {
            chartCard(title: "Speed", unit: "km/h", samples: presentation.speedSamples,
                      color: Theme.Colors.accent)
            chartCard(title: "Battery", unit: "%", samples: presentation.batterySamples.map {
                ($0.timestamp, Double($0.value))
            }, color: Theme.Colors.success)
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
                    .frame(maxWidth: .infinity, minHeight: 170)
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
                .frame(height: 170)
            }
        }
        .glassCard()
    }
}

private struct VisionMetricCard: View {
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
            Text(title)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .glassCard()
        .hoverEffect()
    }
}

#if DEBUG
#Preview {
    VisionContentView()
        .modelContainer(PreviewData.container)
}
#endif

struct VisionRouteImmersiveConceptView: View {
    var body: some View {
        RealityView { content in
            let root = Entity()
            let routeMaterial = SimpleMaterial(color: .cyan, roughness: 0.25, isMetallic: false)
            let startMaterial = SimpleMaterial(color: .green, roughness: 0.2, isMetallic: false)
            let endMaterial = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: false)

            for index in 0..<14 {
                let progress = Float(index) / 13.0
                let point = ModelEntity(
                    mesh: .generateSphere(radius: index == 0 || index == 13 ? 0.045 : 0.025),
                    materials: [index == 0 ? startMaterial : (index == 13 ? endMaterial : routeMaterial)]
                )
                point.position = SIMD3<Float>(
                    -0.75 + progress * 1.5,
                    sin(progress * Float.pi * 2) * 0.18,
                    -1.25 - cos(progress * Float.pi) * 0.25
                )
                root.addChild(point)
            }

            content.add(root)
        }
    }
}
