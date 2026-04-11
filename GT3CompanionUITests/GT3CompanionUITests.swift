//
//  GT3CompanionUITests.swift
//  GT3CompanionUITests
//
//  Created by David Jensenius.
//

import XCTest

final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--screenshot-mode"]
        setupSnapshot(app)
        app.launch()
    }

    func testDashboardScreenshot() {
        snapshot("01_Dashboard")
    }

    func testRidesScreenshot() {
        app.tabBars.buttons["Rides"].tap()
        snapshot("02_RideHistory")
    }

    func testRideDetailScreenshot() {
        app.tabBars.buttons["Rides"].tap()
        // Tap the first ride in the list
        let firstRide = app.cells.firstMatch
        if firstRide.waitForExistence(timeout: 3) {
            firstRide.tap()
            snapshot("03_RideDetail")
        }
    }

    func testScooterInfoScreenshot() {
        app.tabBars.buttons["Scooter"].tap()
        snapshot("04_ScooterInfo")
    }
}
