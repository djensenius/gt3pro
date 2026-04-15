//
//  GeoUtilsTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

import XCTest
@testable import GT3Companion

final class GeoUtilsTests: XCTestCase {
    func testZeroDistanceReturnZero() {
        let dist = haversineDistanceKm(lat1: 40.0, lon1: -74.0, lat2: 40.0, lon2: -74.0)
        XCTAssertEqual(dist, 0.0, accuracy: 1e-10)
    }

    func testNYCToLA() {
        // NYC (40.7128, -74.0060) → LA (34.0522, -118.2437) ≈ 3944 km
        let dist = haversineDistanceKm(
            lat1: 40.7128, lon1: -74.0060,
            lat2: 34.0522, lon2: -118.2437
        )
        XCTAssertEqual(dist, 3944, accuracy: 10)
    }

    func testShortDistance() {
        // ~111 m apart (0.001° latitude at equator ≈ 111 m)
        let dist = haversineDistanceKm(lat1: 0.0, lon1: 0.0, lat2: 0.001, lon2: 0.0)
        XCTAssertEqual(dist, 0.111, accuracy: 0.002)
    }

    func testEarthRadiusConstant() {
        XCTAssertEqual(earthRadiusKm, 6371.0)
    }

    func testAccuracyThresholdConstant() {
        XCTAssertEqual(gpsAccuracyThresholdMetres, 50.0)
    }
}
