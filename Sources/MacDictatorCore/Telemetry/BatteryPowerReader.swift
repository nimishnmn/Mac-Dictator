import Foundation
import IOKit

public struct BatteryPowerReading: Sendable {
    public let watts: Double
    public let isExternalPowerConnected: Bool
    public let isDischarging: Bool
    public let batteryLevelPercent: Int?
    public let updateTimestamp: TimeInterval?
    public let rawAmperageMilliAmps: Double?
    public let voltageMilliVolts: Double?

    public init(
        watts: Double,
        isExternalPowerConnected: Bool,
        isDischarging: Bool,
        batteryLevelPercent: Int?,
        updateTimestamp: TimeInterval? = nil,
        rawAmperageMilliAmps: Double? = nil,
        voltageMilliVolts: Double? = nil
    ) {
        self.watts = watts
        self.isExternalPowerConnected = isExternalPowerConnected
        self.isDischarging = isDischarging
        self.batteryLevelPercent = batteryLevelPercent
        self.updateTimestamp = updateTimestamp
        self.rawAmperageMilliAmps = rawAmperageMilliAmps
        self.voltageMilliVolts = voltageMilliVolts
    }
}

public enum BatteryPowerReader {
    public static func read() -> BatteryPowerReading? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let entry = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let isExternal = (dict["ExternalConnected"] as? Bool) ?? (dict["AppleRawExternalConnected"] as? Bool) ?? false
        let isCharging = (dict["IsCharging"] as? Bool) ?? false
        let curCap = (dict["CurrentCapacity"] as? Int) ?? 0
        let maxCap = (dict["MaxCapacity"] as? Int) ?? 100
        let percent = maxCap > 0 ? Int((Double(curCap) / Double(maxCap)) * 100.0) : nil
        let updateTime = (dict["UpdateTime"] as? NSNumber)?.doubleValue

        var measuredWatts: Double?
        var parsedAmps: Double?
        var parsedVolts: Double?

        // Prioritize instantaneous current * voltage
        if let voltRaw = dict["AppleRawBatteryVoltage"] as? NSNumber ?? dict["Voltage"] as? NSNumber,
           let ampRaw = dict["InstantAmperage"] as? NSNumber ?? dict["Amperage"] as? NSNumber {
            let voltMv = voltRaw.doubleValue
            let ampVal = ampRaw.int64Value
            let ampMa: Double
            if ampVal < 0 {
                ampMa = Double(-ampVal)
            } else if ampVal > 10_000_000 {
                ampMa = Double(UInt64.max - UInt64(ampVal))
            } else {
                ampMa = Double(ampVal)
            }

            parsedVolts = voltMv
            parsedAmps = ampMa

            if voltMv > 5000.0 && ampMa > 20.0 {
                let w = (voltMv * ampMa) / 1_000_000.0
                if w > 0.5 && w < 180.0 {
                    measuredWatts = w
                }
            }
        }

        // Secondary fallback to PowerTelemetryData.SystemLoad only if instant reading is missing
        if measuredWatts == nil,
           let telemetry = dict["PowerTelemetryData"] as? [String: Any],
           let sysLoadRaw = telemetry["SystemLoad"] as? NSNumber {
            let sysLoad = sysLoadRaw.doubleValue
            if sysLoad > 100.0 && sysLoad < 180_000.0 {
                measuredWatts = sysLoad / 1000.0
            }
        }

        guard let watts = measuredWatts else { return nil }

        return BatteryPowerReading(
            watts: watts,
            isExternalPowerConnected: isExternal,
            isDischarging: !isExternal && !isCharging,
            batteryLevelPercent: percent,
            updateTimestamp: updateTime,
            rawAmperageMilliAmps: parsedAmps,
            voltageMilliVolts: parsedVolts
        )
    }
}
