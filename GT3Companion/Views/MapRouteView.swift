//
//  MapRouteView.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import MapKit
import SwiftUI

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
    let photoAnnotations: [RidePhotoMapAnnotation]
    @State private var selectedPhoto: RidePhotoMapAnnotation?

    init(coordinates: [RouteCoordinate], photoAnnotations: [RidePhotoMapAnnotation] = []) {
        self.coordinates = coordinates
        self.photoAnnotations = photoAnnotations
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
                ForEach(photoAnnotations) { photo in
                    Annotation("Photo", coordinate: CLLocationCoordinate2D(
                        latitude: photo.latitude, longitude: photo.longitude
                    )) {
                        Button {
                            selectedPhoto = photo
                        } label: {
                            if let image = UIImage(data: photo.imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                                    .shadow(radius: 2)
                            } else {
                                Image(systemName: "photo.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(Theme.Colors.accent)
                            }
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
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ContentUnavailableView("Unable to load photo", systemImage: "photo")
                    }
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
