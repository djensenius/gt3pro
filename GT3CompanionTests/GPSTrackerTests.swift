//
//  GPSTrackerTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

#if os(iOS)
import XCTest
@testable import GT3Companion

final class GPSTrackerTests: XCTestCase {
    func testInitialStateIsNotTracking() {
        let tracker = GPSTracker()
        XCTAssertFalse(tracker.isTracking)
    }

    func testInitialLatestSampleIsNil() {
        let tracker = GPSTracker()
        XCTAssertNil(tracker.latestSample)
    }

    func testRequestPermissionsDoesNotCrash() {
        let tracker = GPSTracker()
        tracker.requestPermissions()
    }

    func testStartTrackingSetsIsTracking() {
        let tracker = GPSTracker()
        tracker.startTracking()
        XCTAssertTrue(tracker.isTracking)
        tracker.stopTracking()
    }

    func testStopTrackingClearsIsTracking() {
        let tracker = GPSTracker()
        tracker.startTracking()
        tracker.stopTracking()
        XCTAssertFalse(tracker.isTracking)
    }

    func testDoubleStartTrackingIsIdempotent() {
        let tracker = GPSTracker()
        tracker.startTracking()
        tracker.startTracking()
        XCTAssertTrue(tracker.isTracking)
        tracker.stopTracking()
    }

    func testStopTrackingWhenNotStartedIsNoOp() {
        let tracker = GPSTracker()
        tracker.stopTracking()
        XCTAssertFalse(tracker.isTracking)
    }

    func testGPSSampleInit() {
        let sample = GPSSample(
            timestamp: Date(),
            latitude: 43.65,
            longitude: -79.38,
            altitude: 100.0,
            speed: 5.5,
            course: 180.0,
            horizontalAccuracy: 10.0
        )
        XCTAssertEqual(sample.latitude, 43.65, accuracy: 0.001)
        XCTAssertEqual(sample.longitude, -79.38, accuracy: 0.001)
        XCTAssertEqual(sample.speed, 5.5, accuracy: 0.01)
    }
}
#endif
