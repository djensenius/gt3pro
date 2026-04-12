//
//  GT3Registers.swift
//  GT3Companion
//
//  Created by David Jensenius.
//

import Foundation

struct RegisterDefinition: Sendable {
    let name: String
    let board: BLEConstants.Board
    let index: UInt8
    let size: UInt8
    let description: String
}

enum GT3Registers {
    // MARK: - Live Telemetry (poll at 1-2 Hz during rides)

    static let speed = RegisterDefinition(
        name: "rSpeed", board: .vcu, index: 0x57, size: 2,
        description: "Current speed (÷10 = km/h)")
    static let battery = RegisterDefinition(
        name: "rBattery", board: .vcu, index: 0x55, size: 2,
        description: "Combined battery %")
    static let singleMileage = RegisterDefinition(
        name: "rSingleMileage", board: .vcu, index: 0x68, size: 2,
        description: "Trip distance (÷100 = km)")
    static let singleRideTime = RegisterDefinition(
        name: "rSingleRideTime", board: .vcu, index: 0x6A, size: 2,
        description: "Current trip time (seconds)")
    static let runningTime = RegisterDefinition(
        name: "rRunningTime", board: .vcu, index: 0x69, size: 2,
        description: "Session running time (seconds)")
    static let leftMileage = RegisterDefinition(
        name: "rLeftMileage", board: .vcu, index: 0x5F, size: 2,
        description: "Estimated range (÷100 = km)")
    static let bodyTemp = RegisterDefinition(
        name: "rBodyTemp", board: .vcu, index: 0x6B, size: 2,
        description: "Controller temperature (÷10 = °C)")
    static let gearMode = RegisterDefinition(
        name: "rGearMode", board: .vcu, index: 0x5A, size: 2,
        description: "Riding mode (enum)")
    static let errorCode = RegisterDefinition(
        name: "rErrorCode", board: .vcu, index: 0x58, size: 2,
        description: "Active error code")
    static let warnCode = RegisterDefinition(
        name: "rWarnCode", board: .vcu, index: 0x59, size: 2,
        description: "Active warning code")
    static let rBool = RegisterDefinition(
        name: "rBool", board: .vcu, index: 0x1C, size: 2,
        description: "Power/state flags — bit 5 (0x20) = standby, bit 0 (0x01) = powered on")

    // BMS live (only BMS2 responds on GT3 Pro — board 0x07)
    static let bmsVoltage = RegisterDefinition(
        name: "rBMSVolt2", board: .bms2, index: 0x8C, size: 2,
        description: "Battery voltage (÷100 = V)")
    static let bmsCurrent = RegisterDefinition(
        name: "rBMSCur2", board: .bms2, index: 0x8D, size: 2,
        description: "Battery current (÷100 = A, signed)")
    static let bmsSOC = RegisterDefinition(
        name: "rBmsSOC2", board: .bms2, index: 0x8F, size: 2,
        description: "Battery state of charge (%)")
    static let bmsTemp = RegisterDefinition(
        name: "rBmsTmp2", board: .bms2, index: 0x96, size: 4,
        description: "Battery temperature (°C)")

    // MARK: - Cumulative / Diagnostic (read once on connect)

    static let odometer = RegisterDefinition(
        name: "rMileage", board: .vcu, index: 0x62, size: 4,
        description: "Total odometer")
    static let totalRuntime = RegisterDefinition(
        name: "rRuntime", board: .vcu, index: 0x64, size: 4,
        description: "Total power-on time (seconds)")
    static let totalRideTime = RegisterDefinition(
        name: "rRideTime", board: .vcu, index: 0x66, size: 4,
        description: "Total ride time (seconds)")
    static let serialNumber = RegisterDefinition(
        name: "rSN", board: .vcu, index: 0x10, size: 14,
        description: "Serial number (ASCII)")
    static let controllerFW = RegisterDefinition(
        name: "rCtrlV", board: .vcu, index: 0x17, size: 2,
        description: "Controller firmware version")
    static let mcuFW = RegisterDefinition(
        name: "rMCUV", board: .vcu, index: 0x18, size: 2,
        description: "MCU firmware version")
    static let bms1FW = RegisterDefinition(
        name: "rBmsV", board: .vcu, index: 0x19, size: 2,
        description: "BMS firmware version (from VCU)")
    static let bms2FW = RegisterDefinition(
        name: "rBms2V", board: .vcu, index: 0x1A, size: 2,
        description: "BMS2 firmware version (from VCU)")
    static let bleFW = RegisterDefinition(
        name: "rBleV", board: .ble, index: 0x01, size: 2,
        description: "BLE firmware version")
    static let bmsCycleCount = RegisterDefinition(
        name: "rBms2CycleCountLT", board: .bms2, index: 0x59, size: 2,
        description: "Battery charge cycles")
    static let bmsEnergyThroughput = RegisterDefinition(
        name: "rBms2EnergyThroughputLT", board: .bms2, index: 0xE3, size: 4,
        description: "Battery total energy throughput")
    static let bmsCapacityThroughput = RegisterDefinition(
        name: "rBms2CapacityThroughputLT", board: .bms2, index: 0xE1, size: 4,
        description: "Battery total capacity throughput")
    static let bmsDeepDischargeCount = RegisterDefinition(
        name: "rBms2DeepDischargeCountLT", board: .bms2, index: 0x89, size: 2,
        description: "Battery deep discharge count")
    static let bmsRemainingCapacity = RegisterDefinition(
        name: "rBms2RemainCapacityLT", board: .bms2, index: 0x8A, size: 2,
        description: "Battery remaining capacity")
    static let bmsManufactureDate = RegisterDefinition(
        name: "rBms2ManufactureDateLT", board: .bms2, index: 0x0A, size: 2,
        description: "Battery manufacture date")
    static let batterySN = RegisterDefinition(
        name: "rBatterySN2", board: .bms2, index: 0x02, size: 14,
        description: "Battery serial number (ASCII)")
    static let chargeStatus = RegisterDefinition(
        name: "rChargeStatus", board: .bms2, index: 0x92, size: 4,
        description: "Charging status")
    static let timeToFull = RegisterDefinition(
        name: "rTimeFull", board: .bms2, index: 0x94, size: 2,
        description: "Time to full charge (minutes)")
    static let partNumber = RegisterDefinition(
        name: "rPN", board: .vcu, index: 0x20, size: 14,
        description: "Part number")
    static let preciseMileage = RegisterDefinition(
        name: "rPreciseMileage", board: .vcu, index: 0x5E, size: 2,
        description: "High-precision mileage")

    // MARK: - Additional Registers (also captured)

    static let gearED = RegisterDefinition(
        name: "rGearED", board: .vcu, index: 0x47, size: 2,
        description: "Energy recovery / regen braking level")
    static let gearSR = RegisterDefinition(
        name: "rGearSR", board: .vcu, index: 0x48, size: 2,
        description: "Speed response level")
    static let ledMode = RegisterDefinition(
        name: "rLedMode", board: .vcu, index: 0x5B, size: 2,
        description: "LED mode")
    static let projectionLightMode = RegisterDefinition(
        name: "rProjectionLightMode", board: .vcu, index: 0x5C, size: 2,
        description: "Projection light mode")
    static let tailLightMode = RegisterDefinition(
        name: "rTailLightMode", board: .vcu, index: 0x5D, size: 2,
        description: "Tail light mode")
    static let alarmLevel = RegisterDefinition(
        name: "rAlarmLevel", board: .vcu, index: 0x74, size: 2,
        description: "Alarm sensitivity level")
    static let bumpyRoad = RegisterDefinition(
        name: "rBumpyRoad", board: .vcu, index: 0x75, size: 2,
        description: "Bumpy road mode setting")
    static let voiceVolume = RegisterDefinition(
        name: "rVoiceVolume", board: .vcu, index: 0x76, size: 2,
        description: "Speaker volume")
    static let bms1CellVoltages = RegisterDefinition(
        name: "rBmsCellVolFrequence", board: .bms2, index: 0xA0, size: 26,
        description: "Individual cell voltages (26 bytes)")
    static let bms1TempSensors = RegisterDefinition(
        name: "rBmsTempFrequence", board: .bms2, index: 0x96, size: 16,
        description: "Temperature sensor array (16 bytes)")
    static let maxPower = RegisterDefinition(
        name: "rMaxPower", board: .bms2, index: 0x82, size: 2,
        description: "Max power setting")
    static let bmsDesignCapacity = RegisterDefinition(
        name: "rBmsCapacity", board: .bms2, index: 0x13, size: 2,
        description: "Battery design capacity")
    static let findMyStatus = RegisterDefinition(
        name: "rFindMyStatus", board: .ble, index: 0x1D, size: 2,
        description: "Apple Find My integration status")
    static let findMyEnable = RegisterDefinition(
        name: "rFindMyEnable", board: .ble, index: 0x20, size: 2,
        description: "Find My enabled flag")

    // MARK: - Register Groups

    /// Registers to poll at 1-2 Hz during rides
    static let liveTelemetry: [RegisterDefinition] = [
        speed, battery, singleMileage, singleRideTime, runningTime,
        leftMileage, bodyTemp, gearMode, errorCode, warnCode,
        rBool,
        bmsVoltage, bmsCurrent, bmsSOC, bmsTemp,
        gearED, gearSR,
        odometer, chargeStatus
    ]

    /// Registers to read once on connect
    static let cumulative: [RegisterDefinition] = [
        totalRuntime, totalRideTime, serialNumber,
        controllerFW, mcuFW, bms1FW, bms2FW, bleFW,
        bmsCycleCount,
        bmsEnergyThroughput,
        bmsCapacityThroughput,
        bmsDeepDischargeCount,
        bmsRemainingCapacity,
        bmsManufactureDate,
        batterySN,
        timeToFull, partNumber, preciseMileage,
        ledMode, projectionLightMode, tailLightMode,
        alarmLevel, bumpyRoad, voiceVolume,
        bms1CellVoltages, bms1TempSensors,
        maxPower, bmsDesignCapacity,
        findMyStatus, findMyEnable
    ]

    /// All registers
    static let all: [RegisterDefinition] = liveTelemetry + cumulative
}
