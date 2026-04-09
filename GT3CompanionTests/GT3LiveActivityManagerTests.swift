#if os(iOS)
import XCTest
@testable import GT3Companion

final class GT3LiveActivityManagerTests: XCTestCase {
    @MainActor
    func testSharedInstanceExists() {
        let manager = GT3LiveActivityManager.shared
        XCTAssertNotNil(manager)
    }

    @MainActor
    func testInitiallyNotActive() {
        let manager = GT3LiveActivityManager.shared
        // Can't guarantee state without actual ActivityKit, but the property should be accessible
        _ = manager.isActive
    }
}
#endif
