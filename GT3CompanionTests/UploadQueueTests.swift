#if os(iOS)
import XCTest
@testable import GT3Companion

final class UploadQueueTests: XCTestCase {
    func testInitialPendingCountIsZero() async {
        let queue = UploadQueue()
        let count = await queue.getPendingCount()
        XCTAssertEqual(count, 0)
    }

    func testEnqueueIncrementsPendingCount() async {
        let queue = UploadQueue()
        let sample = TelemetrySample(
            timestamp: Date(), speed: 25.0, battery: 80,
            bms1Voltage: 58.0, bms1Current: -10.0, bms1SOC: 80, bms1Temp: 30.0,
            bms2Voltage: 57.0, bms2Current: -10.0, bms2SOC: 78, bms2Temp: 29.0,
            tripDistance: 5.0, tripTime: 600, bodyTemp: 35.0, gearMode: 2,
            estimatedRange: 30.0, errorCode: 0, warnCode: 0,
            regenLevel: 3, speedResponse: 5,
            latitude: nil, longitude: nil, altitude: nil,
            gpsSpeed: nil, gpsCourse: nil, horizontalAccuracy: nil,
            roughnessScore: nil, maxAcceleration: nil, heartRate: nil
        )
        await queue.enqueueSamples([sample])
        let count = await queue.getPendingCount()
        XCTAssertEqual(count, 1)
    }
}
#endif
