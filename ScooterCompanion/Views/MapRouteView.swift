//
//  MapRouteView.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

#if os(iOS)
import MapKit
import SwiftUI
import UIKit

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

struct MapRouteView: View {
    let coordinates: [RouteCoordinate]
    let ridePhotos: [RidePhotoMapAnnotation]
    @State private var selectedPhoto: RidePhotoMapAnnotation?

    init(coordinates: [RouteCoordinate], ridePhotos: [RidePhotoMapAnnotation] = []) {
        self.coordinates = coordinates
        self.ridePhotos = ridePhotos
    }

    private var segments: [RouteSpeedSegment] {
        routeSpeedSegments(for: coordinates)
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
                    MapPolyline(coordinates: segment.coordinates.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    })
                    .stroke(routeSpeedColor(speed: segment.speed, maxSpeed: maxSpeed), lineWidth: 4)
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
