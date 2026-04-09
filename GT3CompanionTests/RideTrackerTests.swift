//
//  RideTrackerTests.swift
//  GT3CompanionTests
//
//  Created by David Jensenius.
//

#if os(iOS)
import XCTest
@testable import GT3Companion

final class RideTrackerTests: XCTestCase {
    private func makeSample(
        speed: Double = 0,
        battery: Int = 90,
        tripDistance: Double = 0
    ) -> TelemetrySample {
        TelemetrySample(
            timestamp: Date(),
            speed: speed,
            battery: battery,
            bms1Voltage: 58.0,
            bms1Current: -12.0,
            bms1SOC: 80,
            bms1Temp: 25.0,
            bms2Voltage: 58.0,
            bms2Current: -12.0,
            bms2SOC: 80,
            bms2Temp: 25.0,
            tripDistance: tripDistance,
            tripTime: 600,
            bodyTemp: 30.0,
            gearMode: 2,
            estimatedRange: 40.0,
            errorCode: 0,
            warnCode: 0,
            regenLevel: 3,
            speedResponse: 5,
            latitude: nil,
            longitude: nil,
            altitude: nil,
            gpsSpeed: nil,
            gpsCourse: nil,
            horizontalAccuracy: nil,
            roughnessScore: nil,
            maxAcceleration: nil,
            heartRate: nil
        )
    }

    func testInitialStateIsIdle() async {
        let tracker = RideTracker()
        let state = await tracker.state
        XCTAssertEqual(state, .idle)
    }

    func testRideStartsOnSpeedGreaterThanZero() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        let state = await tracker.state
        XCTAssertEqual(state, .riding)
    }

    func testRideDoesNotStartOnZeroSpeed() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 0))
        let state = await tracker.state
        XCTAssertEqual(state, .idle)
    }

    func testRideIdAssignedOnStart() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 10.0))
        let rideId = await tracker.getCurrentRideId()
        XCTAssertNotNil(rideId)
    }

    func testSampleCollectionDuringRide() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.addSample(makeSample(speed: 20.0))
        await tracker.addSample(makeSample(speed: 25.0))
        let count = await tracker.getSampleCount()
        XCTAssertEqual(count, 3)
    }

    func testRideTransitionsToStoppedOnZeroSpeed() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.addSample(makeSample(speed: 0))
        let state = await tracker.state
        XCTAssertEqual(state, .stopped)
    }

    func testRideResumesFromStopped() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.addSample(makeSample(speed: 0))
        await tracker.addSample(makeSample(speed: 10.0))
        let state = await tracker.state
        XCTAssertEqual(state, .riding)
    }

    func testForceEndRideReturnsToIdle() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0, battery: 90))
        await tracker.forceEndRide(endBattery: 85)
        let state = await tracker.state
        XCTAssertEqual(state, .idle)
    }

    func testForceEndRideClearsRideId() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.forceEndRide(endBattery: 85)
        let rideId = await tracker.getCurrentRideId()
        XCTAssertNil(rideId)
    }

    func testForceEndRideWhenIdleIsNoOp() async {
        let tracker = RideTracker()
        await tracker.forceEndRide(endBattery: 85)
        let state = await tracker.state
        XCTAssertEqual(state, .idle)
    }

    func testForceEndRideFromStoppedState() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.addSample(makeSample(speed: 0))
        let stoppedState = await tracker.state
        XCTAssertEqual(stoppedState, .stopped)
        await tracker.forceEndRide(endBattery: 80)
        let finalState = await tracker.state
        XCTAssertEqual(finalState, .idle)
    }

    func testRideCompletionCallbackFires() async {
        let tracker = RideTracker()
        let expectation = XCTestExpectation(description: "Ride completed")

        let sample1 = makeSample(speed: 15.0, battery: 90)
        let sample2 = makeSample(speed: 25.0, battery: 87)

        await tracker.setCallback { rideLog in
            XCTAssertGreaterThan(rideLog.maxSpeed, 0)
            XCTAssertEqual(rideLog.startBattery, 90)
            XCTAssertEqual(rideLog.endBattery, 85)
            expectation.fulfill()
        }
        await tracker.addSample(sample1)
        await tracker.addSample(sample2)
        await tracker.forceEndRide(endBattery: 85)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSampleCountResetsAfterRideEnd() async {
        let tracker = RideTracker()
        await tracker.addSample(makeSample(speed: 15.0))
        await tracker.addSample(makeSample(speed: 20.0))
        await tracker.forceEndRide(endBattery: 85)
        let count = await tracker.getSampleCount()
        XCTAssertEqual(count, 0)
    }
}

private extension RideTracker {
    func setCallback(_ callback: @escaping @Sendable (RideLog) -> Void) {
        self.onRideComplete = callback
    }
}
#endif
