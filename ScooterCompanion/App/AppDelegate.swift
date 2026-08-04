//
//  AppDelegate.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

#if os(iOS)
import UIKit
import UserNotifications
import os

private let logger = Logger(subsystem: "org.davidjensenius.GT3Companion", category: "AppDelegate")

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                logger.error("Notification auth error: \(error)")
            }
            logger.info("Notification auth granted: \(granted)")
        }

        // If launched by BLE state restoration, bootstrap the coordinator early
        if launchOptions?[.bluetoothCentrals] != nil {
            logger.info("Launched via BLE state restoration")
            Task { @MainActor in
                DebugLogStore.shared.log(
                    "Cold launch via BLE state restoration — bootstrapping coordinator",
                    category: "BLE", level: .warning
                )
                let coordinator = AppCoordinator.shared
                coordinator.start(storedPassword: ScooterKeychain.loadPassword())
            }
        } else {
            Task { @MainActor in
                DebugLogStore.shared.log("Cold launch (normal, not BLE restoration)", category: "BLE", level: .debug)
            }
        }

        return true
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
#endif
