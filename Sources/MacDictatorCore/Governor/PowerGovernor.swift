import Foundation

public final class PowerGovernor: @unchecked Sendable {
    public var config: PowerLimitConfig
    public let throttler: ProcessThrottler
    public let lowPowerModeManager: LowPowerModeManager
    private let myPid: Int32

    private var status: GovernorStatus = .inactive
    private let lock = NSLock()

    public init(config: PowerLimitConfig = PowerLimitConfig()) {
        self.config = config
        self.throttler = ProcessThrottler()
        self.lowPowerModeManager = LowPowerModeManager()
        self.myPid = getpid()
    }

    deinit {
        throttler.releaseAll()
        lowPowerModeManager.cleanup()
    }

    public func evaluate(
        reading: PowerReading,
        processes: [MonitoredProcess]
    ) -> (GovernorStatus, [ThrottledProcessInfo]) {
        lock.lock()
        defer { lock.unlock() }

        guard config.isGovernorEnabled else {
            throttler.releaseAll()
            lowPowerModeManager.cleanup()
            let status = GovernorStatus(
                isActive: false,
                isThrottling: false,
                throttledProcessCount: 0,
                statusMessage: "Governor Disabled (Uncapped)"
            )
            self.status = status
            return (status, [])
        }

        let cpuExcess = reading.cpuPowerWatts - config.cpuLimitWatts
        let gpuExcess = reading.gpuPowerWatts - config.gpuLimitWatts
        let socExcess = reading.socTotalWatts - config.totalSocLimitWatts

        let isOverBudget = cpuExcess > 0.05 || gpuExcess > 0.05 || socExcess > 0.05

        // Get candidate processes, excluding system / exempt / self
        let exemptLower = Set(config.exemptProcessNames.map { $0.lowercased() })
        let candidates = processes.filter { proc in
            if proc.pid == myPid || proc.pid <= 1 { return false }
            if exemptLower.contains(proc.name.lowercased()) { return false }
            return true
        }

        if isOverBudget {
            // Power exceeded! Throttle top consumers
            let maxExcess = max(cpuExcess, socExcess)
            let excessRatio = maxExcess / max(0.1, reading.cpuPowerWatts)
            let baseDuty = max(0.10, 1.0 - (excessRatio * 1.3))

            // Throttle top candidate processes
            let topTargets = candidates.prefix(4)
            for proc in topTargets {
                throttler.applyThrottle(pid: proc.pid, targetDutyCycle: baseDuty, strategy: config.strategy)
            }

            if config.lowPowerModeCoordination && excessRatio > 0.3 {
                lowPowerModeManager.setLowPowerMode(enabled: true)
            }
        } else {
            // Within budget! Relax active throttles smoothly
            let throttledDict = throttler.getThrottledPids()
            if reading.cpuPowerWatts < config.cpuLimitWatts * 0.85 {
                for pid in throttledDict.keys {
                    throttler.relaxThrottle(pid: pid, stepUp: 0.15)
                }
                lowPowerModeManager.setLowPowerMode(enabled: false)
            }
        }

        let currentThrottled = throttler.getThrottledPids()
        let throttledCount = currentThrottled.count
        let isThrottling = throttledCount > 0

        let statusMsg: String
        if isOverBudget {
            statusMsg = String(format: "⚠️ Clamping Power: CPU %.1fW (Limit %.1fW)", reading.cpuPowerWatts, config.cpuLimitWatts)
        } else if isThrottling {
            statusMsg = String(format: "🟡 Stabilizing Budget (%d processes governed)", throttledCount)
        } else {
            statusMsg = String(format: "🟢 Within Budget: CPU %.1fW ≤ %.1fW", reading.cpuPowerWatts, config.cpuLimitWatts)
        }

        let newStatus = GovernorStatus(
            isActive: true,
            isThrottling: isThrottling,
            throttledProcessCount: throttledCount,
            statusMessage: statusMsg
        )
        self.status = newStatus

        // Build list of process info for display
        var processInfos: [ThrottledProcessInfo] = []
        for proc in processes.prefix(15) {
            let isExempt = exemptLower.contains(proc.name.lowercased()) || proc.pid == myPid
            let duty = currentThrottled[proc.pid] ?? 1.0
            let isClamped = currentThrottled[proc.pid] != nil

            processInfos.append(ThrottledProcessInfo(
                pid: proc.pid,
                name: proc.name,
                cpuPercent: proc.cpuPercent,
                estimatedWatts: proc.estimatedWatts,
                isClampedToECores: isClamped,
                dutyCyclePercent: duty * 100.0,
                isExempt: isExempt,
                lastThrottledAt: isClamped ? Date() : nil
            ))
        }

        return (newStatus, processInfos)
    }

    public func setExempt(processName: String, exempt: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if exempt {
            if !config.exemptProcessNames.contains(processName) {
                config.exemptProcessNames.append(processName)
            }
        } else {
            config.exemptProcessNames.removeAll { $0.lowercased() == processName.lowercased() }
        }
    }
}
