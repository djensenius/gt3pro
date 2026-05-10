//
//  MapRouteView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import MapKit
import SwiftUI
import UIKit

struct RouteCoordinate {
    let latitude: Double
    let longitude: Double
    let speed: Double
}

struct RidePhotoMapAnnotation: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let imageData: Data
    let createdAt: Date
}

private let ridePhotoImageCache = NSCache<NSString, UIImage>()

struct RidePhotoThumbnailView: View {
    let imageData: Data
    let cacheKey: String
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var image: UIImage?

    init(imageData: Data, cacheKey: String, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
        self.imageData = imageData
        self.cacheKey = cacheKey
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        _image = State(initialValue: ridePhotoImageCache.object(forKey: cacheKey as NSString))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Theme.Colors.secondaryBackground
                    Image(systemName: "photo")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task {
            guard image == nil else { return }
            let decoded = await Task.detached(priority: .utility) {
                UIImage(data: imageData)
            }.value
            if let decoded {
                ridePhotoImageCache.setObject(decoded, forKey: cacheKey as NSString)
            }
            image = decoded
        }
    }
}

/// A segment of consecutive coordinates sharing a similar speed color.
private struct SpeedSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let speed: Double
}

/// Maps a speed ratio (0–1) to an integer color bucket for batching.
private func colorBucket(speed: Double, maxSpeed: Double) -> Int {
    guard maxSpeed > 0 else { return 0 }
    return min(Int(speed / maxSpeed * 10), 10)
}

/// Maps a speed value to a gradient from green (slow) → yellow → red (fast).
private func speedColor(speed: Double, maxSpeed: Double) -> Color {
    guard maxSpeed > 0 else { return Theme.Colors.accent }
    let ratio = min(speed / maxSpeed, 1.0)
    if ratio < 0.5 {
        let progress = ratio / 0.5
        return Color(
            red: progress,
            green: 0.8,
            blue: 0.2 * (1 - progress)
        )
    } else {
        let progress = (ratio - 0.5) / 0.5
        return Color(
            red: 0.9 + 0.1 * progress,
            green: 0.8 * (1 - progress),
            blue: 0
        )
    }
}

struct MapRouteView: View {
    let coordinates: [RouteCoordinate]
    let ridePhotos: [RidePhotoMapAnnotation]
    @State private var selectedPhoto: RidePhotoMapAnnotation?

    init(coordinates: [RouteCoordinate], ridePhotos: [RidePhotoMapAnnotation] = []) {
        self.coordinates = coordinates
        self.ridePhotos = ridePhotos
    }

    private var segments: [SpeedSegment] {
        guard coordinates.count >= 2 else { return [] }
        let max = maxSpeed
        var result: [SpeedSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = []
        var currentBucket = -1
        var currentSpeed = 0.0
        var segmentId = 0

        for idx in 0..<coordinates.count {
            let coord = coordinates[idx]
            let speed = coord.speed
            let bucket = colorBucket(speed: speed, maxSpeed: max)
            let loc = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)

            if bucket != currentBucket && !currentCoords.isEmpty {
                // Close previous segment (share the boundary point)
                result.append(SpeedSegment(id: segmentId, coordinates: currentCoords, speed: currentSpeed))
                segmentId += 1
                currentCoords = [currentCoords.last!]
            }
            currentCoords.append(loc)
            currentBucket = bucket
            currentSpeed = speed
        }
        if currentCoords.count >= 2 {
            result.append(SpeedSegment(id: segmentId, coordinates: currentCoords, speed: currentSpeed))
        }
        return result
    }

    private var maxSpeed: Double {
        coordinates.map(\.speed).max() ?? 1
    }

    var body: some View {
        if coordinates.isEmpty {
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 250)
                .overlay {
                    VStack {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("No GPS data")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
        } else {
            Map {
                if let first = coordinates.first {
                    Annotation("Start", coordinate: CLLocationCoordinate2D(
                        latitude: first.latitude, longitude: first.longitude
                    )) {
                        Image(systemName: "flag.circle.fill")
                            .foregroundStyle(Theme.Colors.success)
                    }
                }
                if let last = coordinates.last, coordinates.count > 1 {
                    Annotation("End", coordinate: CLLocationCoordinate2D(
                        latitude: last.latitude, longitude: last.longitude
                    )) {
                        Image(systemName: "flag.checkered.circle.fill")
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                ForEach(ridePhotos) { photo in
                    Annotation("Photo", coordinate: CLLocationCoordinate2D(
                        latitude: photo.latitude, longitude: photo.longitude
                    )) {
                        Button {
                            selectedPhoto = photo
                        } label: {
                            RidePhotoThumbnailView(
                                imageData: photo.imageData,
                                cacheKey: photo.id,
                                width: 36,
                                height: 36,
                                cornerRadius: 18
                            )
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                ForEach(segments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(speedColor(speed: segment.speed, maxSpeed: maxSpeed), lineWidth: 4)
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .sheet(item: $selectedPhoto) { photo in
                VStack(spacing: Theme.Spacing.medium) {
                    RidePhotoThumbnailView(
                        imageData: photo.imageData,
                        cacheKey: photo.id,
                        width: 320,
                        height: 320,
                        cornerRadius: 12
                    )
                    Text(photo.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.Fonts.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding()
                .presentationDetents([.medium, .large])
            }
        }
    }
}

#if DEBUG
#Preview("With Route") {
    MapRouteView(coordinates: PreviewData.sampleRouteCoordinates.map {
        RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, speed: $0.speed)
    })
        .padding()
}

#Preview("Empty") {
    MapRouteView(coordinates: [])
        .padding()
}
#endif
#endif
