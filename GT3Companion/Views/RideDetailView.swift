//
//  RideDetailView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Charts
import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

private struct RideDetailCachedSamples {
    let sorted: [PersistedSample]
    let routes: [RouteCoordinate]
    let speeds: [(Date, Double)]
    let batteries: [(Date, Int)]
    let temps: [RideDetailTempSample]
    #if os(iOS)
    let photos: [RidePhotoDisplay]
    #endif

    init(ride: PersistedRide) {
        let all = (ride.samples ?? []).sorted { $0.timestamp < $1.timestamp }
        self.sorted = all
        self.routes = all
            .filter { $0.latitude != nil && $0.longitude != nil }
            .map { RouteCoordinate(latitude: $0.latitude!, longitude: $0.longitude!, speed: $0.speed) }
        self.speeds = all.map { ($0.timestamp, $0.speed) }
        self.batteries = all.map { ($0.timestamp, $0.battery) }
        self.temps = all.map { RideDetailTempSample(timestamp: $0.timestamp, bms: $0.bmsTemp) }
        #if os(iOS)
        self.photos = ride.sortedPhotos.map { photo in
            RidePhotoDisplay(
                id: photo.photoId,
                createdAt: photo.createdAt,
                imageData: photo.imageData,
                latitude: photo.latitude,
                longitude: photo.longitude
            )
        }
        #endif
    }
}

private struct RideDetailTempSample {
    let timestamp: Date
    let bms: Double
}

#if os(iOS)
private struct RidePhotoDisplay: Identifiable {
    let id: String
    let createdAt: Date
    let imageData: Data
    let latitude: Double?
    let longitude: Double?
}
#endif

struct RideDetailView: View {
    let ride: PersistedRide

    #if os(iOS)
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var showShareSheet = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoAttachStatus: String?
    #endif

    private var cache: RideDetailCachedSamples { RideDetailCachedSamples(ride: ride) }

    #if os(iOS)
    private var photoAnnotations: [RidePhotoMapAnnotation] {
        cache.photos.compactMap { photo in
            guard let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
            return RidePhotoMapAnnotation(
                id: photo.id,
                latitude: latitude,
                longitude: longitude,
                imageData: photo.imageData,
                createdAt: photo.createdAt
            )
        }
    }
    #endif

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: Theme.Spacing.large) {
                    HStack(spacing: Theme.Spacing.medium) {
                        StatCard(
                            title: "Distance",
                            value: String(format: "%.1f km", ride.totalDistance),
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            color: Theme.Colors.accent
                        )
                        StatCard(
                            title: "Duration",
                            value: ride.formattedDuration,
                            icon: "clock",
                            color: Theme.Colors.secondary
                        )
                    }

                    HStack(spacing: Theme.Spacing.medium) {
                        StatCard(
                            title: "Max Speed",
                            value: String(format: "%.0f km/h", ride.maxSpeed),
                            icon: "speedometer",
                            color: Theme.Colors.error
                        )
                        StatCard(
                            title: "Avg Speed",
                            value: String(format: "%.0f km/h", ride.avgSpeed),
                            icon: "gauge.open.with.lines.needle.33percent",
                            color: Theme.Colors.info
                        )
                    }

                    HStack(spacing: Theme.Spacing.medium) {
                        StatCard(
                            title: "Start",
                            value: "\(ride.startBattery)%",
                            icon: batteryIconName(for: ride.startBattery),
                            color: Theme.Colors.success
                        )
                        StatCard(
                            title: "End",
                            value: "\(ride.endBattery ?? 0)%",
                            icon: batteryIconName(for: ride.endBattery ?? 0),
                            color: Theme.Colors.warning
                        )
                    }

                    weatherSection
                    routeSection
                    #if os(iOS)
                    photosSection
                    #endif
                    speedChartSection
                    batteryChartSection
                    tempChartSection
                }
                .padding()
            }
        }
        .navigationTitle(ride.startTime.formatted(date: .abbreviated, time: .omitted))
        .onAppear {
            // Recompute distance from GPS if the stored value looks wrong
            let validGPSSamples = (ride.samples ?? []).filter { sample in
                guard let lat = sample.latitude, let lon = sample.longitude,
                      lat != 0, lon != 0,
                      let acc = sample.horizontalAccuracy, acc > 0,
                      acc < gpsAccuracyThresholdMetres else { return false }
                return true
            }
            if validGPSSamples.count >= 2 && ride.totalDistance < 0.5 {
                ride.recomputeGPSDistance()
            }
        }
        #if os(iOS)
        .toolbar {
            if ride.uploaded {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareRideSheet(rideId: ride.rideId)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let success = await handleRidePhotoSelection(item: newItem)
                await MainActor.run {
                    photoAttachStatus = success ? "Photo added to ride." : "Could not add photo."
                    selectedPhotoItem = nil
                }
            }
        }
        .ridePhotoStatusAlert($photoAttachStatus)
        #endif
    }

    @ViewBuilder
    private var weatherSection: some View {
        if let condition = ride.weatherCondition {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("Weather")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal)

                VStack(spacing: Theme.Spacing.medium) {
                    HStack(spacing: Theme.Spacing.large) {
                        Image(systemName: ride.weatherConditionSymbol ?? weatherSymbol(for: condition))
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(condition.capitalized)
                                .font(Theme.Fonts.bodyMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if let temp = ride.weatherTemp {
                                Text(String(format: "%.0f°C", temp))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                            }
                            if let feelsLike = ride.weatherFeelsLike {
                                Text(String(format: "Feels like %.0f°C", feelsLike))
                                    .font(Theme.Fonts.bodySmall)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: Theme.Spacing.medium) {
                        if let humidity = ride.weatherHumidity {
                            let formatted = String(format: "%.0f%%", humidity)
                            weatherDetail(icon: "humidity.fill", label: "Humidity", value: formatted)
                        }
                        if let windSpeed = ride.weatherWindSpeed {
                            weatherDetail(icon: "wind", label: "Wind", value: String(format: "%.0f km/h", windSpeed))
                        }
                        if let uvIndex = ride.weatherUVIndex {
                            weatherDetail(icon: "sun.max.fill", label: "UV", value: String(format: "%.0f", uvIndex))
                        }
                    }

                    WeatherAttributionView()
                }
                .padding()
                .background(Theme.Colors.elevatedBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .padding(.horizontal)
            }
        }
    }

    private func weatherDetail(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.accent)
            Text(value)
                .font(Theme.Fonts.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Route")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)
            #if os(iOS)
            MapRouteView(
                coordinates: cache.routes,
                ridePhotos: photoAnnotations
            )
                .padding(.horizontal)
            #endif
        }
    }

    #if os(iOS)
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                Text("Photos")
                    .font(Theme.Fonts.headerLarge())
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add", systemImage: "plus")
                        .font(Theme.Fonts.bodySmall)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
            }
            .padding(.horizontal)

            if cache.photos.isEmpty {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 110)
                    .overlay {
                        Text("No photos attached")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Spacing.small) {
                        ForEach(cache.photos) { photo in
                            VStack(alignment: .leading, spacing: 6) {
                                RidePhotoThumbnailView(
                                    imageData: photo.imageData,
                                    cacheKey: photo.id,
                                    width: 110,
                                    height: 110,
                                    cornerRadius: 10
                                )
                                Text(photo.createdAt, style: .time)
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func handleRidePhotoSelection(item: PhotosPickerItem) async -> Bool {
        guard let imageData = await RidePhotoPickerSupport.loadCompressedImageData(from: item) else {
            return false
        }
        return await coordinator.addPhoto(imageData: imageData, to: ride)
    }
    #endif

    private var speedChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Speed")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            if cache.speeds.isEmpty {
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 150)
                    .overlay {
                        Text("No speed data")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal)
            } else {
                Chart {
                    ForEach(cache.speeds, id: \.0) { timestamp, speed in
                        LineMark(
                            x: .value("Time", timestamp),
                            y: .value("Speed", speed)
                        )
                        .foregroundStyle(Theme.Colors.accent)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("km/h")
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private var batteryChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("Battery")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            if cache.batteries.isEmpty {
                noDataPlaceholder(label: "No battery data")
            } else {
                Chart {
                    ForEach(cache.batteries, id: \.0) { timestamp, battery in
                        LineMark(
                            x: .value("Time", timestamp),
                            y: .value("Battery", battery)
                        )
                        .foregroundStyle(Theme.Colors.success)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("%")
                .chartYScale(domain: 0...100)
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private var tempChartSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text("BMS Temperature")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal)

            let hasTempData = cache.temps.contains { $0.bms > 0 }
            if !hasTempData {
                noDataPlaceholder(label: "No temperature data")
            } else {
                Chart {
                    ForEach(cache.temps, id: \.timestamp) { sample in
                        LineMark(
                            x: .value("Time", sample.timestamp),
                            y: .value("BMS", sample.bms),
                            series: .value("Series", "BMS")
                        )
                        .foregroundStyle(Theme.Colors.warning)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(position: .topTrailing)
                .chartXAxis(.hidden)
                .chartYAxisLabel("°C")
                .frame(height: 150)
                .padding(.horizontal)
            }
        }
    }

    private func noDataPlaceholder(label: String) -> some View {
        RoundedRectangle(cornerRadius: Theme.cornerRadius)
            .fill(Theme.Colors.secondaryBackground)
            .frame(height: 150)
            .overlay { Text(label).foregroundStyle(Theme.Colors.textSecondary) }
            .padding(.horizontal)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        RideDetailView(ride: PreviewData.sampleRide)
    }
    .environmentObject(AppCoordinator.shared)
}
#endif
