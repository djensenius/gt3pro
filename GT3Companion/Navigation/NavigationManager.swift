//
//  NavigationManager.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

#if os(iOS)
import Foundation
import MapKit
import os

private let logger = Logger(subsystem: "io.fluxhaus.GT3Companion", category: "Navigation")

/// Navigation state for turn-by-turn directions.
struct NavigationState: Sendable {
    let isNavigating: Bool
    let nextInstruction: String?
    let nextDistance: Double?
    let eta: Date?
    let remainingDistance: Double?
    let routePolyline: [CLLocationCoordinate2D]
}

/// MapKit-based turn-by-turn navigation manager.
@MainActor
class NavigationManager: ObservableObject {
    @Published var state = NavigationState(
        isNavigating: false, nextInstruction: nil,
        nextDistance: nil, eta: nil, remainingDistance: nil,
        routePolyline: []
    )
    @Published var searchResults: [MKMapItem] = []

    private var currentRoute: MKRoute?
    private var currentStepIndex = 0

    /// Search for a destination.
    func search(query: String) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query

        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            searchResults = response.mapItems
        } catch {
            logger.error("Search failed: \(error.localizedDescription)")
            searchResults = []
        }
    }

    /// Calculate route to destination.
    func calculateRoute(to destination: MKMapItem) async {
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = destination
        request.transportType = .automobile

        do {
            let directions = MKDirections(request: request)
            let response = try await directions.calculate()
            guard let route = response.routes.first else { return }

            currentRoute = route
            currentStepIndex = 0

            let firstStep = route.steps.first
            let polylinePoints = route.polyline.points()
            let pointCount = route.polyline.pointCount
            var coords: [CLLocationCoordinate2D] = []
            for idx in 0..<pointCount {
                coords.append(polylinePoints[idx].coordinate)
            }

            state = NavigationState(
                isNavigating: true,
                nextInstruction: firstStep?.instructions,
                nextDistance: firstStep?.distance,
                eta: route.expectedTravelTime > 0
                    ? Date().addingTimeInterval(route.expectedTravelTime) : nil,
                remainingDistance: route.distance,
                routePolyline: coords
            )
            logger.info("Route calculated: \(route.distance)m, ETA: \(route.expectedTravelTime)s")
        } catch {
            logger.error("Route calculation failed: \(error.localizedDescription)")
        }
    }

    /// Stop navigation.
    func stopNavigation() {
        currentRoute = nil
        currentStepIndex = 0
        state = NavigationState(
            isNavigating: false, nextInstruction: nil,
            nextDistance: nil, eta: nil, remainingDistance: nil,
            routePolyline: []
        )
    }
}
#endif
