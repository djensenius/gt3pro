//
//  GT3CompanionUITests.swift
//  GT3CompanionUITests
//
//  Created by David Jensenius.
//

import XCTest

@MainActor
final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--screenshot-mode"]
        setupSnapshot(app)

        addUIInterruptionMonitor(withDescription: "System Alert") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists {
                allow.tap()
                return true
            }
            let allowOnce = alert.buttons["Allow Once"]
            if allowOnce.exists {
                allowOnce.tap()
                return true
            }
            let okButton = alert.buttons["OK"]
            if okButton.exists {
                okButton.tap()
                return true
            }
            return false
        }

        app.launch()
        // Trigger the interruption monitor by interacting with the app
        app.swipeUp()
    }

    private func navigateToTab(_ name: String) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 3) {
            tabButton.tap()
        }
    }

    func testDashboardScreenshot() {
        snapshot("01_Dashboard")
    }

    func testRidesScreenshot() {
        navigateToTab("Rides")
        snapshot("02_RideHistory")
    }

    func testRideDetailScreenshot() {
        navigateToTab("Rides")
        let firstRide = app.cells.firstMatch
        if firstRide.waitForExistence(timeout: 3) {
            firstRide.tap()
            snapshot("03_RideDetail")
        }
    }

    func testScooterInfoScreenshot() {
        navigateToTab("Scooter")
        snapshot("04_ScooterInfo")
    }
}
