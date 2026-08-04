//
//  AppCoordinator+Telemetry.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

#if os(iOS)

// MARK: - Telemetry Value Routing

extension AppCoordinator {
    /// Route a register read result to the appropriate published property.
    /// Returns the battery value if this was a battery register update.
    func updatePublishedValue(for result: RegisterReadResult) -> Int? {
        let battery = updateDashboardValues(for: result)
        updateInfoValues(for: result)
        return battery
    }

    /// Returns battery value if the result is rBattery, nil otherwise.
    private func updateDashboardValues(for result: RegisterReadResult) -> Int? {
        switch result.name {
        case "rSpeed":            currentSpeed = result.doubleValue ?? 0
        case "rBattery":          return result.intValue ?? 0
        case "rSingleMileage":    scooterTripDistance = result.doubleValue ?? 0
        case "rLeftMileage":      estimatedRange = result.doubleValue ?? 0
        case "rGearMode":         gearMode = result.intValue ?? 0
        case "rBmsTmp2":          bmsTemp = result.doubleValue ?? 0
        case "rBodyTemp":         bodyTemp = result.doubleValue ?? 0
        case "rBMSVolt2":        bmsVoltage = result.doubleValue ?? 0
        case "rBMSCur2":         bmsCurrent = result.doubleValue ?? 0
        default:                  break
        }
        return nil
    }

    private func updateInfoValues(for result: RegisterReadResult) {
        switch result.name {
        case "rPreciseMileage":    odometer = result.doubleValue ?? 0
        case "rMileage":
            if odometer == 0 { odometer = result.doubleValue ?? 0 }
        case "rRideTime":         totalRideTime = result.intValue ?? 0
        case "rRuntime":          totalRuntime = result.intValue ?? 0
        case "rChargeStatus":     chargeStatus = result.intValue ?? 0
        case "rTimeFull":         timeToFull = result.intValue ?? 0
        case "rPN":               partNumber = result.stringValue ?? "—"
        default:                  updateBatteryInfoValues(for: result)
        }
    }

    private func updateBatteryInfoValues(for result: RegisterReadResult) {
        switch result.name {
        case "rBms2CycleCountLT":       chargeCycles = result.intValue ?? 0
        case "rBms2RemainCapacityLT":   bmsRemainingCapacity = result.intValue ?? 0
        case "rBms2ManufactureDateLT":  bmsManufactureDate = result.intValue ?? 0
        default:                        updateFirmwareValues(for: result)
        }
    }

    private func updateFirmwareValues(for result: RegisterReadResult) {
        switch result.name {
        case "rCtrlV":  controllerFirmware = result.stringValue ?? "—"
        case "rMCUV":   mcuFirmware = result.stringValue ?? "—"
        case "rBmsV":   bms1Firmware = result.stringValue ?? "—"
        case "rBleV":   bleFirmware = result.stringValue ?? "—"
        default:        break
        }
    }

    /// Populate mock data for App Store screenshots.
    func loadScreenshotData() {
        connectionState = .connected
        isScooterAwake = true
        isRiding = true
        currentSpeed = 47
        currentBattery = 82
        tripDistance = 6.3
        estimatedRange = 38
        gearMode = 3
        bmsTemp = 32.5
        bodyTemp = 28.0
        serialNumber = "03GGG2539C0023"
        odometer = 109.4
        totalRideTime = 7200
        controllerFirmware = "2.1.8"
        mcuFirmware = "1.3.4"
        bms1Firmware = "1.0.9"
        bleFirmware = "1.2.1"
        chargeStatus = 0
        partNumber = "AA.50.0026.10"
        bmsVoltage = 58.2
        bmsCurrent = 12.4
        chargeCycles = 15
        bmsRemainingCapacity = 1890
    }
}
#endif
