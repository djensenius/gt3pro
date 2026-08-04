import XCTest
@testable import ScooterCompanionMac

final class BatteryIconMacTests: XCTestCase {
    func testBatteryIconEmpty() {
        XCTAssertEqual(batteryIconName(for: 0), "battery.0percent")
        XCTAssertEqual(batteryIconName(for: 5), "battery.0percent")
        XCTAssertEqual(batteryIconName(for: 12), "battery.0percent")
    }

    func testBatteryIconQuarter() {
        XCTAssertEqual(batteryIconName(for: 13), "battery.25percent")
        XCTAssertEqual(batteryIconName(for: 25), "battery.25percent")
        XCTAssertEqual(batteryIconName(for: 37), "battery.25percent")
    }

    func testBatteryIconHalf() {
        XCTAssertEqual(batteryIconName(for: 38), "battery.50percent")
        XCTAssertEqual(batteryIconName(for: 50), "battery.50percent")
        XCTAssertEqual(batteryIconName(for: 62), "battery.50percent")
    }

    func testBatteryIconThreeQuarter() {
        XCTAssertEqual(batteryIconName(for: 63), "battery.75percent")
        XCTAssertEqual(batteryIconName(for: 75), "battery.75percent")
        XCTAssertEqual(batteryIconName(for: 87), "battery.75percent")
    }

    func testBatteryIconFull() {
        XCTAssertEqual(batteryIconName(for: 88), "battery.100percent")
        XCTAssertEqual(batteryIconName(for: 100), "battery.100percent")
    }

    func testBatteryIconClampedValues() {
        XCTAssertEqual(batteryIconName(for: -5), "battery.0percent")
        XCTAssertEqual(batteryIconName(for: 150), "battery.100percent")
    }
}
