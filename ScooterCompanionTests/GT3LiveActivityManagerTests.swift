#if os(iOS)
import XCTest
@testable import ScooterCompanion

final class GT3LiveActivityManagerTests: XCTestCase {
    @MainActor
    func testSharedInstanceExists() {
        let manager = GT3LiveActivityManager.shared
        XCTAssertNotNil(manager)
    }

    @MainActor
    func testInitiallyNotActive() {
        let manager = GT3LiveActivityManager.shared
        XCTAssertFalse(manager.isActive)
    }
}
#endif
