import Foundation

public enum ThrottleStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case eCoreClampOnly = "E-Core Clamp (Smooth)"
    case dynamicDutyCycle = "Dynamic Duty-Cycle (Strict)"
    case strictLockdown = "Aggressive Lockdown"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .eCoreClampOnly:
            return "Migrates intensive threads to high-efficiency cores (PRIO_DARWIN_BG). Minimal stutter, lower power."
        case .dynamicDutyCycle:
            return "Combines E-core migration with microsecond PID duty-cycling (SIGSTOP/SIGCONT) to strictly enforce the wattage ceiling."
        case .strictLockdown:
            return "Immediately suppresses any process pushing CPU/GPU beyond the target watt threshold."
        }
    }
}

public struct HardwareProfile: Codable, Sendable {
    public let chipName: String
    public let modelIdentifier: String
    public let totalCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let memoryBytes: Int64
    public let isLaptop: Bool
    public let baseIdleWatts: Double
    public let ratedMaxTdpWatts: Double

    public var memoryGB: Double {
        Double(memoryBytes) / 1_073_741_824.0
    }
}

public struct PowerReading: Codable, Sendable {
    public let timestamp: Date
    public let cpuPowerWatts: Double
    public let gpuPowerWatts: Double
    public let anePowerWatts: Double
    public let socTotalWatts: Double
    public let systemTotalWatts: Double
    public let cpuUtilization: Double // 0.0 - 100.0%
    public let gpuUtilization: Double // 0.0 - 100.0%
    public let isBatteryPowered: Bool
    public let rawBatteryWatts: Double?
    public let rawBatteryAgeSeconds: Int?

    public init(
        timestamp: Date = Date(),
        cpuPowerWatts: Double,
        gpuPowerWatts: Double,
        anePowerWatts: Double = 0.0,
        socTotalWatts: Double,
        systemTotalWatts: Double,
        cpuUtilization: Double,
        gpuUtilization: Double,
        isBatteryPowered: Bool,
        rawBatteryWatts: Double? = nil,
        rawBatteryAgeSeconds: Int? = nil
    ) {
        self.timestamp = timestamp
        self.cpuPowerWatts = max(0.0, cpuPowerWatts)
        self.gpuPowerWatts = max(0.0, gpuPowerWatts)
        self.anePowerWatts = max(0.0, anePowerWatts)
        self.socTotalWatts = max(0.0, socTotalWatts)
        self.systemTotalWatts = max(0.0, systemTotalWatts)
        self.cpuUtilization = min(100.0, max(0.0, cpuUtilization))
        self.gpuUtilization = min(100.0, max(0.0, gpuUtilization))
        self.isBatteryPowered = isBatteryPowered
        self.rawBatteryWatts = rawBatteryWatts
        self.rawBatteryAgeSeconds = rawBatteryAgeSeconds
    }

    public static var zero: PowerReading {
        PowerReading(
            timestamp: Date(),
            cpuPowerWatts: 0.0,
            gpuPowerWatts: 0.0,
            anePowerWatts: 0.0,
            socTotalWatts: 0.0,
            systemTotalWatts: 0.0,
            cpuUtilization: 0.0,
            gpuUtilization: 0.0,
            isBatteryPowered: false
        )
    }
}

public struct PowerLimitConfig: Codable, Sendable {
    public var isGovernorEnabled: Bool
    public var cpuLimitWatts: Double
    public var gpuLimitWatts: Double
    public var totalSocLimitWatts: Double
    public var strategy: ThrottleStrategy
    public var sampleIntervalSeconds: Double
    public var lowPowerModeCoordination: Bool
    public var exemptProcessNames: [String]

    public init(
        isGovernorEnabled: Bool = false,
        cpuLimitWatts: Double = 5.0,
        gpuLimitWatts: Double = 3.0,
        totalSocLimitWatts: Double = 8.0,
        strategy: ThrottleStrategy = .dynamicDutyCycle,
        sampleIntervalSeconds: Double = 0.5,
        lowPowerModeCoordination: Bool = true,
        exemptProcessNames: [String] = ["WindowServer", "loginwindow", "launchd", "Dock", "Finder", "MacDictator", "Antigravity"]
    ) {
        self.isGovernorEnabled = isGovernorEnabled
        self.cpuLimitWatts = cpuLimitWatts
        self.gpuLimitWatts = gpuLimitWatts
        self.totalSocLimitWatts = totalSocLimitWatts
        self.strategy = strategy
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.lowPowerModeCoordination = lowPowerModeCoordination
        self.exemptProcessNames = exemptProcessNames
    }
}

public struct ThrottledProcessInfo: Identifiable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let estimatedWatts: Double
    public let isClampedToECores: Bool
    public let dutyCyclePercent: Double // 100% = full speed, 25% = heavily throttled
    public let isExempt: Bool
    public let lastThrottledAt: Date?

    public init(
        pid: Int32,
        name: String,
        cpuPercent: Double,
        estimatedWatts: Double,
        isClampedToECores: Bool,
        dutyCyclePercent: Double,
        isExempt: Bool = false,
        lastThrottledAt: Date? = nil
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.estimatedWatts = estimatedWatts
        self.isClampedToECores = isClampedToECores
        self.dutyCyclePercent = dutyCyclePercent
        self.isExempt = isExempt
        self.lastThrottledAt = lastThrottledAt
    }
}

public struct GovernorStatus: Sendable {
    public let isActive: Bool
    public let isThrottling: Bool
    public let throttledProcessCount: Int
    public let statusMessage: String

    public init(
        isActive: Bool,
        isThrottling: Bool,
        throttledProcessCount: Int,
        statusMessage: String
    ) {
        self.isActive = isActive
        self.isThrottling = isThrottling
        self.throttledProcessCount = throttledProcessCount
        self.statusMessage = statusMessage
    }

    public static var inactive: GovernorStatus {
        GovernorStatus(
            isActive: false,
            isThrottling: false,
            throttledProcessCount: 0,
            statusMessage: "Governor Inactive (Monitoring Only)"
        )
    }
}
