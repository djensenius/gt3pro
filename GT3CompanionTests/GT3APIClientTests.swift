#if os(iOS)
import XCTest
@testable import GT3Companion

final class GT3APIClientTests: XCTestCase {
    func testClientExists() async {
        let client = GT3APIClient()
        // Basic existence test - actual HTTP tests need mock server
        XCTAssertNotNil(client)
    }
}
#endif
