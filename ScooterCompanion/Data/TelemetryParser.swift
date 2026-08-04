//
//  TelemetryParser.swift
//  ScooterCompanion
//
//  Created by David Jensenius.
//

import Foundation

enum TelemetryParser {
    /// Parse a UInt16 (little-endian) from data at offset 0.
    static func parseUInt16(_ data: Data) -> UInt16 {
        guard data.count >= 2 else { return 0 }
        return UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    /// Parse a signed Int16 (little-endian) from data.
    static func parseInt16(_ data: Data) -> Int16 {
        Int16(bitPattern: parseUInt16(data))
    }

    /// Parse a UInt32 (little-endian) from data.
    static func parseUInt32(_ data: Data) -> UInt32 {
        guard data.count >= 4 else { return 0 }
        return UInt32(data[data.startIndex])
            | (UInt32(data[data.startIndex + 1]) << 8)
            | (UInt32(data[data.startIndex + 2]) << 16)
            | (UInt32(data[data.startIndex + 3]) << 24)
    }

    /// Parse an ASCII string from data.
    static func parseASCII(_ data: Data) -> String {
        String(data: data, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
    }

    // MARK: - Unit Conversions

    /// Speed: raw ÷ 10 → km/h
    static func parseSpeed(_ data: Data) -> Double {
        Double(parseUInt16(data)) / 10.0
    }

    /// Voltage: raw ÷ 100 → V
    static func parseVoltage(_ data: Data) -> Double {
        Double(parseUInt16(data)) / 100.0
    }

    /// Current: signed raw ÷ 100 → A (negative = discharging)
    static func parseCurrent(_ data: Data) -> Double {
        Double(parseInt16(data)) / 100.0
    }

    /// Temperature: raw ÷ 10 → °C
    static func parseTemperature(_ data: Data) -> Double {
        Double(parseInt16(data)) / 10.0
    }

    /// BMS temperature: 4 bytes = 2 sensors (Int16 each, raw °C, no scaling)
    /// Returns average of two sensor readings
    static func parseBmsTemperature(_ data: Data) -> Double {
        let sensor1 = Double(parseInt16(data))
        if data.count >= 4 {
            let sensor2 = Double(parseInt16(Data(data.suffix(from: data.startIndex + 2))))
            return (sensor1 + sensor2) / 2.0
        }
        return sensor1
    }

    /// Distance: raw ÷ 100 → km
    static func parseDistance(_ data: Data) -> Double {
        Double(parseUInt16(data)) / 100.0
    }

    /// Odometer (4 bytes): raw ÷ 100 → km
    static func parseOdometer(_ data: Data) -> Double {
        Double(parseUInt32(data)) / 100.0
    }

    /// Precise mileage: raw value in meters → km
    static func parsePreciseMileage(_ data: Data) -> Double {
        Double(parseUInt16(data)) / 1000.0
    }

    /// Percentage (raw value is already %)
    static func parsePercent(_ data: Data) -> Int {
        Int(parseUInt16(data))
    }

    /// Time in seconds (2 bytes)
    static func parseSeconds(_ data: Data) -> Int {
        Int(parseUInt16(data))
    }

    /// Time in seconds (4 bytes)
    static func parseSecondsLong(_ data: Data) -> Int {
        Int(parseUInt32(data))
    }

    /// Firmware version: raw → "major.minor" string
    static func parseFirmwareVersion(_ data: Data) -> String {
        let raw = parseUInt16(data)
        let major = raw / 100
        let minor = raw % 100
        return "\(major).\(minor)"
    }

    /// Cell voltages: 26 bytes → array of 13 cell voltages in V
    static func parseCellVoltages(_ data: Data) -> [Double] {
        var voltages: [Double] = []
        var offset = data.startIndex
        while offset + 1 < data.endIndex {
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            voltages.append(Double(raw) / 1000.0)
            offset += 2
        }
        return voltages
    }

    /// Temperature sensor array: 16 bytes → array of temperatures
    static func parseTempSensors(_ data: Data) -> [Double] {
        var temps: [Double] = []
        var offset = data.startIndex
        while offset + 1 < data.endIndex {
            let raw = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
            temps.append(Double(raw) / 10.0)
            offset += 2
        }
        return temps
    }

    // MARK: - Generic Register Dispatch

    // swiftlint:disable:next cyclomatic_complexity
    static func parseRegister(_ register: RegisterDefinition, data: Data) -> Any {
        switch register.name {
        case "rSpeed": return parseSpeed(data)
        case "rBattery": return parsePercent(data)
        case "rSingleMileage", "rLeftMileage": return parseDistance(data)
        case "rPreciseMileage": return parsePreciseMileage(data)
        case "rSingleRideTime", "rRunningTime": return parseSeconds(data)
        case "rBodyTemp": return parseTemperature(data)
        case "rGearMode", "rErrorCode", "rWarnCode",
             "rGearED", "rGearSR", "rLedMode",
             "rProjectionLightMode", "rTailLightMode",
             "rAlarmLevel", "rBumpyRoad", "rVoiceVolume",
             "rMaxPower", "rBmsCapacity",
             "rFindMyStatus", "rFindMyEnable",
             "rBool": return Int(parseUInt16(data))
        case "rBMSVolt2": return parseVoltage(data)
        case "rBMSCur2": return parseCurrent(data)
        case "rBmsSOC2": return parsePercent(data)
        case "rBmsTmp2": return parseBmsTemperature(data)
        case "rMileage": return parseOdometer(data)
        case "rRuntime", "rRideTime",
             "rBmsExtremeUseTimeLT", "rBmsExtremeChargeTimeLT": return parseSecondsLong(data)
        case "rBmsCycleCountLT", "rBms2CycleCountLT",
             "rBmsDeepDischargeCountLT", "rBms2DeepDischargeCountLT",
             "rBmsRemainCapacityLT", "rBms2RemainCapacityLT",
             "rBmsManufactureDateLT", "rBms2ManufactureDateLT",
             "rTimeFull": return Int(parseUInt16(data))
        case "rBmsEnergyThroughputLT", "rBms2EnergyThroughputLT",
             "rBmsCapacityThroughputLT", "rBms2CapacityThroughputLT",
             "rChargeStatus": return Int(parseUInt32(data))
        case "rSN", "rBatterySN", "rBatterySN2", "rPN": return parseASCII(data)
        case "rCtrlV", "rMCUV", "rBmsV", "rBms2V", "rBleV": return parseFirmwareVersion(data)
        case "rBmsCellVolFrequence": return parseCellVoltages(data)
        case "rBmsTempFrequence": return parseTempSensors(data)
        default: return data
        }
    }
}
