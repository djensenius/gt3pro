//
//  DashboardView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct DashboardView: View {
    #if os(iOS)
    @Environment(AppCoordinator.self) private var coordinator
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var photoAttachStatus: String?
    @State private var auth = AuthManager.shared

    private var isDemo: Bool { auth.isDemoMode }
    private var isConnected: Bool { isDemo || coordinator.connectionState == .connected }
    private var isAwake: Bool { isDemo || coordinator.isScooterAwake }
    private var speed: Double { isDemo ? 32.5 : coordinator.currentSpeed }
    private var battery: Int { isDemo ? 78 : coordinator.currentBattery }
    private var tripDistance: Double { isDemo ? 12.4 : coordinator.tripDistance }
    private var estimatedRange: Double { isDemo ? 45 : coordinator.estimatedRange }
    private var gearMode: Int { isDemo ? 2 : coordinator.gearMode }
    private var bmsTemp: Double { isDemo ? 28 : coordinator.bmsTemp }
    private var bodyTemp: Double { isDemo ? 25 : coordinator.bodyTemp }
    #else
    @State private var auth = AuthManager.shared
    private var isDemo: Bool { auth.isDemoMode }
    private var isConnected: Bool { isDemo }
    private var speed: Double { isDemo ? 32.5 : 0 }
    private var battery: Int { isDemo ? 78 : 0 }
    private var tripDistance: Double { isDemo ? 12.4 : 0 }
    private var estimatedRange: Double { isDemo ? 45 : 0 }
    private var gearMode: Int { isDemo ? 2 : 0 }
    private var bmsTemp: Double { isDemo ? 28 : 0 }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()
                ScrollView {
                    if isDemo {
                        demoBanner
                    }
                    if isConnected {
                        if isAwake {
                            connectedView
                        } else {
                            standbyView
                        }
                    } else {
                        disconnectedView
                    }
                }
            }
            .navigationTitle("GT3 Companion")
        }
        #if os(iOS)
        .onChange(of: selectedPhotoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                let successCount = await handleDashboardPhotoSelection(items: newItems)
                await MainActor.run {
                    let failedCount = newItems.count - successCount
                    if failedCount == 0 {
                        photoAttachStatus = newItems.count == 1
                            ? "Photo attached to current ride."
                            : "\(newItems.count) photos attached to current ride."
                    } else if successCount > 0 {
                        photoAttachStatus = "\(successCount) photo(s) attached. \(failedCount) failed."
                    } else {
                        photoAttachStatus = "Could not attach selected photos."
                    }
                    selectedPhotoItems = []
                }
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            RideCameraPicker { image in
                Task {
                    let success = await handleDashboardPhotoSelection(image: image)
                    await MainActor.run {
                        photoAttachStatus = success ? "Photo attached to current ride." : "Could not attach photo."
                    }
                }
            }
            .ignoresSafeArea()
        }
        .ridePhotoStatusAlert($photoAttachStatus)
        #endif
    }

    private var demoBanner: some View {
        Label("Demo Mode", systemImage: "play.circle")
            .font(Theme.Fonts.bodySmall)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.vertical, Theme.Spacing.small)
            .padding(.horizontal, Theme.Spacing.medium)
            .background(Theme.Colors.accent.opacity(0.15))
            .clipShape(Capsule())
            .padding(.top, Theme.Spacing.small)
    }

    private var disconnectedView: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer().frame(height: 60)
            Image(systemName: "scooter")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.textSecondary)
                .environment(\.layoutDirection, .rightToLeft)
            Text("Waiting for GT3 Pro")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Power on your scooter to connect automatically")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            #if os(iOS)
            Button {
                coordinator.retryScan()
            } label: {
                Label("Retry Connection", systemImage: "arrow.clockwise")
                    .font(Theme.Fonts.bodyMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var standbyView: some View {
        VStack(spacing: Theme.Spacing.extraLarge) {
            Spacer().frame(height: 60)
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.accent.opacity(0.6))
            Text("Connected · Standby")
                .font(Theme.Fonts.headerLarge())
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Press the scooter power button to wake up")
                .font(Theme.Fonts.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            #if os(iOS)
            Button {
                coordinator.sendPowerOn()
            } label: {
                Label("Send Power On", systemImage: "power")
                    .font(Theme.Fonts.bodyMedium)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
            #endif
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var connectedView: some View {
        VStack(spacing: Theme.Spacing.large) {
            VStack(spacing: 4) {
                Text("\(Int(speed))")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.accent)
                Text("km/h")
                    .font(Theme.Fonts.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "Battery",
                    value: "\(battery)%",
                    icon: batteryIconName(for: battery),
                    color: batteryColor
                )
                StatCard(
                    title: "Range",
                    value: String(format: "%.0f km", estimatedRange),
                    icon: "fuelpump",
                    color: Theme.Colors.info
                )
            }

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "Trip",
                    value: String(format: "%.1f km", tripDistance),
                    icon: "point.topleft.down.to.point.bottomright.curvepath",
                    color: Theme.Colors.secondary
                )
                StatCard(
                    title: "Mode",
                    value: gearModeName,
                    icon: "gauge.with.dots.needle.33percent",
                    color: Theme.Colors.primary
                )
            }

            HStack(spacing: Theme.Spacing.medium) {
                StatCard(
                    title: "BMS Temp",
                    value: String(format: "%.0f°C", bmsTemp),
                    icon: "thermometer.medium",
                    color: tempColor(bmsTemp)
                )
                StatCard(
                    title: "Vehicle Temp",
                    value: String(format: "%.0f°C", bodyTemp),
                    icon: "thermometer.sun",
                    color: tempColor(bodyTemp)
                )
            }

            #if os(iOS)
            if coordinator.isRiding {
                HStack(spacing: Theme.Spacing.small) {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 10,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Add from Library", systemImage: "photo.on.rectangle")
                            .font(Theme.Fonts.bodySmall)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.small)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.Colors.accent)

                    Button {
                        showCameraPicker = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .font(Theme.Fonts.bodySmall)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.small)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.accent)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                .padding(.horizontal)
            }
            #endif

            #if os(iOS)
            PowerSlideButton(
                title: "Slide to Power Off",
                systemImage: "power",
                color: Theme.Colors.error
            ) {
                coordinator.sendPowerOff()
            }
            .padding(.horizontal)
            #endif
        }
        .padding()
    }

    private var batteryColor: Color {
        if battery > 60 { return Theme.Colors.success }
        if battery > 20 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    private func tempColor(_ temp: Double) -> Color {
        if temp < 45 { return Theme.Colors.success }
        if temp < 60 { return Theme.Colors.warning }
        return Theme.Colors.error
    }

    private var gearModeName: String {
        switch gearMode {
        case 1: return "Walk"
        case 2: return "Eco"
        case 3: return "Sport"
        case 4: return "Race"
        default: return "Mode \(gearMode)"
        }
    }

    #if os(iOS)
    private func handleDashboardPhotoSelection(items: [PhotosPickerItem]) async -> Int {
        var successCount = 0
        for item in items {
            successCount += await handleDashboardPhotoSelection(item: item) ? 1 : 0
        }
        return successCount
    }

    private func handleDashboardPhotoSelection(item: PhotosPickerItem) async -> Bool {
        guard let imageData = await RidePhotoPickerSupport.loadCompressedImageData(from: item) else {
            return false
        }
        return await coordinator.addPhotoToCurrentRide(imageData: imageData)
    }

    private func handleDashboardPhotoSelection(image: UIImage) async -> Bool {
        guard let imageData = RidePhotoPickerSupport.compressJPEGData(from: image) else {
            return false
        }
        return await coordinator.addPhotoToCurrentRide(imageData: imageData)
    }
    #endif
}

#if DEBUG
#Preview {
    #if os(iOS)
    DashboardView()
        .environment(AppCoordinator.shared)
    #else
    DashboardView()
    #endif
}
#endif
