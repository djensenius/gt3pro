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

/// A segment of 2 consecutive coordinates with an averaged speed for coloring.
private struct SpeedSegment: Identifiable {
    let id: Int
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let speed: Double

    var coordinates: [CLLocationCoordinate2D] { [start, end] }
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

    private var segments: [SpeedSegment] {
        guard coordinates.count >= 2 else { return [] }
        return (0..<coordinates.count - 1).map { index in
            let curr = coordinates[index]
            let next = coordinates[index + 1]
            return SpeedSegment(
                id: index,
                start: CLLocationCoordinate2D(latitude: curr.latitude, longitude: curr.longitude),
                end: CLLocationCoordinate2D(latitude: next.latitude, longitude: next.longitude),
                speed: (curr.speed + next.speed) / 2
            )
        }
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
                ForEach(segments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(speedColor(speed: segment.speed, maxSpeed: maxSpeed), lineWidth: 4)
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
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
