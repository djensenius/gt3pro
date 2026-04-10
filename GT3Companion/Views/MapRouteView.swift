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

struct MapRouteView: View {
    let coordinates: [RouteCoordinate]

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
                MapPolyline(coordinates: coordinates.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                })
                .stroke(Theme.Colors.accent, lineWidth: 4)
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
